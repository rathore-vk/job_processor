import Config

# Reachable from outside the container.
config :job_processor, :http,
  port: String.to_integer(System.get_env("PORT") || "8080"),
  ip: :any

config :logger, level: :info
