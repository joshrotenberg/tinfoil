defmodule Tinfoil.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/joshrotenberg/tinfoil"

  def project do
    [
      app: :tinfoil,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      name: "tinfoil",
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:plug, "~> 1.0", only: :test}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :eex],
      plt_file: {:no_warn, "priv/plts/tinfoil.plt"},
      flags: [:error_handling, :unknown, :underspecs]
    ]
  end

  defp description do
    "Distribution automation for Burrito-based Elixir CLIs. " <>
      "Generate CI workflows, GitHub Releases, Homebrew formulas, and installer scripts."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
