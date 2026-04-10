defmodule Tinfoil.ConfigTest do
  use ExUnit.Case, async: true

  alias Tinfoil.Config

  defp base_project(tinfoil_opts, opts \\ []) do
    releases = Keyword.get(opts, :releases, default_releases())

    [
      app: :my_cli,
      version: "1.2.3",
      description: "A test CLI",
      homepage_url: "https://example.com/my_cli",
      package: [licenses: ["Apache-2.0"]],
      releases: releases,
      tinfoil: tinfoil_opts
    ]
  end

  # Burrito targets using tinfoil's own atom names — keeps default-case
  # assertions trivial (burrito_name == tinfoil target atom).
  defp default_releases do
    [
      my_cli: [
        steps: [:assemble],
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  describe "load/1" do
    test "returns an error when no :tinfoil key is present" do
      assert {:error, :missing_tinfoil_config} =
               Config.load(app: :my_cli, version: "1.0.0", releases: default_releases())
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
      assert config.burrito_names == %{darwin_arm64: :darwin_arm64, linux_x86_64: :linux_x86_64}
      assert config.archive_name == "{app}-{version}-{target}"
      assert config.archive_format == :tar_gz
      assert config.checksums == :sha256
      assert config.github.draft == false
      assert config.homebrew.enabled == false
      assert config.homebrew.formula_name == "my_cli"
      assert config.installer.enabled == false
      assert config.installer.install_dir == "~/.local/bin"
      assert config.ci.elixir_version == "1.19"
      assert config.ci.zig_version == "0.15.2"
    end

    test "infers ci.elixir_version from the project's :elixir requirement" do
      for {req, expected} <- [
            {"~> 1.19", "1.19"},
            {"~> 1.17.0", "1.17"},
            {">= 1.15", "1.15"},
            {"1.16.3", "1.16"}
          ] do
        project =
          base_project(targets: [:darwin_arm64, :linux_x86_64])
          |> Keyword.put(:elixir, req)

        {:ok, config} = Config.load(project)

        assert config.ci.elixir_version == expected,
               "expected #{inspect(req)} -> #{inspect(expected)}, got #{inspect(config.ci.elixir_version)}"
      end
    end

    test "ci.elixir_version falls back when project :elixir is absent or unparseable" do
      {:ok, config} =
        Config.load(base_project(targets: [:darwin_arm64, :linux_x86_64]))

      # base_project has no :elixir, so we get the fallback
      assert config.ci.elixir_version == "1.19"
    end

    test "explicit ci.elixir_version override beats auto-detection" do
      project =
        base_project(
          targets: [:darwin_arm64, :linux_x86_64],
          ci: [elixir_version: "1.16"]
        )
        |> Keyword.put(:elixir, "~> 1.19")

      {:ok, config} = Config.load(project)

      assert config.ci.elixir_version == "1.16"
    end

    test "resolves burrito_names from the user's release config" do
      woof_style = [
        my_cli: [
          burrito: [
            targets: [
              macos: [os: :darwin, cpu: :x86_64],
              macos_m1: [os: :darwin, cpu: :aarch64],
              linux: [os: :linux, cpu: :x86_64]
            ]
          ]
        ]
      ]

      {:ok, config} =
        Config.load(
          base_project(
            [targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64]],
            releases: woof_style
          )
        )

      assert config.burrito_names == %{
               darwin_arm64: :macos_m1,
               darwin_x86_64: :macos,
               linux_x86_64: :linux
             }
    end

    test "errors when a tinfoil target has no matching burrito target" do
      linux_only = [
        my_cli: [burrito: [targets: [linux: [os: :linux, cpu: :x86_64]]]]
      ]

      assert {:error, {:no_matching_burrito_target, :darwin_arm64}} =
               Config.load(
                 base_project(
                   [targets: [:darwin_arm64, :linux_x86_64]],
                   releases: linux_only
                 )
               )
    end

    test "errors when :archive_name is missing the {target} token" do
      assert {:error, {:archive_name_missing_target_token, "my_cli-{version}"}} =
               Config.load(
                 base_project(
                   targets: [:darwin_arm64, :linux_x86_64],
                   archive_name: "my_cli-{version}"
                 )
               )
    end

    test "errors when :archive_name is not a string" do
      assert {:error, :archive_name_not_string} =
               Config.load(
                 base_project(
                   targets: [:darwin_arm64],
                   archive_name: :an_atom
                 )
               )
    end

    test "errors when :archive_format is not supported" do
      assert {:error, {:invalid_archive_format, :rar}} =
               Config.load(
                 base_project(
                   targets: [:darwin_arm64],
                   archive_format: :rar
                 )
               )
    end

    test "accepts :tar_gz and :zip as archive formats" do
      for fmt <- [:tar_gz, :zip] do
        {:ok, config} =
          Config.load(
            base_project(
              targets: [:darwin_arm64],
              archive_format: fmt
            )
          )

        assert config.archive_format == fmt
      end
    end

    test "errors when :homebrew is enabled without a tap" do
      assert {:error, :homebrew_enabled_without_tap} =
               Config.load(
                 base_project(
                   targets: [:darwin_arm64],
                   homebrew: [enabled: true]
                 )
               )
    end

    test "errors when :homebrew is enabled with an empty tap string" do
      assert {:error, :homebrew_enabled_without_tap} =
               Config.load(
                 base_project(
                   targets: [:darwin_arm64],
                   homebrew: [enabled: true, tap: ""]
                 )
               )
    end

    test "accepts :homebrew enabled with a non-empty tap" do
      {:ok, config} =
        Config.load(
          base_project(
            targets: [:darwin_arm64],
            homebrew: [enabled: true, tap: "owner/homebrew-tap"]
          )
        )

      assert config.homebrew.enabled == true
      assert config.homebrew.tap == "owner/homebrew-tap"
    end

    test "errors when :releases is missing entirely" do
      project = [
        app: :my_cli,
        version: "1.0.0",
        tinfoil: [targets: [:darwin_arm64]]
      ]

      assert {:error, :missing_releases} = Config.load(project)
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
      assert config.ci.zig_version == "0.15.2"
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

    test "raises a readable error when a burrito target can't be matched" do
      linux_only = [
        my_cli: [burrito: [targets: [linux: [os: :linux, cpu: :x86_64]]]]
      ]

      assert_raise ArgumentError, ~r/no matching Burrito target/, fn ->
        Config.load!(
          base_project(
            [targets: [:darwin_arm64]],
            releases: linux_only
          )
        )
      end
    end
  end
end
