defmodule Tinfoil.GeneratorTest do
  use ExUnit.Case, async: true

  alias Tinfoil.{Config, Generator}

  defp build_config(extra \\ []) do
    project =
      [
        app: :my_cli,
        version: "1.2.3",
        description: "A test CLI",
        homepage_url: "https://example.com/my_cli",
        package: [licenses: ["MIT"]],
        tinfoil:
          Keyword.merge(
            [targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64]],
            extra
          )
      ]

    {:ok, config} = Config.load(project)
    # Force a repo so generators don't call git.
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  describe "render/1" do
    test "emits just the workflow when homebrew and installer are disabled" do
      files = Generator.render(build_config())
      paths = Enum.map(files, & &1.path)

      assert paths == [".github/workflows/release.yml"]
    end

    test "emits homebrew files when homebrew is enabled" do
      config = build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
      paths = config |> Generator.render() |> Enum.map(& &1.path)

      assert ".tinfoil/formula.rb.eex" in paths
      assert "scripts/update-homebrew.sh" in paths
      assert ".github/workflows/release.yml" in paths
    end

    test "emits the installer script when installer is enabled" do
      config = build_config(installer: [enabled: true])
      paths = config |> Generator.render() |> Enum.map(& &1.path)

      assert "scripts/install.sh" in paths
    end

    test "shell scripts are marked executable" do
      config =
        build_config(
          installer: [enabled: true],
          homebrew: [enabled: true, tap: "owner/tap"]
        )

      files = Generator.render(config)
      install = Enum.find(files, &(&1.path == "scripts/install.sh"))
      update = Enum.find(files, &(&1.path == "scripts/update-homebrew.sh"))
      workflow = Enum.find(files, &(&1.path == ".github/workflows/release.yml"))

      assert install.executable
      assert update.executable
      refute workflow.executable
    end
  end

  describe "workflow rendering" do
    test "workflow includes every configured target" do
      yaml = build_config() |> Generator.render_workflow()

      assert yaml =~ "aarch64-apple-darwin"
      assert yaml =~ "x86_64-apple-darwin"
      assert yaml =~ "x86_64-unknown-linux-musl"
      assert yaml =~ "aarch64-unknown-linux-musl"
      assert yaml =~ "macos-latest"
      assert yaml =~ "macos-13"
      assert yaml =~ "ubuntu-latest"
      assert yaml =~ "ubuntu-24.04-arm"
    end

    test "workflow respects configured tool versions" do
      yaml =
        build_config(ci: [elixir_version: "1.17", otp_version: "27", zig_version: "0.14.0"])
        |> Generator.render_workflow()

      assert yaml =~ ~s(elixir-version: "1.17")
      assert yaml =~ ~s(otp-version: "27")
      assert yaml =~ ~s(version: "0.14.0")
    end

    test "workflow omits homebrew job when disabled" do
      yaml = build_config() |> Generator.render_workflow()
      refute yaml =~ "homebrew:"
      refute yaml =~ "HOMEBREW_TAP_TOKEN"
    end

    test "workflow includes homebrew job when enabled" do
      yaml =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
        |> Generator.render_workflow()

      assert yaml =~ "homebrew:"
      assert yaml =~ "HOMEBREW_TAP_TOKEN"
      assert yaml =~ "TAP_REPO: owner/homebrew-tap"
    end

    test "workflow interpolates the archive template" do
      yaml =
        build_config(archive_name: "{app}_v{version}_{target}")
        |> Generator.render_workflow()

      assert yaml =~ ~s(BASENAME="{app}_v{version}_{target}")
    end
  end

  describe "formula rendering" do
    test "renders a Homebrew formula with placeholders" do
      rb =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
        |> Generator.render_formula()

      assert rb =~ ~s(class MyCli < Formula)
      assert rb =~ ~s(desc "A test CLI")
      assert rb =~ ~s(homepage "https://example.com/my_cli")
      assert rb =~ ~s(license "MIT")
      assert rb =~ "__VERSION__"
      assert rb =~ "__SHA256_DARWIN_ARM64__"
      assert rb =~ "__SHA256_LINUX_X86_64__"
      assert rb =~ "on_macos do"
      assert rb =~ "on_linux do"
      assert rb =~ ~s(bin.install "my_cli")
    end

    test "only emits blocks for configured targets" do
      config =
        build_config(
          targets: [:darwin_arm64, :linux_x86_64],
          homebrew: [enabled: true, tap: "owner/homebrew-tap"]
        )

      rb = Generator.render_formula(config)

      assert rb =~ "on_macos do"
      assert rb =~ "on_linux do"
      assert rb =~ "__SHA256_DARWIN_ARM64__"
      assert rb =~ "__SHA256_LINUX_X86_64__"
      refute rb =~ "__SHA256_DARWIN_X86_64__"
      refute rb =~ "__SHA256_LINUX_ARM64__"
    end
  end

  describe "installer rendering" do
    test "renders install.sh referencing the configured repo" do
      sh =
        build_config(installer: [enabled: true])
        |> Generator.render_installer()

      assert sh =~ ~s(APP="my_cli")
      assert sh =~ ~s(REPO="owner/my_cli")
      assert sh =~ ~s(DEFAULT_INSTALL_DIR="~/.local/bin")
    end
  end

  describe "update_homebrew rendering" do
    test "uses the configured formula name" do
      sh =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
        |> Generator.render_update_homebrew()

      assert sh =~ "Formula/my_cli.rb"
    end
  end

  describe "write!/2" do
    @tag :tmp_dir
    test "writes generated files into root", %{tmp_dir: tmp} do
      config =
        build_config(
          installer: [enabled: true],
          homebrew: [enabled: true, tap: "owner/homebrew-tap"]
        )

      result = Generator.write!(config, root: tmp)

      assert ".github/workflows/release.yml" in result.written
      assert "scripts/install.sh" in result.written
      assert "scripts/update-homebrew.sh" in result.written
      assert ".tinfoil/formula.rb.eex" in result.written

      assert File.exists?(Path.join(tmp, ".github/workflows/release.yml"))

      install_path = Path.join(tmp, "scripts/install.sh")
      assert File.exists?(install_path)

      # Executable bit
      %File.Stat{mode: mode} = File.stat!(install_path)
      assert Bitwise.band(mode, 0o100) != 0
    end
  end
end
