defmodule Tinfoil.TargetTest do
  use ExUnit.Case, async: true

  alias Tinfoil.Target

  @extra %{
    linux_riscv64: %{
      runner: "ubuntu-latest",
      burrito_os: :linux,
      burrito_cpu: :riscv64,
      triple: "riscv64-unknown-linux-musl",
      archive_ext: ".tar.gz",
      os_family: :linux
    }
  }

  describe "builtin/0 and all/1" do
    test "builtin/0 returns just the hardcoded targets" do
      assert Enum.sort(Target.builtin()) ==
               Enum.sort([:darwin_arm64, :darwin_x86_64, :linux_arm64, :linux_x86_64])
    end

    test "all/1 merges extras on top of builtins" do
      assert :linux_riscv64 in Target.all(@extra)
      assert :darwin_arm64 in Target.all(@extra)
    end
  end

  describe "extras" do
    test "spec!/2 resolves user-defined targets" do
      spec = Target.spec!(:linux_riscv64, @extra)
      assert spec.triple == "riscv64-unknown-linux-musl"
      assert spec.burrito_cpu == :riscv64
    end

    test "validate/2 accepts extras as valid targets" do
      assert Target.validate([:darwin_arm64, :linux_riscv64], @extra) == :ok
    end

    test "validate_extras rejects shadowing a built-in" do
      shadow = %{darwin_arm64: @extra.linux_riscv64}

      assert {:error, {:extra_target_shadows_builtin, :darwin_arm64}} =
               Target.validate_extras(shadow)
    end

    test "validate_extras rejects missing keys" do
      incomplete = %{linux_riscv64: %{runner: "x", triple: "y"}}

      assert {:error, {:extra_target_missing_keys, :linux_riscv64, missing}} =
               Target.validate_extras(incomplete)

      assert :burrito_os in missing
    end

    test "validate_extras tolerates nil and empty map" do
      assert Target.validate_extras(nil) == {:ok, %{}}
      assert Target.validate_extras(%{}) == {:ok, %{}}
    end
  end

  describe "spec/1 and spec!/1" do
    test "returns the full spec for a known target" do
      spec = Target.spec!(:darwin_arm64)
      assert spec.runner == "macos-latest"
      assert spec.triple == "aarch64-apple-darwin"
      assert spec.burrito_os == :darwin
      assert spec.burrito_cpu == :aarch64
      assert spec.os_family == :darwin
    end

    test "spec/1 returns nil for unknown targets" do
      assert Target.spec(:freebsd_x86_64) == nil
    end

    test "spec!/1 raises on unknown targets" do
      assert_raise ArgumentError, ~r/unknown tinfoil target/, fn ->
        Target.spec!(:freebsd_x86_64)
      end
    end
  end

  describe "triple/1" do
    test "returns standard Rust-style triples" do
      assert Target.triple(:darwin_arm64) == "aarch64-apple-darwin"
      assert Target.triple(:darwin_x86_64) == "x86_64-apple-darwin"
      assert Target.triple(:linux_x86_64) == "x86_64-unknown-linux-musl"
      assert Target.triple(:linux_arm64) == "aarch64-unknown-linux-musl"
    end
  end

  describe "burrito_target/1" do
    test "returns the keyword list Burrito expects" do
      assert Target.burrito_target(:darwin_arm64) == [os: :darwin, cpu: :aarch64]
      assert Target.burrito_target(:linux_x86_64) == [os: :linux, cpu: :x86_64]
    end
  end

  describe "validate/1" do
    test "accepts a list of known targets" do
      assert Target.validate([:darwin_arm64, :linux_x86_64]) == :ok
    end

    test "returns an error tuple listing unknown targets" do
      assert {:error, {:unknown_targets, [:windows_x86_64, :freebsd_x86_64]}} =
               Target.validate([:darwin_arm64, :windows_x86_64, :freebsd_x86_64])
    end
  end
end
