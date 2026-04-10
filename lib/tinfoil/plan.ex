defmodule Tinfoil.Plan do
  @moduledoc """
  Build a structured plan describing what tinfoil would build and
  release from the current config.

  The plan is the shared data structure between `mix tinfoil.plan`
  (human output), the GitHub Actions build matrix (JSON output), and
  future `mix tinfoil.build` / `mix tinfoil.publish` tasks.

  This module is deliberately pure — no filesystem, no network, no
  shelling out — so it is trivial to test and safe to call from any
  context.
  """

  alias Tinfoil.{Config, Target}

  @type target_plan :: %{
          target: Target.target(),
          runner: String.t(),
          triple: String.t(),
          burrito_os: atom(),
          burrito_cpu: atom(),
          os_family: atom(),
          archive: String.t()
        }

  @type t :: %{
          app: atom(),
          version: String.t(),
          archive_format: atom(),
          checksums: atom(),
          targets: [target_plan()],
          github: map(),
          homebrew: map(),
          installer: map()
        }

  @doc """
  Build a plan map from a resolved `%Tinfoil.Config{}`.

  The `:targets` list preserves the order the user configured.
  """
  @spec build(Config.t()) :: t()
  def build(%Config{} = config) do
    %{
      app: config.app,
      version: config.version,
      archive_format: config.archive_format,
      checksums: config.checksums,
      targets: Enum.map(config.targets, &target_plan(&1, config)),
      github: config.github,
      homebrew: config.homebrew,
      installer: config.installer
    }
  end

  @doc """
  Return the GitHub Actions matrix fragment — an object with an
  `include` array, one entry per target.

  Suitable for feeding into `strategy.matrix` via `fromJson()`:

      - id: plan
        run: echo "matrix=$(mix tinfoil.plan --format matrix)" >> $GITHUB_OUTPUT

      build:
        needs: plan
        strategy:
          matrix: ${{ fromJson(needs.plan.outputs.matrix) }}
  """
  @spec matrix(t()) :: %{include: [target_plan()]}
  def matrix(%{targets: targets}), do: %{include: targets}

  ## ───────────────────── internals ─────────────────────

  defp target_plan(target, config) do
    spec = Target.spec!(target)

    %{
      target: target,
      runner: spec.runner,
      triple: spec.triple,
      burrito_os: spec.burrito_os,
      burrito_cpu: spec.burrito_cpu,
      os_family: spec.os_family,
      archive: Config.archive_filename(config, target)
    }
  end
end
