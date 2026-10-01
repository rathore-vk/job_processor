# Why there is no Phoenix

The service started on Phoenix, but it only used routing for one `POST`, JSON encoding and test
helpers — no channels, LiveView, templates, sessions or Ecto.

That's what `Plug.Router` and Bandit already provide. Removing Phoenix dropped four dependencies and
**114 modules** (`phoenix` 93, `phoenix_pubsub` 14, `phoenix_template` 4, `websock_adapter` 3).
Nothing under `JobProcessor.Tasks` changed.

| Phoenix | Replacement |
|---|---|
| `Phoenix.Endpoint` | `{Bandit, plug: Router}` in `application.ex` |
| `Phoenix.Router` | `Plug.Router` — one `post` and a catch-all `match _` |
| `Phoenix.Controller` | `send_resp/3` in `Response` |
| `action_fallback` | the `with/else` in `TaskController.create/1` |
| `plug :accepts` | `Response.negotiate/1`, ~20 lines with doctests |
| `Phoenix.ConnTest` | `Plug.Test.conn/3` plus helpers in `ConnCase` |

Two things got better:

- **Errors are always JSON.** With Phoenix, `dev` returned HTML error pages for 404 and 406. Now
  every error is the same JSON in every environment.
- **Every test goes through `Plug.Parsers`.** Phoenix's `post/3` with a map skips the parser. Now
  requests are real JSON, and parser errors are tested as normal responses.

The trade-off: Phoenix is the convention, so a hand-rolled pipeline needs explaining. The table above
is that explanation.
