defmodule JobProcessor.MixProject do
  use Mix.Project

  def project do
    [
      app: :job_processor,
      version: "0.3.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :extra_return, :missing_return, :unmatched_returns]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {JobProcessor.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:plug, "~> 1.18"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "credo --strict",
        "cmd env MIX_ENV=test mix test",
        "dialyzer"
      ]
    ]
  end
end
