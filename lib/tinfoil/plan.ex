defmodule Tinfoil.Plan do
  @moduledoc """
  Build a structured plan describing what tinfoil would build and
  release from the current config.

  The plan is the shared data structure between `mix tinfoil.plan`
  (human output), the GitHub Actions build matrix (JSON output), and
  future `mix tinfoil.build` / `mix tinfoil.publish` tasks.

  This module is deliberately pure — no filesystem, no network, no
  shelling out — so it is trivial to test and safe to call from any
  context. The companion `mix tinfoil.plan` task layers in side
  effects on top: pretty-printing for humans, and NIF cross-compile
  warnings via `Tinfoil.NifCheck`.
  """

  alias Tinfoil.{Config, Target}

  @type target_plan :: %{
          target: Target.target(),
          burrito_name: atom(),
          runner: String.t(),
          triple: String.t(),
          burrito_os: atom(),
          burrito_cpu: atom(),
          os_family: atom(),
          archive: String.t()
        }

  @type build_entry :: %{
          id: String.t(),
          targets: String.t(),
          runner: String.t()
        }

  @type t :: %{
          app: atom(),
          version: String.t(),
          archive_format: atom(),
          checksums: atom(),
          targets: [target_plan()],
          single_runner_per_os: boolean(),
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
      single_runner_per_os: config.single_runner_per_os,
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

  @doc """
  Return the list of build job matrix entries.

  In the default (`single_runner_per_os: false`) mode every tinfoil
  target is its own entry, so the CI matrix is one job per target.

  When `:single_runner_per_os` is true, targets that share both a
  runner and an OS family are collapsed into a single entry. The
  `:targets` field is a comma-separated list of tinfoil target names
  that the generated workflow loops over with a shell `for`.
  """
  @spec build_entries(t()) :: [build_entry()]
  def build_entries(%{single_runner_per_os: true, targets: targets}),
    do: grouped_entries(targets)

  def build_entries(%{targets: targets}),
    do: Enum.map(targets, &flat_entry/1)

  ## ───────────────────── internals ─────────────────────

  defp target_plan(target, config) do
    spec = Target.spec!(target, config.extra_targets)

    %{
      target: target,
      burrito_name: Map.fetch!(config.burrito_names, target),
      runner: spec.runner,
      triple: spec.triple,
      burrito_os: spec.burrito_os,
      burrito_cpu: spec.burrito_cpu,
      os_family: spec.os_family,
      archive: Config.archive_filename(config, target)
    }
  end

  defp flat_entry(%{target: target, runner: runner}) do
    %{id: to_string(target), targets: to_string(target), runner: runner}
  end

  # Collapse every target in an os_family onto one matrix entry. The runner
  # is taken from the first target in that family (by user-declared order),
  # which sidesteps having to hardcode an opinion about which runner should
  # own the family — a user who configures :darwin_arm64 first gets
  # macos-latest for the whole family, and the cross-compile handles x86.
  defp grouped_entries(targets) do
    targets
    |> Enum.group_by(& &1.os_family)
    |> Enum.map(fn {os_family, entries} ->
      names = Enum.map(entries, &to_string(&1.target))
      [%{runner: runner} | _] = entries

      %{id: to_string(os_family), targets: Enum.join(names, ","), runner: runner}
    end)
    |> Enum.sort_by(& &1.id)
  end
end
