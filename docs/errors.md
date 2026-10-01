# Errors are values, not exceptions

Every expected failure is a tagged tuple that tells the client what to fix:

```elixir
{:invalid_task, index}
{:duplicate_task, name}
{:missing_dependency, name}
{:circular_dependency, name}
```

`JobProcessor.Tasks.error/0` is the full list. `Response.describe/1` is the only place they become
status codes, so a new failure means one new clause, and Dialyzer flags any you miss.

Each error points at something specific — an index or a name — because "the tasks are invalid" is
useless when a client sends two hundred of them.

For a cycle, the name is the task where the walk looped back on itself, so it's always *in* the
cycle, never just stuck behind it. Only the first cycle found is reported; fixing it may reveal
another.

## Two traps

**`requires: null`.** `Map.get(attrs, "requires", [])` only defaults when the key is *missing*. An
explicit `null` returns `nil`, which would fail later somewhere unhelpful. So it's rejected up front,
and a doctest covers it.

**Duplicate names.** Tasks are looked up by name, so duplicates would silently merge and one would
disappear from the response. `Validation` rejects them with a 422 instead.

## Real exceptions

`Plug.ErrorHandler` renders anything that escapes as a JSON 500. Since expected failures are values,
this only happens on a bug. Plug re-raises afterwards, so the crash is still reported.
