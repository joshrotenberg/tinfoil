defmodule Tinfoil.Homebrew.Git do
  @moduledoc """
  Thin wrapper around the subset of `git` commands `Tinfoil.Homebrew`
  needs. Kept behind a behaviour so tests can swap in a stub module
  without touching the real filesystem or network.
  """

  @callback clone(url :: String.t(), dir :: Path.t()) :: :ok | {:error, term()}
  @callback config_identity(dir :: Path.t(), name :: String.t(), email :: String.t()) :: :ok
  @callback add(dir :: Path.t(), relative_path :: String.t()) :: :ok
  @callback staged_changes?(dir :: Path.t()) :: boolean()
  @callback commit(dir :: Path.t(), message :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
  @callback push(dir :: Path.t()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def clone(url, dir) do
    case run(["clone", "--depth", "1", url, dir], nil) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  @impl true
  def config_identity(dir, name, email) do
    {:ok, _} = run(["config", "user.name", name], dir)
    {:ok, _} = run(["config", "user.email", email], dir)
    :ok
  end

  @impl true
  def add(dir, relative_path) do
    {:ok, _} = run(["add", relative_path], dir)
    :ok
  end

  @impl true
  def staged_changes?(dir) do
    # `git diff --cached --quiet` exits 0 when there are no staged changes
    # and 1 when there are.
    case System.cmd("git", ["diff", "--cached", "--quiet"], cd: dir) do
      {_, 0} -> false
      {_, 1} -> true
      {out, n} -> raise "git diff --cached failed (#{n}): #{out}"
    end
  end

  @impl true
  def commit(dir, message) do
    with {:ok, _} <- run(["commit", "-m", message], dir),
         {:ok, sha} <- run(["rev-parse", "HEAD"], dir) do
      {:ok, String.trim(sha)}
    end
  end

  @impl true
  def push(dir) do
    case run(["push", "origin", "HEAD"], dir) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp run(args, cwd) do
    opts = [stderr_to_stdout: true]
    opts = if cwd, do: Keyword.put(opts, :cd, cwd), else: opts

    case System.cmd("git", args, opts) do
      {out, 0} -> {:ok, out}
      {out, n} -> {:error, {:git_failed, args, n, String.trim(out)}}
    end
  end
end
