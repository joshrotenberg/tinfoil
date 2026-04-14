defmodule Tinfoil.HomebrewTest do
  use ExUnit.Case, async: false

  alias Tinfoil.{Config, Homebrew}

  @moduletag :tmp_dir

  defmodule GitStub do
    @moduledoc """
    In-process stub for `Tinfoil.Homebrew.Git` that records calls and
    lets a test control whether there are staged changes to commit.
    Behavior is driven by :ets to avoid coupling across async tests
    (the parent Homebrew test sets :async: false, so a single table
    name works).
    """
    @behaviour Tinfoil.Homebrew.Git

    @table :tinfoil_homebrew_git_stub

    def setup(opts \\ []) do
      if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
      :ets.new(@table, [:named_table, :public])
      :ets.insert(@table, {:staged, Keyword.get(opts, :staged, true)})
      :ets.insert(@table, {:calls, []})
    end

    def calls, do: :ets.lookup_element(@table, :calls, 2)

    defp record(tag), do: :ets.update_element(@table, :calls, {2, calls() ++ [tag]})

    @impl true
    def clone(url, dir) do
      File.mkdir_p!(dir)
      record({:clone, url, dir})
      :ok
    end

    @impl true
    def config_identity(_dir, _name, _email) do
      record(:config_identity)
      :ok
    end

    @impl true
    def add(_dir, relative_path) do
      record({:add, relative_path})
      :ok
    end

    @impl true
    def staged_changes?(_dir) do
      :ets.lookup_element(@table, :staged, 2)
    end

    @impl true
    def commit(_dir, message) do
      record({:commit, message})
      {:ok, "deadbeef1234567"}
    end

    @impl true
    def push(_dir) do
      record(:push)
      :ok
    end
  end

  defp build_config(extra_tinfoil \\ []) do
    releases = [
      my_cli: [
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            linux_x86_64: [os: :linux, cpu: :x86_64]
          ]
        ]
      ]
    ]

    tinfoil =
      Keyword.merge(
        [
          targets: [:darwin_arm64, :linux_x86_64],
          homebrew: [
            enabled: true,
            tap: "owner/homebrew-tap",
            formula_name: "my_cli"
          ]
        ],
        extra_tinfoil
      )

    project = [
      app: :my_cli,
      version: "1.2.3",
      package: [licenses: ["MIT"]],
      releases: releases,
      tinfoil: tinfoil
    ]

    {:ok, config} = Config.load(project)
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  defp write_artifacts(input_dir, shas) do
    File.mkdir_p!(input_dir)

    Enum.each(shas, fn {archive, sha} ->
      path = Path.join(input_dir, archive)
      File.write!(path, "bytes")
      File.write!(path <> ".sha256", "#{sha}  #{archive}\n")
    end)
  end

  defp write_formula_template(root) do
    tinfoil_dir = Path.join(root, ".tinfoil")
    File.mkdir_p!(tinfoil_dir)

    File.write!(Path.join(tinfoil_dir, "formula.rb.eex"), """
    class MyCli < Formula
      version "__VERSION__"
      url "https://example.com/aarch64-apple-darwin.tar.gz"
      sha256 "__SHA256_DARWIN_ARM64__"
      url "https://example.com/x86_64-unknown-linux-musl.tar.gz"
      sha256 "__SHA256_LINUX_X86_64__"
    end
    """)
  end

  setup %{tmp_dir: tmp} do
    cwd = File.cwd!()
    File.cd!(tmp)
    GitStub.setup()
    on_exit(fn -> File.cd!(cwd) end)
    :ok
  end

  describe "publish/2" do
    test "renders the formula and pushes when staged changes exist", %{tmp_dir: tmp} do
      write_formula_template(tmp)

      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      tap = Path.join(tmp, "tap")
      System.put_env("HOMEBREW_TAP_TOKEN", "fake-token")

      {:ok, result} =
        Homebrew.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          tap_dir: tap,
          git: GitStub
        )

      assert result.pushed == true
      assert result.commit_sha == "deadbeef1234567"
      assert result.formula_path == Path.join([tap, "Formula", "my_cli.rb"])

      rendered = File.read!(result.formula_path)
      assert rendered =~ ~s|version "1.2.3"|
      assert rendered =~ "sha256 \"#{String.duplicate("a", 64)}\""
      assert rendered =~ "sha256 \"#{String.duplicate("b", 64)}\""
      refute rendered =~ "__VERSION__"
      refute rendered =~ "__SHA256_"

      calls = GitStub.calls()
      assert Enum.any?(calls, &match?({:clone, _, _}, &1))
      assert {:commit, "my_cli 1.2.3"} in calls
      assert :push in calls
    end

    test "returns pushed: false when nothing changed", %{tmp_dir: tmp} do
      write_formula_template(tmp)

      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      GitStub.setup(staged: false)
      System.put_env("HOMEBREW_TAP_TOKEN", "fake-token")

      {:ok, result} =
        Homebrew.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          tap_dir: Path.join(tmp, "tap"),
          git: GitStub
        )

      assert result.pushed == false
      assert result.commit_sha == nil
      refute :push in GitStub.calls()
    end

    test "uses SSH clone URL when auth is :deploy_key", %{tmp_dir: tmp} do
      write_formula_template(tmp)

      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      config =
        build_config(
          homebrew: [
            enabled: true,
            tap: "owner/homebrew-tap",
            formula_name: "my_cli",
            auth: :deploy_key
          ]
        )

      {:ok, _} =
        Homebrew.publish(config,
          input_dir: input,
          tag: "v1.2.3",
          tap_dir: Path.join(tmp, "tap"),
          git: GitStub
        )

      {:clone, url, _} = Enum.find(GitStub.calls(), &match?({:clone, _, _}, &1))
      assert url == "git@github.com:owner/homebrew-tap.git"
    end

    test "errors when the sha256 sidecar is missing", %{tmp_dir: tmp} do
      write_formula_template(tmp)

      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64)
        # linux sidecar intentionally omitted
      })

      System.put_env("HOMEBREW_TAP_TOKEN", "fake-token")

      assert {:error, {:missing_sha_sidecar, :linux_x86_64, _}} =
               Homebrew.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 tap_dir: Path.join(tmp, "tap"),
                 git: GitStub
               )
    end

    test "dry-run renders the formula without cloning or pushing", %{tmp_dir: tmp} do
      write_formula_template(tmp)
      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      System.put_env("HOMEBREW_TAP_TOKEN", "secret-token")

      # No git stub needed — dry-run must never invoke git.
      {:ok, preview} =
        Homebrew.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          dry_run: true
        )

      assert preview.dry_run == true
      assert preview.tap == "owner/homebrew-tap"
      assert preview.auth == :token
      assert preview.commit_message == "my_cli 1.2.3"
      assert preview.formula_name == "my_cli.rb"
      assert preview.formula =~ ~s|version "1.2.3"|
      # The token must be redacted — never print the real secret.
      refute preview.clone_url =~ "secret-token"
      assert preview.clone_url =~ "x-access-token:****"
    end

    test "dry-run shows an SSH clone URL for deploy-key auth", %{tmp_dir: tmp} do
      write_formula_template(tmp)
      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      config =
        build_config(
          homebrew: [
            enabled: true,
            tap: "owner/homebrew-tap",
            formula_name: "my_cli",
            auth: :deploy_key
          ]
        )

      {:ok, preview} =
        Homebrew.publish(config, input_dir: input, tag: "v1.2.3", dry_run: true)

      assert preview.auth == :deploy_key
      assert preview.clone_url == "git@github.com:owner/homebrew-tap.git"
    end

    test "errors when homebrew is not enabled" do
      releases = [my_cli: [burrito: [targets: [darwin_arm64: [os: :darwin, cpu: :aarch64]]]]]

      project = [
        app: :my_cli,
        version: "1.2.3",
        package: [licenses: ["MIT"]],
        releases: releases,
        tinfoil: [targets: [:darwin_arm64]]
      ]

      {:ok, config} = Config.load(project)
      assert {:error, :homebrew_not_enabled} = Homebrew.publish(config)
    end

    test "errors when HOMEBREW_TAP_TOKEN missing under :token auth", %{tmp_dir: tmp} do
      write_formula_template(tmp)

      input = Path.join(tmp, "artifacts")

      write_artifacts(input, %{
        "my_cli-1.2.3-aarch64-apple-darwin.tar.gz" => String.duplicate("a", 64),
        "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz" => String.duplicate("b", 64)
      })

      System.delete_env("HOMEBREW_TAP_TOKEN")

      assert {:error, :missing_homebrew_tap_token} =
               Homebrew.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 tap_dir: Path.join(tmp, "tap"),
                 git: GitStub
               )
    end
  end
end
