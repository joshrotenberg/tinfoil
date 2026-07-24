defmodule Tinfoil.PublishAttachTest do
  use ExUnit.Case, async: false

  alias Tinfoil.{Config, Publish}

  @tag_name "v1.2.3"
  @release_url "https://github.com/owner/my_cli/releases/tag/v1.2.3"

  defp build_config do
    project = [
      app: :my_cli,
      version: "1.2.3",
      package: [licenses: ["MIT"]],
      releases: [
        my_cli: [
          burrito: [targets: [linux_x86_64: [os: :linux, cpu: :x86_64]]]
        ]
      ],
      tinfoil: [targets: [:linux_x86_64]]
    ]

    {:ok, config} = Config.load(project)
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  defp artifacts(tmp) do
    input = Path.join(tmp, "artifacts")
    File.mkdir_p!(input)

    File.write!(Path.join(input, "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz"), "bytes")

    File.write!(
      Path.join(input, "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz.sha256"),
      "aaa  my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz\n"
    )

    input
  end

  # Stands in for a repo where release-please already created the release:
  # GET by tag succeeds, and the release carries a curated body that must
  # survive untouched.
  defp existing_release_stub(test_pid, opts \\ []) do
    found? = Keyword.get(opts, :found, true)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn.method, conn.request_path, body})

      cond do
        conn.method == "GET" and
            conn.request_path == "/repos/owner/my_cli/releases/tags/#{@tag_name}" ->
          if found? do
            respond_json(conn, 200, %{
              "id" => 7,
              "tag_name" => @tag_name,
              "html_url" => @release_url,
              "body" => "## 1.2.3\n\n* curated changelog from release-please",
              "prerelease" => false,
              "draft" => false,
              "upload_url" =>
                "https://test.invalid/repos/owner/my_cli/releases/7/assets{?name,label}"
            })
          else
            respond_json(conn, 404, %{"message" => "Not Found"})
          end

        conn.method == "POST" and
            String.starts_with?(conn.request_path, "/repos/owner/my_cli/releases/7/assets") ->
          respond_json(conn, 201, %{"id" => 1, "name" => "ok"})

        true ->
          respond_json(conn, 500, %{"message" => "unexpected request"})
      end
    end
  end

  defp respond_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp stub_req(plug) do
    Req.new(
      base_url: "https://test.invalid",
      plug: plug,
      headers: [{"authorization", "Bearer fake-token"}]
    )
  end

  defp received_requests do
    receive do
      {:request, method, path, body} -> [{method, path, body} | received_requests()]
    after
      0 -> []
    end
  end

  describe "attach mode" do
    @tag :tmp_dir
    test "uploads to the existing release without creating one", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:ok, result} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 req: stub_req(existing_release_stub(self()))
               )

      assert result.mode == :attach
      assert result.release_id == 7
      assert result.html_url == @release_url

      assert Enum.sort(result.uploaded) == [
               "checksums-sha256.txt",
               "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz"
             ]
    end

    @tag :tmp_dir
    test "never creates, deletes, or edits the release", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:ok, _} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 req: stub_req(existing_release_stub(self()))
               )

      requests = received_requests()

      # The one and only non-upload call is the lookup by tag.
      refute Enum.any?(requests, fn {method, path, _} ->
               method == "POST" and path == "/repos/owner/my_cli/releases"
             end)

      refute Enum.any?(requests, fn {method, _, _} -> method == "DELETE" end)
      refute Enum.any?(requests, fn {method, _, _} -> method in ["PATCH", "PUT"] end)

      assert Enum.any?(requests, fn {method, path, _} ->
               method == "GET" and path == "/repos/owner/my_cli/releases/tags/#{@tag_name}"
             end)
    end

    @tag :tmp_dir
    test "errors when no release exists for the tag", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:error, :release_not_found_for_attach} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 req: stub_req(existing_release_stub(self(), found: false))
               )

      # Nothing was uploaded after the failed lookup.
      refute Enum.any?(received_requests(), fn {method, _, _} -> method == "POST" end)
    end
  end

  describe "attach and replace are mutually exclusive" do
    @tag :tmp_dir
    test "rejects the combination before any request", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:error, :attach_and_replace} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 replace: true,
                 req: stub_req(existing_release_stub(self()))
               )

      assert received_requests() == []
    end

    @tag :tmp_dir
    test "rejects the combination in dry-run too", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:error, :attach_and_replace} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 replace: true,
                 dry_run: true
               )
    end
  end

  describe "mode reporting" do
    @tag :tmp_dir
    test "dry-run reports attach mode and leaves release fields alone", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:ok, preview} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 attach: true,
                 dry_run: true
               )

      assert preview.mode == :attach
      assert preview.attach == true
      assert preview.replace == false
    end

    @tag :tmp_dir
    test "dry-run defaults to create mode", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:ok, preview} =
               Publish.publish(build_config(), input_dir: input, tag: @tag_name, dry_run: true)

      assert preview.mode == :create
      assert preview.attach == false
      assert preview.replace == false
    end

    @tag :tmp_dir
    test "dry-run reports replace mode", %{tmp_dir: tmp} do
      input = artifacts(tmp)

      assert {:ok, preview} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: @tag_name,
                 replace: true,
                 dry_run: true
               )

      assert preview.mode == :replace
      assert preview.replace == true
      assert preview.attach == false
    end
  end
end
