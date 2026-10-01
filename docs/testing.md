# Testing

```bash
mix test
```

```
14 doctests, 8 properties, 63 tests, 0 failures
```

Every test runs `async: true`, since sorting has no shared state.

## Three layers

**Doctests.** The examples in `@doc` are run, so the docs can't drift from the code.
`Response.negotiate/1` is specified entirely by its doctests.

**Property tests** (`sorter_property_test.exs`) check invariants on generated graphs:

- nothing is dropped or duplicated
- every task comes after everything it requires
- input order doesn't change the result
- sorting the output again changes nothing

Generated graphs are acyclic by construction (task `i` only requires lower-indexed tasks). Cycles,
unknown dependencies and duplicate names are generated separately and must fail.

**Example tests** cover the cases from the brief and every error response. Requests are sent as real
JSON, so `Plug.Parsers` always runs.

## The server test

`server_test.exs` is the only test that opens a socket. Everything else calls `Router.call/2`
directly, which skips Bandit and its config — so a bad Bandit option would pass the rest of the suite
and only fail at boot.

It connects to the listener the app started. The test port is 0, so it asks Thousand Island which
port was bound. The request is raw HTTP over `:gen_tcp`, so no HTTP client is needed.

## The properties catch real bugs

Checked by breaking the code on purpose:

- removing the final `Enum.reverse/1` fails with a three-task counterexample
- removing the duplicate-name check fails immediately

## Full check

```bash
mix check
```

Runs `format --check-formatted`, `compile --warnings-as-errors`, `credo --strict`, the tests and
`dialyzer` (with `error_handling`, `extra_return`, `missing_return` and `unmatched_returns`).

The test step is `mix cmd env MIX_ENV=test mix test`, not plain `test`. Alias steps run in the
environment the alias was called from, so a bare `test` would run in `:dev`.
