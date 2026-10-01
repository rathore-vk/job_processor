import Config

# Any free port, so tests never clash with a dev server. `server_test.exs` looks it up.
config :job_processor, :http, port: 0

config :logger, level: :warning
