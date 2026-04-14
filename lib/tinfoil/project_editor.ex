defmodule Tinfoil.ProjectEditor do
  @moduledoc """
  Splice tinfoil + Burrito wiring into a `mix.exs` that was produced
  by `mix new`. The edits are intentionally string-based (not AST
  rewrites) so user formatting, comments, and layout are preserved.

  The module exports one splicer per concern:

    * `insert_tinfoil_dep/2`       — `{:tinfoil, "~> X", runtime: false}`
    * `insert_burrito_dep/1`       — `{:burrito, "~> 1.0"}`
    * `insert_tinfoil_config/2`    — `tinfoil: [ targets: [...] ]` in `project/0`
    * `insert_releases_entry/1`    — `releases: releases()` in `project/0`
    * `insert_releases_block/2`    — `defp releases do ... end` function
    * `insert_application_mod/2`   — `mod: {App.Application, []}` in `application/0`

  Every splicer is idempotent: if the target is already present, the
  source is returned unchanged with an `:already_present` status.

  If a splicer can't find its anchor -- typically because the user
  customized the file beyond the `mix new` shape -- the caller gets
  `{:error, reason}` and should print a snippet for manual paste
  rather than guessing.
  """

  @type status :: :inserted | :already_present

  @burrito_requirement "~> 1.0"

  @doc """
  Insert `{:tinfoil, "~> <version>", runtime: false}` as the first
  element of `deps/0`.
  """
  @spec insert_tinfoil_dep(String.t(), String.t()) ::
          {:ok, String.t(), status()} | {:error, :deps_anchor_not_found}
  def insert_tinfoil_dep(source, tinfoil_version) do
    insert_dep_if_missing(
      source,
      ~r/\{\s*:tinfoil\s*,/,
      ~s({:tinfoil, "~> #{tinfoil_version}", runtime: false})
    )
  end

  @doc """
  Back-compat alias for `insert_tinfoil_dep/2`. Kept because earlier
  callers used the shorter name.
  """
  @spec insert_dep(String.t(), String.t()) ::
          {:ok, String.t(), status()} | {:error, :deps_anchor_not_found}
  def insert_dep(source, tinfoil_version), do: insert_tinfoil_dep(source, tinfoil_version)

  @doc """
  Insert `{:burrito, "~> 1.0"}` into `deps/0`.
  """
  @spec insert_burrito_dep(String.t()) ::
          {:ok, String.t(), status()} | {:error, :deps_anchor_not_found}
  def insert_burrito_dep(source) do
    insert_dep_if_missing(
      source,
      ~r/\{\s*:burrito\s*,/,
      ~s({:burrito, "#{@burrito_requirement}"})
    )
  end

  @doc """
  Insert a minimal `:tinfoil` config block into `project/0`, right
  after the `deps: deps()` line.
  """
  @spec insert_tinfoil_config(String.t(), [atom()]) ::
          {:ok, String.t(), status()} | {:error, :project_anchor_not_found}
  def insert_tinfoil_config(source, targets) when is_list(targets) and targets != [] do
    if already_has_tinfoil_config?(source) do
      {:ok, source, :already_present}
    else
      regex = ~r/([ \t]*)deps:\s*deps\(\),?(\n)/

      if Regex.match?(regex, source) do
        replacer = &replace_deps_line(&1, &2, &3, targets)
        {:ok, Regex.replace(regex, source, replacer), :inserted}
      else
        {:error, :project_anchor_not_found}
      end
    end
  end

  @doc """
  Insert `releases: releases()` into `project/0` right after the
  `deps: deps()` line.
  """
  @spec insert_releases_entry(String.t()) ::
          {:ok, String.t(), status()} | {:error, :project_anchor_not_found}
  def insert_releases_entry(source) do
    if Regex.match?(~r/\breleases:\s*releases\(\)/, source) do
      {:ok, source, :already_present}
    else
      regex = ~r/([ \t]*)deps:\s*deps\(\),?(\n)/

      if Regex.match?(regex, source) do
        {:ok, Regex.replace(regex, source, &add_releases_line/3), :inserted}
      else
        {:error, :project_anchor_not_found}
      end
    end
  end

  defp add_releases_line(_full, indent, newline) do
    indent <> "deps: deps()," <> newline <> indent <> "releases: releases()," <> newline
  end

  @doc """
  Append a `defp releases do ... end` function with a Burrito
  `:targets` block for the given tinfoil targets. The function is
  inserted at the bottom of the module, right before the final `end`.
  The release name matches the app atom so `Tinfoil.Burrito.pick_release/2`
  picks it by name.
  """
  @spec insert_releases_block(String.t(), atom(), [atom()]) ::
          {:ok, String.t(), status()} | {:error, :module_end_not_found}
  def insert_releases_block(source, app, targets)
      when is_atom(app) and is_list(targets) and targets != [] do
    # "defp releases" at any indent signals the block is already there.
    if Regex.match?(~r/^\s*defp\s+releases\s+do/m, source) do
      {:ok, source, :already_present}
    else
      # The module-level `end` is on its own line at column 0 at end-of-file,
      # optionally followed by a trailing newline.
      regex = ~r/\nend\s*\z/

      if Regex.match?(regex, source) do
        block = render_releases_block(app, targets)
        {:ok, Regex.replace(regex, source, "\n" <> block <> "\nend\n", global: false), :inserted}
      else
        {:error, :module_end_not_found}
      end
    end
  end

  @doc """
  Add `mod: {<app_module>.Application, []}` to the `application/0`
  keyword list, right after the `extra_applications: [...]` line.
  """
  @spec insert_application_mod(String.t(), String.t()) ::
          {:ok, String.t(), status()} | {:error, :application_anchor_not_found}
  def insert_application_mod(source, app_module) when is_binary(app_module) do
    if Regex.match?(~r/\bmod:\s*\{/, source) do
      {:ok, source, :already_present}
    else
      regex = ~r/([ \t]*)extra_applications:\s*\[[^\]]*\](,?)(\n)/

      if Regex.match?(regex, source) do
        updated =
          Regex.replace(regex, source, fn _full, indent, _comma, newline ->
            [
              indent,
              "extra_applications: [:logger],",
              newline,
              indent,
              "mod: {",
              app_module,
              ".Application, []}",
              newline
            ]
            |> IO.iodata_to_binary()
          end)

        {:ok, updated, :inserted}
      else
        {:error, :application_anchor_not_found}
      end
    end
  end

  ## ───────────────────── internals ─────────────────────

  # Inject a single `{:name, ...}` entry as the first element of deps/0
  # unless a matching entry is already present. Indentation of the
  # existing `[` is preserved on the injected line.
  defp insert_dep_if_missing(source, existing_regex, entry) do
    if Regex.match?(existing_regex, source) do
      {:ok, source, :already_present}
    else
      deps_regex = ~r/(defp\s+deps\s+do\s*\n)([ \t]*)\[/

      if Regex.match?(deps_regex, source) do
        replacement = "\\1\\2[\n\\2  #{entry},"
        {:ok, Regex.replace(deps_regex, source, replacement, global: false), :inserted}
      else
        {:error, :deps_anchor_not_found}
      end
    end
  end

  defp replace_deps_line(_full, indent, newline, targets) do
    indent <> "deps: deps()," <> newline <> render_config_block(targets, indent)
  end

  defp already_has_tinfoil_config?(source) do
    Regex.match?(~r/\btinfoil:\s*\[/, source)
  end

  defp render_config_block(targets, indent) do
    """
    #{indent}tinfoil: [
    #{indent}  targets: #{inspect(targets, limit: :infinity)}
    #{indent}]
    """
  end

  # Two-space indent matches what `mix new` uses for function bodies.
  defp render_releases_block(app, targets) do
    entries =
      Enum.map_join(targets, ",\n", fn t ->
        spec = Tinfoil.Target.spec!(t)
        "          #{t}: [os: :#{spec.burrito_os}, cpu: :#{spec.burrito_cpu}]"
      end)

    """
      defp releases do
        [
          #{app}: [
            steps: [:assemble, &Burrito.wrap/1],
            burrito: [
              targets: [
    #{entries}
              ]
            ]
          ]
        ]
      end\
    """
  end
end
