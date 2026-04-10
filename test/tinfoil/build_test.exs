defmodule Tinfoil.BuildTest do
  use ExUnit.Case, async: false

  alias Tinfoil.{Build, Config}

  defp build_config(targets) do
    project = [
      app: :my_cli,
      version: "1.2.3",
      description: "A test CLI",
      package: [licenses: ["MIT"]],
      releases: [
        my_cli: [
          burrito: [
            targets: [
              darwin_arm64: [os: :darwin, cpu: :aarch64],
              linux_x86_64: [os: :linux, cpu: :x86_64]
            ]
          ]
        ]
      ],
      tinfoil: [targets: targets]
    ]

    {:ok, config} = Config.load(project)
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  describe "run/2 with skip_release" do
    @tag :tmp_dir
    test "packages an existing burrito_out binary into an archive with sha256", %{tmp_dir: tmp} do
      config = build_config([:darwin_arm64])

      # Fake Burrito output: burrito_out/my_cli_darwin_arm64
      burrito_out = Path.join(tmp, "burrito_out")
      File.mkdir_p!(burrito_out)
      fake_binary = Path.join(burrito_out, "my_cli_darwin_arm64")
      File.write!(fake_binary, "pretend burrito ERTS + BEAM bytes")

      # Build.run uses relative paths for burrito_out, so we chdir.
      result =
        File.cd!(tmp, fn ->
          Build.run(config,
            target: :darwin_arm64,
            skip_release: true,
            output_dir: "_tinfoil"
          )
        end)

      assert result.target == :darwin_arm64
      assert result.burrito_name == :darwin_arm64
      assert result.binary == "burrito_out/my_cli_darwin_arm64"

      archive_path = Path.join([tmp, "_tinfoil", "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"])
      assert File.exists?(archive_path)
      assert result.archive == "_tinfoil/my_cli-1.2.3-aarch64-apple-darwin.tar.gz"

      sidecar = archive_path <> ".sha256"
      assert File.exists?(sidecar)
      assert File.read!(sidecar) =~ "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"
      assert result.sha256 == String.slice(File.read!(sidecar), 0, 64)
    end

    @tag :tmp_dir
    test "raises when the expected burrito binary is missing", %{tmp_dir: tmp} do
      config = build_config([:linux_x86_64])

      File.mkdir_p!(Path.join(tmp, "burrito_out"))

      assert_raise RuntimeError, ~r/no Burrito output at/, fn ->
        File.cd!(tmp, fn ->
          Build.run(config,
            target: :linux_x86_64,
            skip_release: true,
            output_dir: "_tinfoil"
          )
        end)
      end
    end

    @tag :tmp_dir
    test "uses the user's Burrito target name when it differs from the tinfoil atom",
         %{tmp_dir: tmp} do
      # woof-style config: darwin_arm64 -> :macos_m1
      project = [
        app: :woof,
        version: "0.1.0",
        package: [licenses: ["MIT"]],
        releases: [
          woof: [
            burrito: [targets: [macos_m1: [os: :darwin, cpu: :aarch64]]]
          ]
        ],
        tinfoil: [targets: [:darwin_arm64]]
      ]

      {:ok, config} = Config.load(project)
      config = %{config | github: %{config.github | repo: "owner/woof"}}

      burrito_out = Path.join(tmp, "burrito_out")
      File.mkdir_p!(burrito_out)
      File.write!(Path.join(burrito_out, "woof_macos_m1"), "bytes")

      result =
        File.cd!(tmp, fn ->
          Build.run(config, target: :darwin_arm64, skip_release: true, output_dir: "_tinfoil")
        end)

      assert result.burrito_name == :macos_m1
      assert result.binary == "burrito_out/woof_macos_m1"
    end
  end
end
