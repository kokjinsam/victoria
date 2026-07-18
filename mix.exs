defmodule Victoria.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kokjinsam/victoria"

  def project do
    [
      app: :victoria,
      version: @version,
      elixir: "~> 1.20",
      description: "Model-based testing lib for TLA+",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      source_url: @source_url,
      package: package(),
      aliases: aliases()
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
      {:code_style, "~> 0.1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.11.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "victoria",
      licenses: ["MIT"],
      links: %{"Source" => @source_url},
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE"
      ]
    ]
  end

  def cli do
    [preferred_envs: [check: :test, dialyzer: :dev]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end
end
