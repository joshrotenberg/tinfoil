defmodule Tinfoil.NifCheck do
  @moduledoc """
  Heuristic detection of dependencies that may not cross-compile
  cleanly under Burrito's Zig toolchain.

  Burrito handles pure-Erlang/Elixir deps without ceremony, but deps
  that carry NIFs -- Rustler crates, `elixir_make` C extensions, raw
  `c_src/` sources -- often need per-target native tooling that Zig
  can't always synthesize. This module surfaces those deps at plan
  time so a broken release doesn't silently ship.

  It reads files from disk but never shells out or runs a build; the
  heuristics look at each dep's top-level `mix.exs`, `Makefile`, and
  well-known source directories. The detection is a warning, not a
  gate -- Burrito + Zig often does cross-compile these cleanly, and
  `rustler_precompiled` deps ship prebuilts that sidestep the issue
  entirely when coverage matches your targets.
  """

  @type reason ::
          :rustler
          | :rustler_precompiled
          | :elixir_make
          | :c_sources

  @type warning :: %{
          name: atom(),
          path: Path.t(),
          reasons: [reason()]
        }

  @doc """
  Inspect a list of `{name, path}` dep tuples and return a list of
  warnings, one entry per dep that matched at least one NIF signal.

  Order of reasons within a warning is stable (see `@reason_order/0`).
  Order of warnings follows the input order.
  """
  @spec check([{atom(), Path.t()}]) :: [warning()]
  def check(deps) do
    deps
    |> Enum.map(fn {name, path} -> {name, path, inspect_dep(path)} end)
    |> Enum.filter(fn {_name, _path, reasons} -> reasons != [] end)
    |> Enum.map(fn {name, path, reasons} ->
      %{name: name, path: path, reasons: reasons}
    end)
  end

  @doc """
  Resolve the dep set to scan: the deps that will actually be present
  in the release build.

  `mix tinfoil.plan` normally runs under `MIX_ENV=dev`, but the
  generated workflow builds under `MIX_ENV=prod`. Scanning the dev set
  reports NIFs in deps that can never reach the artifact -- `credo`
  pulls in `file_system`, which carries a `c_src/` directory but is
  `only: [:dev, :test]` and so is absent from the release.

  Two filters are applied:

    * environment -- deps are resolved as `env` sees them, so `only:`
      restrictions that exclude a dep from the build drop it here too
    * `runtime: false` -- top-level deps marked compile-time-only are
      excluded from the release's `:applications`, so a NIF in one
      cannot affect the built binary

  Returns `{name, path}` tuples suitable for `check/1`. The list is
  empty when `mix deps.get` hasn't been run, in which case callers
  should stay silent rather than emit spurious warnings.
  """
  @spec release_deps(atom()) :: [{atom(), Path.t()}]
  def release_deps(env \\ :prod) do
    excluded = compile_time_only(Keyword.get(Mix.Project.config(), :deps, []))

    env
    |> deps_paths_in_env()
    |> Enum.reject(fn {name, _path} -> MapSet.member?(excluded, name) end)
    |> Enum.sort()
  end

  @doc false
  # Top-level deps declared `runtime: false` are compiled but left out
  # of the project's `:applications`, so `mix release` never packages
  # them. Tinfoil itself is declared this way in every user project.
  @spec compile_time_only([tuple()]) :: MapSet.t(atom())
  def compile_time_only(deps) do
    deps
    |> Enum.filter(fn dep -> Keyword.get(dep_opts(dep), :runtime, true) == false end)
    |> MapSet.new(&elem(&1, 0))
  end

  @doc """
  Human-readable sentence for a reason atom.
  """
  @spec describe(reason()) :: String.t()
  def describe(:rustler),
    do: "uses Rustler (Rust NIF); cross-compile via Zig is often fine but not guaranteed"

  def describe(:rustler_precompiled),
    do: "uses rustler_precompiled; verify prebuilts cover your targets"

  def describe(:elixir_make),
    do: "uses elixir_make; C extensions can be fragile to cross-compile"

  def describe(:c_sources),
    do: "has c_src/ directory; C extensions may not cross-compile cleanly"

  ## ───────────────────── internals ─────────────────────

  # `Mix.Project.deps_paths/0` is environment-sensitive: it returns the
  # deps the *current* `Mix.env()` resolves to. To see the build's view
  # from a `plan` running in dev we flip the env, drop Mix's dep cache
  # so the next load re-resolves, and restore both afterwards.
  #
  # `Mix.Dep.clear_cached/0` is undocumented but has been present and
  # stable since well before 1.15. Its 1.15-era sibling
  # `Mix.Dep.load_on_environment/1` -- the obvious API for this -- was
  # removed in 1.16, so it isn't usable across the supported range.
  defp deps_paths_in_env(env) do
    if Mix.env() == env do
      Map.to_list(Mix.Project.deps_paths())
    else
      previous = Mix.env()

      try do
        Mix.env(env)
        Mix.Dep.clear_cached()
        Map.to_list(Mix.Project.deps_paths())
      after
        Mix.env(previous)
        Mix.Dep.clear_cached()
      end
    end
  end

  defp dep_opts({_name, opts}) when is_list(opts), do: opts
  defp dep_opts({_name, _req, opts}) when is_list(opts), do: opts
  defp dep_opts(_), do: []

  # Order reasons deterministically regardless of detection order.
  @reason_order [:rustler, :rustler_precompiled, :elixir_make, :c_sources]

  defp inspect_dep(path) do
    mix_exs = read_file(Path.join(path, "mix.exs"))

    [
      rustler_reason(mix_exs),
      elixir_make_reason(mix_exs, path),
      c_sources_reason(path)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> sort_reasons()
  end

  defp rustler_reason(nil), do: nil

  defp rustler_reason(mix_exs) do
    cond do
      Regex.match?(~r/\brustler_precompiled\b/, mix_exs) -> :rustler_precompiled
      Regex.match?(~r/\brustler\b/, mix_exs) -> :rustler
      true -> nil
    end
  end

  defp elixir_make_reason(nil, _path), do: nil

  defp elixir_make_reason(mix_exs, path) do
    if Regex.match?(~r/\belixir_make\b/, mix_exs) or
         (File.regular?(Path.join(path, "Makefile")) and
            Regex.match?(~r/compilers:\s*\[[^\]]*:make\b/, mix_exs)) do
      :elixir_make
    end
  end

  defp c_sources_reason(path) do
    if File.dir?(Path.join(path, "c_src")) do
      :c_sources
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, _} -> nil
    end
  end

  defp sort_reasons(reasons) do
    Enum.sort_by(reasons, fn r -> Enum.find_index(@reason_order, &(&1 == r)) end)
  end
end
