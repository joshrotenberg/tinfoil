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
