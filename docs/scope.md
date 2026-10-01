# Scope: what was left out

The brief asks for a service that *sorts* tasks, not one that runs them, and defines a job as the
request itself. So there's no `/jobs` endpoint, no storage and no execution. The bash output leaves
execution to the caller.

## What running jobs would need

- **A `GenServer` per job under a `DynamicSupervisor`**, with `restart: :temporary` so a half-run job
  is never retried. Sorting itself should stay out of a `GenServer` — that would serialise work that
  currently runs on every core.
- **Owning the OS process directly.** `System.cmd/3` in a `Task` with `Task.shutdown/2` kills the
  Elixir process but leaves the command running. `Port.close/1` doesn't signal it either (tested on
  OTP 28). A real timeout has to kill the process tree — on macOS by walking `ps -axo pid=,ppid=`.
- **`trap_exit` plus `terminate/2`**, so a job can't get stuck in `:running`. Tasks should be driven
  by self-sent messages, not chained `handle_continue/2`, so the process can still react to shutdown.
- **ETS as `:protected`**, so only the owner writes. Reads go through `:ets.whereis/1`, so a missing
  table returns `{:error, :store_unavailable}` instead of crashing.

> [!NOTE]
> These are built and tested on the `exploration/job-execution` branch, which adds `POST /jobs`. It
> isn't on `main` because the brief doesn't ask for it. Without `.git` the branch won't be there.
>
> ```bash
> git switch exploration/job-execution
> ```

## Also left out

- **No database.** Nothing outlives a request.
- **No job queue.** The work is stateless and takes well under a second.
- **No storage behaviour.** One implementation doesn't need an abstraction.
- **No caching.** Only worth it if clients resend identical payloads.
