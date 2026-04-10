defmodule Tinfoil do
  @moduledoc """
  tinfoil — distribution automation for Burrito-based Elixir CLIs.

  Be to Burrito what cargo-dist is to Cargo: a single tool that takes
  your `mix release` output to platform binaries in a GitHub Release,
  with Homebrew and installer support.

  The v0.1 story is **generate-and-forget**: `mix tinfoil.init` writes
  a self-contained GitHub Actions workflow that drives the whole
  release pipeline without needing tinfoil on the CI runners. Later
  versions evolve the workflow to call `mix tinfoil.*` tasks directly.

  See the `Mix.Tasks.Tinfoil.Init` and `Mix.Tasks.Tinfoil.Generate`
  moduledocs for usage.
  """

  alias Tinfoil.Config

  @doc """
  Load the current mix project's tinfoil config.

  This is a convenience wrapper around `Tinfoil.Config.load/1` that
  reads from `Mix.Project.config/0`.
  """
  @spec config() :: {:ok, Config.t()} | {:error, term()}
  def config do
    Config.load(Mix.Project.config())
  end

  @doc "Load the current mix project's tinfoil config, raising on error."
  @spec config!() :: Config.t()
  def config! do
    Config.load!(Mix.Project.config())
  end

  @doc "Return the tinfoil package version."
  @spec version() :: String.t()
  def version do
    Application.spec(:tinfoil, :vsn) |> to_string()
  end
end
