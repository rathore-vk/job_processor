import Config

# Passed straight to Bandit. Loopback by default; only :prod listens on all interfaces.
config :job_processor, :http, port: 8080, ip: :loopback

config :logger, :default_formatter,
  format: "$time [$level] $message $metadata\n",
  metadata: [
    :state,
    :requires,
    :remaining,
    :visited,
    :stack,
    :task,
    :tasks,
    :order
  ]

import_config "#{config_env()}.exs"
