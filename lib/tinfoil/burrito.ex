defmodule Tinfoil.Burrito do
  @moduledoc """
  Integration with the user's Burrito configuration in `mix.exs`.

  Burrito target names are user-chosen keys in the `:releases` block:

      releases: [
        my_cli: [
          steps: [:assemble, &Burrito.wrap/1],
          burrito: [
            targets: [
              macos:    [os: :darwin, cpu: :x86_64],
              macos_m1: [os: :darwin, cpu: :aarch64],
              linux:    [os: :linux,  cpu: :x86_64]
            ]
          ]
        ]
      ]

  Tinfoil's own target atoms (`:darwin_arm64`, `:linux_x86_64`, ...) are
  abstract. To drive Burrito from CI, tinfoil needs to know what *the
  user* called the target with matching `[os:, cpu:]`. This module reads
  the releases block from a mix project keyword list and resolves each
  tinfoil target atom to the user's Burrito target name.
  """

  alias Tinfoil.Target

  @type burrito_targets :: %{atom() => [os: atom(), cpu: atom()]}

  @doc """
  Extract the Burrito targets map from a mix project keyword list.

  Picks the release whose name matches `app`. If no release matches by
  name, falls back to the single release in the block (if exactly one
  exists). Any other case is an error.
  """
  @spec extract_targets(keyword(), atom()) ::
          {:ok, burrito_targets()} | {:error, term()}
  def extract_targets(project, app) when is_list(project) and is_atom(app) do
    with {:ok, releases} <- fetch_releases(project),
         {:ok, release_opts} <- pick_release(releases, app),
         {:ok, burrito} <- fetch_burrito(release_opts),
         {:ok, targets} <- fetch_burrito_targets(burrito) do
      normalize(targets)
    end
  end

  @doc """
  Resolve a single tinfoil target atom to the user's Burrito target
  name by matching `[os:, cpu:]` against the user's Burrito config.
  """
  @spec resolve(Target.target(), burrito_targets(), Target.extras()) ::
          {:ok, atom()}
          | {:error, {:no_matching_burrito_target, Target.target(), Target.spec()}}
  def resolve(tinfoil_target, burrito_targets, extras \\ %{}) do
    spec = Target.spec!(tinfoil_target, extras)

    match =
      Enum.find(burrito_targets, fn {_name, opts} ->
        opts[:os] == spec.burrito_os and opts[:cpu] == spec.burrito_cpu
      end)

    case match do
      {name, _} -> {:ok, name}
      nil -> {:error, {:no_matching_burrito_target, tinfoil_target, spec}}
    end
  end

  @doc """
  Resolve every tinfoil target atom against the user's Burrito targets.

  Returns `{:ok, %{tinfoil_target => burrito_name}}` or halts on the
  first unmatched target and returns the error.
  """
  @spec resolve_all([Target.target()], burrito_targets(), Target.extras()) ::
          {:ok, %{Target.target() => atom()}} | {:error, term()}
  def resolve_all(tinfoil_targets, burrito_targets, extras \\ %{}) do
    Enum.reduce_while(tinfoil_targets, {:ok, %{}}, fn t, {:ok, acc} ->
      case resolve(t, burrito_targets, extras) do
        {:ok, name} -> {:cont, {:ok, Map.put(acc, t, name)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  ## ───────────────────── internals ─────────────────────

  defp fetch_releases(project) do
    case Keyword.fetch(project, :releases) do
      {:ok, releases} when is_list(releases) and releases != [] ->
        {:ok, releases}

      {:ok, _} ->
        {:error, :releases_empty_or_invalid}

      :error ->
        {:error, :missing_releases}
    end
  end

  defp pick_release(releases, app) do
    cond do
      Keyword.has_key?(releases, app) ->
        {:ok, Keyword.fetch!(releases, app)}

      length(releases) == 1 ->
        [{_name, opts}] = releases
        {:ok, opts}

      true ->
        {:error, {:multiple_releases_no_match, Keyword.keys(releases), app}}
    end
  end

  defp fetch_burrito(release_opts) when is_list(release_opts) do
    case Keyword.fetch(release_opts, :burrito) do
      {:ok, burrito} when is_list(burrito) -> {:ok, burrito}
      {:ok, _} -> {:error, :burrito_not_keyword_list}
      :error -> {:error, :missing_burrito_in_release}
    end
  end

  defp fetch_burrito(_), do: {:error, :release_opts_not_keyword_list}

  defp fetch_burrito_targets(burrito) do
    case Keyword.fetch(burrito, :targets) do
      {:ok, targets} when is_list(targets) and targets != [] -> {:ok, targets}
      {:ok, _} -> {:error, :burrito_targets_empty_or_invalid}
      :error -> {:error, :missing_burrito_targets}
    end
  end

  defp normalize(targets) do
    Enum.reduce_while(targets, {:ok, %{}}, fn
      {name, opts}, {:ok, acc} when is_atom(name) and is_list(opts) ->
        os = Keyword.get(opts, :os)
        cpu = Keyword.get(opts, :cpu)

        if is_atom(os) and not is_nil(os) and is_atom(cpu) and not is_nil(cpu) do
          {:cont, {:ok, Map.put(acc, name, os: os, cpu: cpu)}}
        else
          {:halt, {:error, {:invalid_burrito_target, name}}}
        end

      _other, _acc ->
        {:halt, {:error, :burrito_targets_malformed}}
    end)
  end
end
