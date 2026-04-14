defmodule Tinfoil.Archive do
  @moduledoc """
  Create release archives from built binaries.

  Archive creation is bytes-in, bytes-out: given a binary path and an
  archive basename, produce either a gzipped tarball (`tar_gz/4`,
  used for the unix targets) or a zip file (`zip/4`, used for
  Windows targets where users expect `.zip`/`.exe`), plus a `.sha256`
  sidecar in `shasum -a 256` format. The choice of format is driven
  by the target spec's `archive_ext` and dispatched in `Tinfoil.Build`.

  Uses Erlang's built-in `:erl_tar`, `:zip`, and `:crypto` — no
  shelling out, no extra dependencies.
  """

  @doc """
  Create `<output_dir>/<archive_basename>.tar.gz` containing the file
  at `binary_path`, renamed to `to_string(app)` inside the archive.

  The archive entry is written with mode `0755` so the extracted
  binary is executable without the user needing a manual `chmod +x`.
  This matters for anyone who downloads the tarball directly — the
  installer script does its own chmod, but a plain `tar -xzf` extract
  should produce something runnable.

  Returns the path to the written archive.
  """
  @spec tar_gz(Path.t(), atom(), String.t(), Path.t(), [{Path.t(), Path.t()}]) :: Path.t()
  def tar_gz(binary_path, app, archive_basename, output_dir, extras \\ []) do
    File.mkdir_p!(output_dir)
    archive_path = Path.join(output_dir, archive_basename <> ".tar.gz")
    name_in_archive = to_string(app)

    # Stage the binary in a temp file with the executable bit set, then
    # use :erl_tar's filesystem form. :erl_tar.add reads mode/atime/mtime
    # from stat(2), so the archive entry inherits the staged file's 0755.
    # The {name, binary} form of :erl_tar.create uses a hardcoded 0644
    # and produces a non-executable entry — see tinfoil#<issue>.
    stage = Path.join(output_dir, ".tinfoil_stage_" <> name_in_archive)

    try do
      File.cp!(binary_path, stage)
      File.chmod!(stage, 0o755)

      {:ok, tar} = :erl_tar.open(String.to_charlist(archive_path), [:write, :compressed])

      :ok =
        :erl_tar.add(
          tar,
          String.to_charlist(stage),
          String.to_charlist(name_in_archive),
          []
        )

      Enum.each(extras, fn {src, dst} ->
        verify_extra_exists!(src)

        :ok =
          :erl_tar.add(
            tar,
            String.to_charlist(src),
            String.to_charlist(dst),
            []
          )
      end)

      :ok = :erl_tar.close(tar)
    after
      File.rm(stage)
    end

    archive_path
  end

  @doc """
  Create `<output_dir>/<archive_basename>.zip` containing the file at
  `binary_path`, renamed to `name_in_archive` inside the archive.

  Used for Windows targets, where users expect `.zip` and the wrapped
  binary already carries a `.exe` suffix (so `name_in_archive` should
  include it). The zip format does not carry unix mode bits, so no
  `chmod` dance is needed.

  Returns the path to the written archive.
  """
  @spec zip(Path.t(), String.t(), String.t(), Path.t(), [{Path.t(), Path.t()}]) :: Path.t()
  def zip(binary_path, name_in_archive, archive_basename, output_dir, extras \\ []) do
    File.mkdir_p!(output_dir)
    archive_path = Path.join(output_dir, archive_basename <> ".zip")

    extra_entries =
      Enum.map(extras, fn {src, dst} ->
        verify_extra_exists!(src)
        {String.to_charlist(dst), File.read!(src)}
      end)

    entries =
      [{String.to_charlist(name_in_archive), File.read!(binary_path)} | extra_entries]

    {:ok, _} = :zip.create(String.to_charlist(archive_path), entries)

    archive_path
  end

  defp verify_extra_exists!(path) do
    unless File.regular?(path) do
      raise "extra_artifacts entry not found on disk: #{inspect(path)}"
    end
  end

  @doc """
  Compute the SHA256 of the file at `path`, write a `<path>.sha256`
  sidecar in `shasum -a 256` format (`<hex>  <filename>\\n`), and
  return `{hex_digest, sidecar_path}`.
  """
  @spec sha256(Path.t()) :: {String.t(), Path.t()}
  def sha256(path) do
    digest =
      :sha256
      |> :crypto.hash(File.read!(path))
      |> Base.encode16(case: :lower)

    sidecar = path <> ".sha256"
    File.write!(sidecar, "#{digest}  #{Path.basename(path)}\n")
    {digest, sidecar}
  end

  @doc """
  Combine per-archive `.sha256` sidecars under `input_dir` into a
  single `checksums-sha256.txt` file at `Path.join(input_dir, name)`.

  Returns the path to the combined file.
  """
  @spec combined_checksums(Path.t(), String.t()) :: Path.t()
  def combined_checksums(input_dir, name \\ "checksums-sha256.txt") do
    combined_path = Path.join(input_dir, name)

    contents =
      input_dir
      |> Path.join("*.sha256")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map_join(&File.read!/1)

    File.write!(combined_path, contents)
    combined_path
  end
end
