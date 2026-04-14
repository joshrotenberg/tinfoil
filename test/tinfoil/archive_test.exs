defmodule Tinfoil.ArchiveTest do
  use ExUnit.Case, async: true

  alias Tinfoil.Archive

  describe "tar_gz/4" do
    @tag :tmp_dir
    test "creates a gzipped tar with the binary renamed to the app name", %{tmp_dir: tmp} do
      binary_path = Path.join(tmp, "woof_macos_m1")
      File.write!(binary_path, "fake-burrito-binary-bytes")

      output_dir = Path.join(tmp, "out")

      archive =
        Archive.tar_gz(binary_path, :woof, "woof-0.1.0-aarch64-apple-darwin", output_dir)

      assert archive == Path.join(output_dir, "woof-0.1.0-aarch64-apple-darwin.tar.gz")
      assert File.exists?(archive)

      # Extract and verify the binary is in there under the app name
      extract_dir = Path.join(tmp, "extracted")
      File.mkdir_p!(extract_dir)

      :ok =
        :erl_tar.extract(String.to_charlist(archive), [
          :compressed,
          {:cwd, String.to_charlist(extract_dir)}
        ])

      extracted = Path.join(extract_dir, "woof")
      assert File.exists?(extracted)
      assert File.read!(extracted) == "fake-burrito-binary-bytes"
    end

    @tag :tmp_dir
    test "extracted binary preserves executable mode (0755)", %{tmp_dir: tmp} do
      # Source binary intentionally non-executable to prove tar_gz forces
      # the mode up — Burrito's real output is 0755, but tinfoil shouldn't
      # trust that and should emit an executable archive entry regardless.
      binary_path = Path.join(tmp, "woof_linux")
      File.write!(binary_path, "not-executable-at-source")
      File.chmod!(binary_path, 0o644)

      output_dir = Path.join(tmp, "out")

      Archive.tar_gz(binary_path, :woof, "woof-0.1.0-x86_64-unknown-linux-musl", output_dir)

      archive = Path.join(output_dir, "woof-0.1.0-x86_64-unknown-linux-musl.tar.gz")
      extract_dir = Path.join(tmp, "extracted")
      File.mkdir_p!(extract_dir)

      :ok =
        :erl_tar.extract(String.to_charlist(archive), [
          :compressed,
          {:cwd, String.to_charlist(extract_dir)}
        ])

      extracted = Path.join(extract_dir, "woof")
      %File.Stat{mode: mode} = File.stat!(extracted)

      # mode is stored as decimal; mask out file-type bits and assert the
      # "executable by owner" bit is set
      assert Bitwise.band(mode, 0o100) != 0,
             "expected extracted binary to be owner-executable, got mode #{Integer.to_string(mode, 8)}"
    end

    @tag :tmp_dir
    test "leaves no stage file behind on success", %{tmp_dir: tmp} do
      binary_path = Path.join(tmp, "app_target")
      File.write!(binary_path, "bytes")

      output_dir = Path.join(tmp, "out")
      Archive.tar_gz(binary_path, :app, "app-1.0.0-linux", output_dir)

      stage_files =
        output_dir
        |> Path.join(".tinfoil_stage_*")
        |> Path.wildcard()

      assert stage_files == []
    end
  end

  describe "tar_gz with :extras" do
    @tag :tmp_dir
    test "bundles extra files alongside the binary at their dest paths", %{tmp_dir: tmp} do
      binary_path = Path.join(tmp, "woof_macos_m1")
      File.write!(binary_path, "bytes")

      File.write!(Path.join(tmp, "LICENSE"), "MIT License")
      File.mkdir_p!(Path.join(tmp, "man"))
      File.write!(Path.join(tmp, "man/woof.1"), "man page contents")

      extras = [
        {Path.join(tmp, "LICENSE"), "LICENSE"},
        {Path.join(tmp, "man/woof.1"), "share/man/man1/woof.1"}
      ]

      output_dir = Path.join(tmp, "out")

      archive =
        Archive.tar_gz(binary_path, :woof, "woof-0.1.0-linux", output_dir, extras)

      extract_dir = Path.join(tmp, "ex")
      File.mkdir_p!(extract_dir)

      :ok =
        :erl_tar.extract(String.to_charlist(archive), [
          :compressed,
          {:cwd, String.to_charlist(extract_dir)}
        ])

      assert File.read!(Path.join(extract_dir, "woof")) == "bytes"
      assert File.read!(Path.join(extract_dir, "LICENSE")) == "MIT License"
      assert File.read!(Path.join(extract_dir, "share/man/man1/woof.1")) == "man page contents"
    end

    @tag :tmp_dir
    test "raises when an extra path doesn't exist", %{tmp_dir: tmp} do
      binary_path = Path.join(tmp, "woof")
      File.write!(binary_path, "bytes")

      extras = [{Path.join(tmp, "missing"), "LICENSE"}]

      assert_raise RuntimeError, ~r/extra_artifacts entry not found/, fn ->
        Archive.tar_gz(binary_path, :woof, "woof-0.1.0", Path.join(tmp, "out"), extras)
      end
    end
  end

  describe "zip/4" do
    @tag :tmp_dir
    test "creates a zip with the binary renamed to name_in_archive", %{tmp_dir: tmp} do
      binary_path = Path.join(tmp, "demo_windows_x86_64.exe")
      File.write!(binary_path, "fake-windows-binary")

      output_dir = Path.join(tmp, "out")

      archive =
        Archive.zip(binary_path, "demo.exe", "demo-0.1.0-x86_64-pc-windows-msvc", output_dir)

      assert archive == Path.join(output_dir, "demo-0.1.0-x86_64-pc-windows-msvc.zip")
      assert File.exists?(archive)

      {:ok, entries} = :zip.list_dir(String.to_charlist(archive))

      names =
        entries
        |> Enum.flat_map(fn
          {:zip_file, name, _, _, _, _} -> [to_string(name)]
          _ -> []
        end)

      assert names == ["demo.exe"]

      extract_dir = Path.join(tmp, "extracted")
      File.mkdir_p!(extract_dir)

      {:ok, _} =
        :zip.extract(String.to_charlist(archive), [{:cwd, String.to_charlist(extract_dir)}])

      assert File.read!(Path.join(extract_dir, "demo.exe")) == "fake-windows-binary"
    end

    @tag :tmp_dir
    test "zip also bundles extra files at their dest paths", %{tmp_dir: tmp} do
      bin = Path.join(tmp, "demo.exe")
      File.write!(bin, "fake-windows-binary")

      File.write!(Path.join(tmp, "LICENSE.txt"), "license bytes")

      extras = [{Path.join(tmp, "LICENSE.txt"), "LICENSE.txt"}]

      archive = Archive.zip(bin, "demo.exe", "demo-0.1.0-win", Path.join(tmp, "out"), extras)

      extract_dir = Path.join(tmp, "ex")
      File.mkdir_p!(extract_dir)

      {:ok, _} =
        :zip.extract(String.to_charlist(archive), [{:cwd, String.to_charlist(extract_dir)}])

      assert File.read!(Path.join(extract_dir, "demo.exe")) == "fake-windows-binary"
      assert File.read!(Path.join(extract_dir, "LICENSE.txt")) == "license bytes"
    end
  end

  describe "sha256/1" do
    @tag :tmp_dir
    test "writes a shasum-style sidecar and returns the digest", %{tmp_dir: tmp} do
      path = Path.join(tmp, "asset.tar.gz")
      File.write!(path, "hello, tinfoil")

      {digest, sidecar} = Archive.sha256(path)

      # Known SHA256 for "hello, tinfoil"
      expected =
        :sha256
        |> :crypto.hash("hello, tinfoil")
        |> Base.encode16(case: :lower)

      assert digest == expected
      assert sidecar == path <> ".sha256"
      assert File.read!(sidecar) == "#{digest}  asset.tar.gz\n"
    end
  end

  describe "combined_checksums/2" do
    @tag :tmp_dir
    test "concatenates every .sha256 sidecar in sorted order", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "a.tar.gz.sha256"), "aaa  a.tar.gz\n")
      File.write!(Path.join(tmp, "b.tar.gz.sha256"), "bbb  b.tar.gz\n")
      File.write!(Path.join(tmp, "c.tar.gz.sha256"), "ccc  c.tar.gz\n")

      combined = Archive.combined_checksums(tmp)

      assert combined == Path.join(tmp, "checksums-sha256.txt")
      assert File.read!(combined) == "aaa  a.tar.gz\nbbb  b.tar.gz\nccc  c.tar.gz\n"
    end

    @tag :tmp_dir
    test "honors a custom combined-file name", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "x.tar.gz.sha256"), "xxx  x.tar.gz\n")
      combined = Archive.combined_checksums(tmp, "SHA256SUMS")

      assert combined == Path.join(tmp, "SHA256SUMS")
      assert File.read!(combined) == "xxx  x.tar.gz\n"
    end
  end
end
