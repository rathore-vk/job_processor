# Architecture

```
┌──────────────────────────────────────────────────┐
│              HTTP (Plug on Bandit)               │
│        Router → TaskController → Response        │
│       Response maps domain errors → status       │
├──────────────────────────────────────────────────┤
│      JobProcessor.Tasks (context boundary)       │
│                   sort_tasks/1                   │
├────────────────┬────────────────┬────────────────┤
│      Task      │   Validation   │     Sorter     │
│    (parse)     │ (graph checks) │  (depth-first) │
├────────────────┴────────────────┴────────────────┤
│               OTP Supervision Tree               │
│                      Bandit                      │
└──────────────────────────────────────────────────┘
```

Sorting is a pure function with no state, so the supervision tree only holds the Bandit listener and
every test runs `async: true`.

`JobProcessor.Tasks.sort_tasks/1` is the only function the web layer calls. It takes the decoded
request maps and runs three steps, each owning one kind of failure:

1. `Task` — parses each map; rejects malformed tasks
2. `Validation` — rejects duplicate names and unknown `requires`
3. `Sorter` — orders the tasks; the only failure left is a cycle

Nothing below the context knows about HTTP, which is why [removing Phoenix](why-no-phoenix.md) didn't
touch it.

## Request pipeline

```
Plug.RequestId → Plug.Logger → Plug.Telemetry → :match → :parse_body → :dispatch
```

The body is parsed after `:match`, so unknown routes skip parsing. `Plug.Parsers` raises on an
oversized body or invalid JSON; the router turns those into 413 and 400.

## Configuration

| Environment | Port | Interface | Log level |
|---|---|---|---|
| dev | 8080 | `127.0.0.1` | `:debug` |
| test | 0 (any free port) | `127.0.0.1` | `:warning` |
| prod | `PORT`, default 8080 | `0.0.0.0` | `:info` |

`config :job_processor, :http` is passed straight to Bandit, so any Bandit option can be set per
environment. Bandit rejects unknown keys, so a typo fails at startup.

Only `:prod` listens on all interfaces, so a dev server isn't exposed to the network.

The test listener uses port 0 to avoid clashing with a dev server. Most tests call the router
directly; only [one](testing.md#the-server-test) opens a socket.

## Layout

```
job_processor/
├── config/                          # One file per environment
├── docs/
├── lib/
│   ├── job_processor/
│   │   ├── application.ex           # Supervision tree (Bandit)
│   │   ├── tasks.ex                 # Context: sort_tasks/1
│   │   └── tasks/
│   │       ├── sorter.ex            # Depth-first sort, cycle detection
│   │       ├── task.ex              # Task struct and parsing
│   │       └── validation.ex        # Duplicate names, unknown requires
│   └── job_processor_web/
│       ├── response.ex              # Accept negotiation, rendering, error → status
│       ├── router.ex                # Plug pipeline and routes
│       └── task_controller.ex       # POST /tasks
├── test/
│   ├── job_processor/
│   │   ├── tasks/
│   │   │   ├── sorter_property_test.exs   # Invariants over generated graphs
│   │   │   ├── sorter_test.exs
│   │   │   ├── task_test.exs
│   │   │   └── validation_test.exs
│   │   └── tasks_test.exs
│   ├── job_processor_web/
│   │   ├── response_test.exs        # Negotiation doctests
│   │   ├── server_test.exs          # Real socket to the Bandit listener
│   │   └── task_controller_test.exs
│   └── support/
│       └── conn_case.ex             # Router test helpers
└── mix.exs
```
