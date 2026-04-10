defmodule Tinfoil do
  @moduledoc """
  Distribution automation for Burrito-based Elixir CLIs.

  Tinfoil is to [Burrito](https://github.com/burrito-elixir/burrito) what
  [cargo-dist](https://opensource.axo.dev/cargo-dist/) is to Cargo: a
  single tool that takes your `mix release` output to platform binaries
  in a GitHub Release, with Homebrew and installer support.

  ## What tinfoil does

    * Generates a complete GitHub Actions workflow (`.github/workflows/release.yml`)
      from a `:tinfoil` keyword in `mix.exs`
    * Reads the user's Burrito release config and resolves tinfoil's
      abstract target atoms (`:darwin_arm64`, `:linux_x86_64`, …) against
      the user's chosen Burrito target names by matching `[os:, cpu:]`
    * At CI time, drives one `mix tinfoil.build` per matrix entry: sets
      `BURRITO_TARGET`, runs `mix release`, packages the binary, writes a
      `sha256` sidecar
    * After all matrix builds finish, drives `mix tinfoil.publish` to
      create a GitHub Release via the REST API and upload every archive
      plus a combined `checksums-sha256.txt`
    * Optionally generates an `install.sh` curl-able installer and a
      Homebrew formula template

  ## Where to start

    * `Mix.Tasks.Tinfoil.Init` — interactive scaffold for new projects
    * `Mix.Tasks.Tinfoil.Plan` — read-only preview of what would be built
    * `Mix.Tasks.Tinfoil.Build` — single-target build + package + checksum
    * `Mix.Tasks.Tinfoil.Publish` — create GitHub Release and upload assets
    * `Tinfoil.Config` — the schema, defaults, and validation for
      everything under the `:tinfoil` keyword in `mix.exs`
    * `Tinfoil.Target` — the target matrix that maps tinfoil atoms to
      GitHub runners and Burrito os/cpu pairs
    * `Tinfoil.Burrito` — the bridge between tinfoil's abstract targets
      and the user's `releases/0` block

  For the full narrative with installation steps, configuration
  examples, and the Burrito target-name resolution story, see the
  [README](readme.html).
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
