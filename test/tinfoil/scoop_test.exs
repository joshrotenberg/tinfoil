defmodule Tinfoil.ScoopTest do
  use ExUnit.Case, async: false

  alias Tinfoil.{Config, Scoop}

  @moduletag :tmp_dir

  defmodule GitStub do
    @moduledoc """
    In-process stub for Tinfoil.Homebrew.Git (which Scoop reuses). Same
    shape as HomebrewTest.GitStub: records calls via ETS, lets a test
    toggle staged_changes?.
    """
    @behaviour Tinfoil.Homebrew.Git

    @table :tinfoil_scoop_git_stub

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
    def config_identity(_, _, _), do: (record(:config_identity) && :ok) || :ok

    @impl true
    def add(_dir, rel), do: (record({:add, rel}) && :ok) || :ok

    @impl true
    def staged_changes?(_dir), do: :ets.lookup_element(@table, :staged, 2)

    @impl true
    def commit(_dir, message) do
      record({:commit, message})
      {:ok, "deadbeefscoop12"}
    end

    @impl true
    def push(_dir), do: (record(:push) && :ok) || :ok
  end

  defp build_config(extra_tinfoil \\ []) do
    releases = [
      my_cli: [
        burrito: [
          targets: [
            windows_x86_64: [os: :windows, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64]
          ]
        ]
      ]
    ]

    tinfoil =
      Keyword.merge(
        [
          targets: [:windows_x86_64, :linux_x86_64],
          scoop: [
            enabled: true,
            bucket: "owner/scoop-bucket",
            manifest_name: "my_cli"
          ]
        ],
        extra_tinfoil
      )

    project = [
      app: :my_cli,
      version: "1.2.3",
      description: "A test CLI",
      package: [licenses: ["MIT"]],
      releases: releases,
      tinfoil: tinfoil
    ]

    {:ok, config} = Config.load(project)
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  defp write_win_sidecar(input_dir, sha) do
    File.mkdir_p!(input_dir)
    archive = "my_cli-1.2.3-x86_64-pc-windows-msvc.zip"
    File.write!(Path.join(input_dir, archive), "bytes")
    File.write!(Path.join(input_dir, archive <> ".sha256"), "#{sha}  #{archive}\n")
  end

  setup %{tmp_dir: tmp} do
    cwd = File.cwd!()
    File.cd!(tmp)
    GitStub.setup()
    on_exit(fn -> File.cd!(cwd) end)
    :ok
  end

  describe "publish/2" do
    test "renders a manifest and pushes when staged changes exist", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      sha = String.duplicate("a", 64)
      write_win_sidecar(input, sha)

      bucket = Path.join(tmp, "bucket")
      System.put_env("SCOOP_BUCKET_TOKEN", "fake-token")

      {:ok, result} =
        Scoop.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          bucket_dir: bucket,
          git: GitStub
        )

      assert result.pushed == true
      assert result.commit_sha == "deadbeefscoop12"
      assert result.manifest_path == Path.join(bucket, "my_cli.json")

      manifest = File.read!(result.manifest_path)
      assert manifest =~ ~s("version": "1.2.3")
      assert manifest =~ ~s("hash": "#{sha}")
      assert manifest =~ "my_cli-1.2.3-x86_64-pc-windows-msvc.zip"
      assert manifest =~ ~s("bin": "my_cli.exe")
    end

    test "errors when windows_x86_64 target isn't configured" do
      config =
        build_config(
          targets: [:linux_x86_64],
          scoop: [enabled: true, bucket: "owner/bucket", manifest_name: "my_cli"]
        )

      assert {:error, :missing_windows_target} = Scoop.publish(config, tag: "v1.2.3")
    end

    test "dry-run renders manifest without git side effects", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      write_win_sidecar(input, String.duplicate("b", 64))

      System.put_env("SCOOP_BUCKET_TOKEN", "real-token-not-printed")

      {:ok, preview} =
        Scoop.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          dry_run: true
        )

      assert preview.dry_run == true
      assert preview.bucket == "owner/scoop-bucket"
      assert preview.manifest_name == "my_cli.json"
      assert preview.manifest =~ ~s("version": "1.2.3")
      refute preview.clone_url =~ "real-token-not-printed"
      assert preview.clone_url =~ "x-access-token:****"
      assert preview.commit_message == "my_cli 1.2.3"
    end

    test "deploy-key auth builds an SSH clone URL", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      write_win_sidecar(input, String.duplicate("c", 64))

      config =
        build_config(
          scoop: [
            enabled: true,
            bucket: "owner/scoop-bucket",
            manifest_name: "my_cli",
            auth: :deploy_key
          ]
        )

      {:ok, preview} = Scoop.publish(config, input_dir: input, tag: "v1.2.3", dry_run: true)

      assert preview.auth == :deploy_key
      assert preview.clone_url == "git@github.com:owner/scoop-bucket.git"
    end

    test "returns pushed: false when the manifest is unchanged", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      write_win_sidecar(input, String.duplicate("a", 64))

      GitStub.setup(staged: false)
      System.put_env("SCOOP_BUCKET_TOKEN", "fake-token")

      {:ok, result} =
        Scoop.publish(build_config(),
          input_dir: input,
          tag: "v1.2.3",
          bucket_dir: Path.join(tmp, "bucket"),
          git: GitStub
        )

      assert result.pushed == false
      refute :push in GitStub.calls()
    end

    test "errors when scoop isn't enabled" do
      releases = [my_cli: [burrito: [targets: [windows_x86_64: [os: :windows, cpu: :x86_64]]]]]

      project = [
        app: :my_cli,
        version: "1.2.3",
        package: [licenses: ["MIT"]],
        releases: releases,
        tinfoil: [targets: [:windows_x86_64]]
      ]

      {:ok, config} = Config.load(project)
      assert {:error, :scoop_not_enabled} = Scoop.publish(config)
    end

    test "errors when SCOOP_BUCKET_TOKEN missing under :token auth", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      write_win_sidecar(input, String.duplicate("a", 64))
      System.delete_env("SCOOP_BUCKET_TOKEN")

      assert {:error, :missing_scoop_bucket_token} =
               Scoop.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 bucket_dir: Path.join(tmp, "bucket"),
                 git: GitStub
               )
    end

    test "errors when the sha256 sidecar is missing", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)

      System.put_env("SCOOP_BUCKET_TOKEN", "fake-token")

      assert {:error, {:missing_sha_sidecar, :windows_x86_64, _}} =
               Scoop.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 bucket_dir: Path.join(tmp, "bucket"),
                 git: GitStub
               )
    end
  end
end
