defmodule JobProcessor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Bandit, [plug: JobProcessorWeb.Router] ++ Application.get_env(:job_processor, :http, [])}
    ]

    opts = [strategy: :one_for_one, name: JobProcessor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
