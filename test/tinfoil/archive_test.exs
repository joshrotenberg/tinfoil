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
