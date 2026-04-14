defmodule Tinfoil.PlanTest do
  use ExUnit.Case, async: true

  alias Tinfoil.{Config, Plan}

  import Tinfoil.ProjectHelpers, only: [default_releases: 0]

  defp build_config(extra \\ []) do
    project =
      [
        app: :my_cli,
        version: "1.2.3",
        description: "A test CLI",
        package: [licenses: ["MIT"]],
        releases: default_releases(),
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
      assert entry.burrito_name == :darwin_arm64
      assert entry.runner == "macos-latest"
      assert entry.triple == "aarch64-apple-darwin"
      assert entry.burrito_os == :darwin
      assert entry.burrito_cpu == :aarch64
      assert entry.os_family == :darwin
      assert entry.archive == "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"
    end

    test "burrito_name reflects the user's chosen release target names" do
      project = [
        app: :my_cli,
        version: "1.2.3",
        package: [licenses: ["MIT"]],
        releases: [
          my_cli: [
            burrito: [
              targets: [
                macos_m1: [os: :darwin, cpu: :aarch64],
                linux: [os: :linux, cpu: :x86_64]
              ]
            ]
          ]
        ],
        tinfoil: [targets: [:darwin_arm64, :linux_x86_64]]
      ]

      {:ok, config} = Config.load(project)
      config = %{config | github: %{config.github | repo: "owner/my_cli"}}
      plan = Plan.build(config)

      [darwin, linux] = plan.targets
      assert darwin.target == :darwin_arm64
      assert darwin.burrito_name == :macos_m1
      assert linux.target == :linux_x86_64
      assert linux.burrito_name == :linux
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

  describe "build_entries/1" do
    test "flat mode yields one entry per target preserving order" do
      entries =
        build_config()
        |> Plan.build()
        |> Plan.build_entries()

      assert Enum.map(entries, & &1.id) == [
               "darwin_arm64",
               "darwin_x86_64",
               "linux_x86_64",
               "linux_arm64"
             ]

      assert Enum.all?(entries, &(&1.targets == &1.id))
    end

    test "grouped mode collapses targets sharing runner + os_family" do
      entries =
        build_config(single_runner_per_os: true)
        |> Plan.build()
        |> Plan.build_entries()

      ids = Enum.map(entries, & &1.id) |> Enum.sort()
      assert ids == ["darwin", "linux"]

      # First darwin target listed is :darwin_arm64, so its runner
      # (macos-latest) owns the whole darwin family in grouped mode.
      darwin = Enum.find(entries, &(&1.id == "darwin"))
      assert darwin.runner == "macos-latest"
      assert String.split(darwin.targets, ",") |> Enum.sort() ==
               ["darwin_arm64", "darwin_x86_64"]

      linux = Enum.find(entries, &(&1.id == "linux"))
      assert linux.runner == "ubuntu-latest"
      assert String.split(linux.targets, ",") |> Enum.sort() ==
               ["linux_arm64", "linux_x86_64"]
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

      for key <- [
            :target,
            :burrito_name,
            :runner,
            :triple,
            :burrito_os,
            :burrito_cpu,
            :os_family,
            :archive
          ] do
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
      assert out =~ "ubuntu-latest"
    end

    test "shows the burrito column and burrito_name values" do
      out =
        build_config()
        |> Plan.build()
        |> Mix.Tasks.Tinfoil.Plan.render_human()

      assert out =~ "burrito"
      # Default-case base_project uses tinfoil atoms as burrito names.
      assert out =~ "darwin_arm64"
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
