defmodule Tinfoil.ConfigTest do
  use ExUnit.Case, async: true

  alias Tinfoil.Config

  defp base_project(tinfoil_opts) do
    [
      app: :my_cli,
      version: "1.2.3",
      description: "A test CLI",
      homepage_url: "https://example.com/my_cli",
      package: [licenses: ["Apache-2.0"]],
      tinfoil: tinfoil_opts
    ]
  end

  describe "load/1" do
    test "returns an error when no :tinfoil key is present" do
      assert {:error, :missing_tinfoil_config} =
               Config.load(app: :my_cli, version: "1.0.0")
    end

    test "returns an error when targets are missing" do
      assert {:error, :missing_targets} = Config.load(base_project([]))
    end

    test "returns an error when targets are empty" do
      assert {:error, :empty_targets} = Config.load(base_project(targets: []))
    end

    test "returns an error on unknown targets" do
      assert {:error, {:unknown_targets, [:windows_x86_64]}} =
               Config.load(base_project(targets: [:darwin_arm64, :windows_x86_64]))
    end

    test "loads a minimal config with defaults" do
      {:ok, config} =
        Config.load(base_project(targets: [:darwin_arm64, :linux_x86_64]))

      assert config.app == :my_cli
      assert config.version == "1.2.3"
      assert config.description == "A test CLI"
      assert config.homepage_url == "https://example.com/my_cli"
      assert config.license == "Apache-2.0"
      assert config.targets == [:darwin_arm64, :linux_x86_64]
      assert config.archive_name == "{app}-{version}-{target}"
      assert config.archive_format == :tar_gz
      assert config.checksums == :sha256
      assert config.github.draft == false
      assert config.homebrew.enabled == false
      assert config.homebrew.formula_name == "my_cli"
      assert config.installer.enabled == false
      assert config.installer.install_dir == "~/.local/bin"
      assert config.ci.elixir_version == "1.18"
      assert config.ci.zig_version == "0.13.0"
    end

    test "merges user overrides with defaults" do
      {:ok, config} =
        Config.load(
          base_project(
            targets: [:darwin_arm64],
            archive_name: "{app}_{version}_{target}",
            homebrew: [enabled: true, tap: "owner/homebrew-tap"],
            installer: [enabled: true, install_dir: "/usr/local/bin"],
            ci: [elixir_version: "1.17", otp_version: "27"]
          )
        )

      assert config.archive_name == "{app}_{version}_{target}"
      assert config.homebrew.enabled == true
      assert config.homebrew.tap == "owner/homebrew-tap"
      assert config.homebrew.formula_name == "my_cli"
      assert config.installer.enabled == true
      assert config.installer.install_dir == "/usr/local/bin"
      assert config.ci.elixir_version == "1.17"
      assert config.ci.otp_version == "27"
      # unchanged defaults
      assert config.ci.zig_version == "0.13.0"
    end
  end

  describe "archive_basename/2 and archive_filename/2" do
    test "interpolates {app}, {version}, {target} into archive names" do
      {:ok, config} =
        Config.load(base_project(targets: [:darwin_arm64, :linux_x86_64]))

      assert Config.archive_basename(config, :darwin_arm64) ==
               "my_cli-1.2.3-aarch64-apple-darwin"

      assert Config.archive_filename(config, :darwin_arm64) ==
               "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"

      assert Config.archive_filename(config, :linux_x86_64) ==
               "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz"
    end

    test "respects a custom archive_name template" do
      {:ok, config} =
        Config.load(
          base_project(
            targets: [:darwin_arm64],
            archive_name: "{app}_v{version}_{target}"
          )
        )

      assert Config.archive_basename(config, :darwin_arm64) ==
               "my_cli_v1.2.3_aarch64-apple-darwin"
    end
  end

  describe "load!/1" do
    test "raises a readable error on invalid config" do
      assert_raise ArgumentError, ~r/unknown tinfoil targets/, fn ->
        Config.load!(base_project(targets: [:windows_x86_64]))
      end
    end
  end
end
