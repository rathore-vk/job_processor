# API reference

One endpoint: `POST /tasks`. It returns the tasks in a valid execution order. It does not run them.

## Request

```json
{
  "tasks": [
    {"name": "task-1", "command": "touch /tmp/file1"},
    {"name": "task-2", "command": "cat /tmp/file1", "requires": ["task-3"]},
    {"name": "task-3", "command": "echo 'Hello World!' > /tmp/file1", "requires": ["task-1"]},
    {"name": "task-4", "command": "rm /tmp/file1", "requires": ["task-2", "task-3"]}
  ]
}
```

- `name` and `command` must be strings.
- `requires` is optional. If present, it must be a list of strings. `null` is rejected rather than
  treated as missing, so client bugs show up early.
- An empty list is valid and returns `{"tasks": []}`.

## Responses

The `Accept` header picks the format.

### JSON

`requires` is left out — the order already reflects it.

```json
{
  "tasks": [
    {"name": "task-1", "command": "touch /tmp/file1"},
    {"name": "task-3", "command": "echo 'Hello World!' > /tmp/file1"},
    {"name": "task-2", "command": "cat /tmp/file1"},
    {"name": "task-4", "command": "rm /tmp/file1"}
  ]
}
```

### Bash script

```bash
#!/usr/bin/env bash

touch /tmp/file1
echo 'Hello World!' > /tmp/file1
cat /tmp/file1
rm /tmp/file1
```

Commands are output exactly as sent — never rewritten or re-quoted.

## Content negotiation

The first supported type in `Accept` wins. Parameters like `;q=` are ignored.

| `Accept` | Response |
|---|---|
| absent, empty, `*/*`, `application/*`, `application/json` | JSON |
| `text/plain`, `text/*` | bash script |
| anything else (e.g. `application/xml`) | 406 |

Unsupported types are skipped, so `application/xml, text/plain` returns the script.

## Errors

| Status | When |
|--------|------|
| 400 | Invalid JSON, body isn't `{"tasks": [...]}`, or an invalid task (the message gives its index) |
| 404 | Unknown route, or a method other than `POST` on `/tasks` |
| 406 | Unsupported `Accept` header |
| 413 | Body over Plug's 8 MB default |
| 422 | Circular dependency, missing dependency or duplicate name (the message names the task) |

Every error is `{"error": "..."}`. See [Errors are values](errors.md).

A cycle is reported by naming one task in it:

```json
{"error": "Tasks contain a circular dependency involving task-1"}
```

## Limits

The only limit is Plug's 8 MB body size, which returns 413. The number of tasks isn't capped.

**Memory.** Decoded tasks take about 3–8× the body size, so an 8 MB body is roughly 25–60 MB per
request in flight. Multiply by concurrency for the real ceiling.

**CPU.** Sort time grows linearly with tasks and dependencies. A minimal task is about 32 bytes, so
8 MB is around 250,000 tasks:

| Independent tasks | Sort time |
|---|---|
| 5,000 | 3.8 ms |
| 10,000 | 7.9 ms |
| 20,000 | 17.2 ms |
| 250,000 | 319.3 ms |

So memory, not CPU, is the real constraint. More shapes in [Sorting](sorting.md#cost).

For a public deployment, set a body limit and request timeout at the reverse proxy — the service
enforces neither.

## Verifying the order

`task-2` runs `cat /tmp/file1`, which only works if `task-1` and `task-3` ran first. Piping the
script to bash tests the order for real:

```bash
curl -s -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" -H "Accept: text/plain" \
  -d '{"tasks":[{"name":"task-1","command":"touch /tmp/file1"},{"name":"task-2","command":"cat /tmp/file1","requires":["task-3"]},{"name":"task-3","command":"echo '\''Hello World!'\'' > /tmp/file1","requires":["task-1"]},{"name":"task-4","command":"rm /tmp/file1","requires":["task-2","task-3"]}]}' \
  | tee /tmp/sorted.sh | bash
echo "exit status: $?"
```

```
Hello World!
exit status: 0
```

> [!NOTE]
> Check `/tmp/sorted.sh` before running it. It contains the commands you sent, so it is only as safe
> as your request.
