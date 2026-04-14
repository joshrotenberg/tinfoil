defmodule Tinfoil.ProjectEditor do
  @moduledoc """
  Splice tinfoil's dep and config into a `mix.exs` that was produced
  by `mix new`. The edits are intentionally string-based (not AST
  rewrites) so user formatting, comments, and layout are preserved.

  Anchors used:

    * `insert_dep/2` looks for `defp deps do\n    [` and injects the
      tinfoil entry as the first list element.
    * `insert_tinfoil_config/2` looks for `deps: deps()` inside
      `project/0` and appends a `tinfoil: [ ... ]` entry after it.

  Both functions are idempotent: if tinfoil is already present, the
  source is returned unchanged with an `:already_present` status.

  If the expected anchors don't match -- typically because the user
  customized the file beyond the `mix new` shape -- the caller gets
  `{:error, reason}` and should print a snippet for manual paste
  rather than guessing.
  """

  @type status :: :inserted | :already_present

  @doc """
  Insert `{:tinfoil, "~> <version>", runtime: false}` as the first
  element of `deps/0`.
  """
  @spec insert_dep(String.t(), String.t()) ::
          {:ok, String.t(), status()} | {:error, :deps_anchor_not_found}
  def insert_dep(source, tinfoil_version) do
    if already_has_tinfoil_dep?(source) do
      {:ok, source, :already_present}
    else
      # Capture the leading indentation of `[` so our injected entry lines up.
      regex = ~r/(defp\s+deps\s+do\s*\n)([ \t]*)\[/

      if Regex.match?(regex, source) do
        entry = ~s({:tinfoil, "~> #{tinfoil_version}", runtime: false})
        replacement = "\\1\\2[\n\\2  #{entry},"

        {:ok, Regex.replace(regex, source, replacement, global: false), :inserted}
      else
        {:error, :deps_anchor_not_found}
      end
    end
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

  ## ───────────────────── internals ─────────────────────

  defp replace_deps_line(_full, indent, newline, targets) do
    indent <> "deps: deps()," <> newline <> render_config_block(targets, indent)
  end

  defp already_has_tinfoil_dep?(source) do
    Regex.match?(~r/\{\s*:tinfoil\s*,/, source)
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
end
