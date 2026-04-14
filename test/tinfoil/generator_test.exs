defmodule Tinfoil.GeneratorTest do
  use ExUnit.Case, async: true

  alias Tinfoil.{Config, Generator}

  import Tinfoil.ProjectHelpers, only: [default_releases: 0]

  defp build_config(extra \\ []) do
    project =
      [
        app: :my_cli,
        version: "1.2.3",
        description: "A test CLI",
        homepage_url: "https://example.com/my_cli",
        package: [licenses: ["MIT"]],
        releases: default_releases(),
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
      assert ".github/workflows/release.yml" in paths
      # The bash update-homebrew.sh was absorbed into mix tinfoil.homebrew.
      refute "scripts/update-homebrew.sh" in paths
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
      workflow = Enum.find(files, &(&1.path == ".github/workflows/release.yml"))

      assert install.executable
      refute workflow.executable
    end
  end

  describe "workflow rendering" do
    test "workflow includes every configured target" do
      yaml = build_config() |> Generator.render_workflow()

      # Triples no longer appear in the matrix — that lookup happens inside
      # `mix tinfoil.build`. The matrix just carries target atoms + runners.
      assert yaml =~ "id: darwin_arm64"
      assert yaml =~ "id: darwin_x86_64"
      assert yaml =~ "id: linux_x86_64"
      assert yaml =~ "id: linux_arm64"
      assert yaml =~ "macos-latest"
      assert yaml =~ "macos-15-intel"
      assert yaml =~ "ubuntu-latest"
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

    test "workflow includes homebrew job with token auth by default" do
      yaml =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap"])
        |> Generator.render_workflow()

      assert yaml =~ "homebrew:"
      assert yaml =~ "HOMEBREW_TAP_TOKEN"
      assert yaml =~ "mix tinfoil.homebrew --input-dir artifacts"
      refute yaml =~ "webfactory/ssh-agent"
    end

    test "workflow uses deploy key auth when configured" do
      yaml =
        build_config(homebrew: [enabled: true, tap: "owner/homebrew-tap", auth: :deploy_key])
        |> Generator.render_workflow()

      assert yaml =~ "webfactory/ssh-agent"
      assert yaml =~ "HOMEBREW_TAP_DEPLOY_KEY"
      refute yaml =~ "HOMEBREW_TAP_TOKEN"
    end

    test "workflow delegates build to mix tinfoil.build" do
      yaml = build_config() |> Generator.render_workflow()

      assert yaml =~ ~S(mix tinfoil.build --target "$target")
      assert yaml =~ "for target in"
      assert yaml =~ ~S(tr ',' ' ')
      refute yaml =~ "BURRITO_TARGET"
      refute yaml =~ "burrito_out/"
    end

    test "workflow delegates publish to mix tinfoil.publish with GITHUB_TOKEN" do
      yaml = build_config() |> Generator.render_workflow()

      assert yaml =~ "mix tinfoil.publish --input-dir artifacts"
      assert yaml =~ "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}"
      refute yaml =~ "softprops/action-gh-release"
    end

    test "build job caches deps per matrix target" do
      yaml = build_config() |> Generator.render_workflow()

      assert yaml =~ "actions/cache@v5"
      # Build cache key includes the matrix target so each runner has its own
      assert yaml =~ ~s(key: ${{ runner.os }}-${{ matrix.id }}-mix-)
    end

    test "release job caches deps separately from build" do
      yaml = build_config() |> Generator.render_workflow()

      assert yaml =~ ~s(key: ${{ runner.os }}-release-mix-)
    end

    test "workflow adds --draft when github.draft is true" do
      yaml =
        build_config(
          targets: [:darwin_arm64],
          github: [draft: true]
        )
        |> Generator.render_workflow()

      assert yaml =~ "mix tinfoil.publish --input-dir artifacts --draft"
    end

    test "workflow matrix entries include burrito_name mapped from the user's release config" do
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
      yaml = Generator.render_workflow(config)

      # burrito_name lookup happens inside `mix tinfoil.build` at runtime;
      # the matrix just passes the tinfoil target atom. End-to-end coverage
      # lives in Tinfoil.BuildTest.
      assert yaml =~ ~s(targets: "darwin_arm64")
      assert yaml =~ ~s(targets: "linux_x86_64")
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
