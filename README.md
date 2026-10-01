# Job Processor

An HTTP service that takes tasks with dependencies and returns them in a valid execution order, as
JSON or as a bash script.

It only **sorts** tasks — it never runs them. The caller decides whether to execute the script.

Built with Elixir 1.19 / OTP 28, [Plug](https://hex.pm/packages/plug) and
[Bandit](https://hex.pm/packages/bandit). No Phoenix — see [why](docs/why-no-phoenix.md).

## Features

- **Topological sort** — depth-first; each task comes after everything it requires
- **Rejects bad input** — cycles, missing dependencies and duplicate names return 422
- **Deterministic** — the same set of tasks always gives the same order, whatever order they're sent in
- **JSON or bash** — chosen by the `Accept` header
- **JSON errors everywhere** — `{"error": "..."}`, including 404 and 500

The only input limit is Plug's 8 MB body size. See [Limits](docs/api.md#limits).

## Tests

```bash
mix test     # 14 doctests, 8 properties, 63 tests
mix check    # format, compile --warnings-as-errors, credo --strict, tests, dialyzer
```

See [Testing](docs/testing.md).

## Repository map

A request flows router → controller → `Tasks` → parse, validate, sort.

```
job_processor/
├── config/                          # Port, interface and log level per environment
├── docs/                            # Design notes, listed below
├── lib/
│   ├── job_processor/
│   │   ├── application.ex           # Supervision tree (the Bandit listener)
│   │   ├── tasks.ex                 # Context: sort_tasks/1, the only entry point to the domain
│   │   └── tasks/
│   │       ├── task.ex              # Task struct and payload parsing
│   │       ├── validation.ex        # Duplicate names, unknown requires
│   │       └── sorter.ex            # Depth-first sort and cycle detection
│   └── job_processor_web/
│       ├── router.ex                # Plug pipeline and routes; parser errors → 400/413
│       ├── task_controller.ex       # POST /tasks
│       └── response.ex              # Accept negotiation, JSON/bash rendering, error → status
├── test/
│   ├── job_processor/               # Domain tests, including sorter property tests
│   ├── job_processor_web/           # HTTP tests through the router, plus one real socket
│   └── support/
│       └── conn_case.ex             # Router test helpers
└── mix.exs
```

## Docs

| | |
|---|---|
| [API reference](docs/api.md) | Request, responses, errors, limits |
| [Architecture](docs/architecture.md) | Layers, request pipeline, config, file layout |
| [Sorting](docs/sorting.md) | How the sort works, determinism, cost |
| [Errors](docs/errors.md) | Why failures are values, not exceptions |
| [Testing](docs/testing.md) | Test layers and `mix check` |
| [Why there is no Phoenix](docs/why-no-phoenix.md) | What Phoenix did here and what replaced it |
| [Scope](docs/scope.md) | What was left out on purpose |

## How to run and test

### 1. Prerequisites

Elixir 1.19 and Erlang/OTP 28. Exact versions are pinned in [`.tool-versions`](.tool-versions), so
with [asdf](https://asdf-vm.com) or [mise](https://mise.jdx.dev):

```bash
asdf install        # or: mise install
```

`curl` and `bash` are used for the manual checks below.

### 2. Start the server

```bash
mix deps.get
mix run --no-halt        # listens on port 8080
```

Leave it running and use a second terminal for the rest.

### 3. Save the example request

The example from the brief, saved once so the commands below stay short:

```bash
cat > /tmp/tasks.json <<'JSON'
{
  "tasks": [
    {"name": "task-1", "command": "touch /tmp/file1"},
    {"name": "task-2", "command": "cat /tmp/file1", "requires": ["task-3"]},
    {"name": "task-3", "command": "echo 'Hello World!' > /tmp/file1", "requires": ["task-1"]},
    {"name": "task-4", "command": "rm /tmp/file1", "requires": ["task-2", "task-3"]}
  ]
}
JSON
```

### 4. Get the order as JSON

```bash
curl -s -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d @/tmp/tasks.json
```

```json
{"tasks":[{"name":"task-1","command":"touch /tmp/file1"},{"name":"task-3","command":"echo 'Hello World!' > /tmp/file1"},{"name":"task-2","command":"cat /tmp/file1"},{"name":"task-4","command":"rm /tmp/file1"}]}
```

### 5. Get the order as a bash script

Same request, with `Accept: text/plain`:

```bash
curl -s -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -H "Accept: text/plain" \
  -d @/tmp/tasks.json
```

```bash
#!/usr/bin/env bash

touch /tmp/file1
echo 'Hello World!' > /tmp/file1
cat /tmp/file1
rm /tmp/file1
```

### 6. Run the script

Save it, look at it, then run it:

```bash
curl -s -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -H "Accept: text/plain" \
  -d @/tmp/tasks.json \
  -o /tmp/sorted.sh

cat /tmp/sorted.sh       # check what it will run
bash /tmp/sorted.sh; echo "exit status: $?"
```

```
Hello World!
exit status: 0
```

This proves the order: `cat /tmp/file1` only prints `Hello World!` if `touch` and `echo` ran before
it. In the wrong order it fails with `No such file or directory` and a non-zero exit status.

> [!NOTE]
> The script runs exactly the commands in the request, so only run scripts built from requests you
> trust.

### Error cases

```bash
# Circular dependency → 422
curl -s -X POST http://localhost:8080/tasks -H "Content-Type: application/json" \
  -d '{"tasks":[{"name":"a","command":"echo a","requires":["b"]},{"name":"b","command":"echo b","requires":["a"]}]}'
# {"error":"Tasks contain a circular dependency involving a"}

# Unknown dependency → 422
curl -s -X POST http://localhost:8080/tasks -H "Content-Type: application/json" \
  -d '{"tasks":[{"name":"a","command":"echo a","requires":["ghost"]}]}'
# {"error":"Task depends on non-existent task: ghost"}
```

All status codes are listed in the [API reference](docs/api.md#errors).
