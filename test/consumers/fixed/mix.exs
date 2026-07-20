defmodule VictoriaFixedConsumer.MixProject do
  use Mix.Project

  def project do
    [app: :victoria_fixed_consumer, version: "0.0.0", elixir: "~> 1.18", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [{:victoria, path: System.fetch_env!("VICTORIA_PACKAGE_PATH")}]
  end
end
