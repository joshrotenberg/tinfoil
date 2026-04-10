defmodule Tinfoil.PlanTest do
  use ExUnit.Case, async: true

  alias Tinfoil.{Config, Plan}

  defp build_config(extra \\ []) do
    project =
      [
        app: :my_cli,
        version: "1.2.3",
        description: "A test CLI",
        package: [licenses: ["MIT"]],
        tinfoil:
          Keyword.merge(
            [targets: [:darwin_arm64, :darwin_x86_64, :linux_x86_64, :linux_arm64]],
            extra
          )
      ]

    {:ok, config} = Config.load(project)
    # Pin the inferred github repo so tests are deterministic regardless
    # of the environment's git remote.
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  describe "build/1" do
    test "returns top-level app and version from the config" do
      plan = build_config() |> Plan.build()

      assert plan.app == :my_cli
      assert plan.version == "1.2.3"
      assert plan.archive_format == :tar_gz
      assert plan.checksums == :sha256
    end

    test "preserves the order of configured targets" do
      plan = build_config(targets: [:linux_x86_64, :darwin_arm64]) |> Plan.build()

      assert Enum.map(plan.targets, & &1.target) == [:linux_x86_64, :darwin_arm64]
    end

    test "each target plan includes runner, triple, burrito os/cpu, archive" do
      plan = build_config(targets: [:darwin_arm64]) |> Plan.build()
      [entry] = plan.targets

      assert entry.target == :darwin_arm64
      assert entry.runner == "macos-latest"
      assert entry.triple == "aarch64-apple-darwin"
      assert entry.burrito_os == :darwin
      assert entry.burrito_cpu == :aarch64
      assert entry.os_family == :darwin
      assert entry.archive == "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"
    end

    test "archive filenames respect a custom archive_name template" do
      plan =
        build_config(
          targets: [:linux_x86_64],
          archive_name: "{app}_v{version}_{target}"
        )
        |> Plan.build()

      [entry] = plan.targets
      assert entry.archive == "my_cli_v1.2.3_x86_64-unknown-linux-musl.tar.gz"
    end

    test "passes github, homebrew, and installer through from config" do
      plan =
        build_config(
          targets: [:darwin_arm64],
          homebrew: [enabled: true, tap: "owner/homebrew-tap"],
          installer: [enabled: true, install_dir: "/usr/local/bin"]
        )
        |> Plan.build()

      assert plan.homebrew.enabled == true
      assert plan.homebrew.tap == "owner/homebrew-tap"
      assert plan.homebrew.formula_name == "my_cli"
      assert plan.installer.enabled == true
      assert plan.installer.install_dir == "/usr/local/bin"
      assert plan.github.repo == "owner/my_cli"
      assert plan.github.draft == false
    end
  end

  describe "matrix/1" do
    test "returns an include-wrapped list of target plans" do
      plan = build_config(targets: [:darwin_arm64, :linux_x86_64]) |> Plan.build()
      matrix = Plan.matrix(plan)

      assert Map.keys(matrix) == [:include]
      assert length(matrix.include) == 2
      assert Enum.map(matrix.include, & &1.target) == [:darwin_arm64, :linux_x86_64]
    end

    test "matrix entries carry every key GitHub Actions might want" do
      matrix = build_config(targets: [:darwin_arm64]) |> Plan.build() |> Plan.matrix()
      [entry] = matrix.include

      for key <- [:target, :runner, :triple, :burrito_os, :burrito_cpu, :os_family, :archive] do
        assert Map.has_key?(entry, key), "missing key #{inspect(key)}"
      end
    end
  end

  describe "JSON encoding" do
    test "full plan round-trips through Jason" do
      plan = build_config(targets: [:darwin_arm64, :linux_x86_64]) |> Plan.build()
      json = Jason.encode!(plan)
      decoded = Jason.decode!(json)

      assert decoded["app"] == "my_cli"
      assert decoded["version"] == "1.2.3"
      assert decoded["archive_format"] == "tar_gz"
      assert length(decoded["targets"]) == 2

      [first | _] = decoded["targets"]
      assert first["target"] == "darwin_arm64"
      assert first["runner"] == "macos-latest"
      assert first["triple"] == "aarch64-apple-darwin"
      assert first["archive"] == "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"
    end

    test "matrix output is a compact single-line JSON object" do
      json =
        build_config(targets: [:darwin_arm64])
        |> Plan.build()
        |> Plan.matrix()
        |> Jason.encode!()

      refute String.contains?(json, "\n")
      decoded = Jason.decode!(json)
      assert is_list(decoded["include"])
    end
  end

  describe "human rendering" do
    test "includes app, version, every triple, and every runner" do
      out =
        build_config()
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "my_cli"
      assert out =~ "1.2.3"
      assert out =~ "aarch64-apple-darwin"
      assert out =~ "x86_64-apple-darwin"
      assert out =~ "x86_64-unknown-linux-musl"
      assert out =~ "aarch64-unknown-linux-musl"
      assert out =~ "macos-latest"
      assert out =~ "ubuntu-24.04-arm"
    end

    test "shows 'disabled' for disabled extras" do
      out =
        build_config()
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "homebrew:  disabled"
      assert out =~ "installer: disabled"
    end

    test "shows tap info when homebrew is enabled" do
      out =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "owner/homebrew-tap"
      assert out =~ "formula: my_cli"
    end

    test "shows install dir when installer is enabled" do
      out =
        build_config(installer: [enabled: true, install_dir: "/opt/bin"])
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "installer: /opt/bin"
    end

    test "shows github repo and draft flag" do
      out =
        build_config()
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "owner/my_cli"
      assert out =~ "draft: false"
    end
  end
end
