defmodule ReqCassette.MixProject do
  use Mix.Project

  def project do
    [
      app: :req_cassette,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        precommit: :test,
        ci: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.15"},
      {:plug, "~> 1.18"},
      {:jason, "~> 1.4"},
      {:req_llm, "~> 1.0.0-rc.5", only: [:dev, :test], runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases for common tasks
  defp aliases do
    [
      precommit: [
        "format",
        "credo --strict",
        "test"
      ],
      ci: [
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end
end
