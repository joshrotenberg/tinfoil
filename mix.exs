defmodule Tinfoil.MixProject do
  use Mix.Project

  @version "0.2.16"
  @source_url "https://github.com/joshrotenberg/tinfoil"

  def project do
    [
      app: :tinfoil,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Hex" => "https://hex.pm/packages/tinfoil"
      },
      files: ~w(lib priv/templates mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        "Public API": [
          Tinfoil,
          Tinfoil.Config,
          Tinfoil.Target,
          Tinfoil.Plan
        ],
        "Build lifecycle": [
          Tinfoil.Build,
          Tinfoil.Archive,
          Tinfoil.Publish
        ],
        Integration: [
          Tinfoil.Burrito,
          Tinfoil.Generator
        ],
        "Mix tasks": [
          Mix.Tasks.Tinfoil.Init,
          Mix.Tasks.Tinfoil.Generate,
          Mix.Tasks.Tinfoil.Plan,
          Mix.Tasks.Tinfoil.Build,
          Mix.Tasks.Tinfoil.Publish
        ]
      ]
    ]
  end
end
