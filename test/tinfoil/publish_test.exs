defmodule Tinfoil.PublishTest do
  use ExUnit.Case, async: false

  alias Tinfoil.{Config, Publish}

  defp build_config do
    project = [
      app: :my_cli,
      version: "1.2.3",
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
      tinfoil: [targets: [:darwin_arm64, :linux_x86_64]]
    ]

    {:ok, config} = Config.load(project)
    %{config | github: %{config.github | repo: "owner/my_cli"}}
  end

  # A Plug that stands in for api.github.com + uploads.github.com.
  # Records every received request for assertions.
  defp github_stub(test_pid) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.method, conn.request_path, conn.query_string, body, conn.req_headers}
      )

      cond do
        conn.method == "POST" and conn.request_path == "/repos/owner/my_cli/releases" ->
          release = %{
            "id" => 42,
            "html_url" => "https://github.com/owner/my_cli/releases/tag/v1.2.3",
            "upload_url" =>
              "https://test.invalid/repos/owner/my_cli/releases/42/assets{?name,label}"
          }

          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(201, Jason.encode!(release))

        conn.method == "POST" and
            String.starts_with?(conn.request_path, "/repos/owner/my_cli/releases/42/assets") ->
          Plug.Conn.resp(conn, 201, Jason.encode!(%{"id" => 1, "name" => "ok"}))

        true ->
          Plug.Conn.resp(conn, 404, "not found")
      end
    end
  end

  defp stub_req(test_pid) do
    Req.new(
      base_url: "https://test.invalid",
      plug: github_stub(test_pid),
      headers: [
        {"accept", "application/vnd.github+json"},
        {"authorization", "Bearer fake-token"}
      ]
    )
  end

  # Plug that emulates GitHub's "release already exists" state. The first
  # POST to /releases returns 422 with the real error shape; a GET by tag
  # returns the existing release; a DELETE on the existing release is a
  # no-op; a second POST after delete returns 201 (handled via the
  # :release_deleted process dict flag — Req's plug option runs in-process,
  # so self() / Process.put stay inside the test).
  defp conflicting_stub(test_pid) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.method, conn.request_path, conn.query_string, body}
      )

      dispatch_conflicting(conn.method, conn.request_path, conn)
    end
  end

  defp dispatch_conflicting("POST", "/repos/owner/my_cli/releases", conn) do
    if Process.get(:release_deleted, false) do
      respond_json(conn, 201, %{
        "id" => 99,
        "html_url" => "https://github.com/owner/my_cli/releases/tag/v1.2.3",
        "upload_url" => "https://test.invalid/repos/owner/my_cli/releases/99/assets{?name,label}"
      })
    else
      respond_json(conn, 422, %{
        "message" => "Validation Failed",
        "errors" => [
          %{"resource" => "Release", "code" => "already_exists", "field" => "tag_name"}
        ]
      })
    end
  end

  defp dispatch_conflicting("GET", "/repos/owner/my_cli/releases/tags/v1.2.3", conn) do
    respond_json(conn, 200, %{"id" => 7, "tag_name" => "v1.2.3"})
  end

  defp dispatch_conflicting("DELETE", "/repos/owner/my_cli/releases/7", conn) do
    Process.put(:release_deleted, true)
    Plug.Conn.resp(conn, 204, "")
  end

  defp dispatch_conflicting("POST", "/repos/owner/my_cli/releases/99/assets", conn) do
    respond_json(conn, 201, %{"id" => 1, "name" => "ok"})
  end

  defp dispatch_conflicting(_method, _path, conn) do
    Plug.Conn.resp(conn, 404, "not found")
  end

  defp respond_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  defp conflicting_req(test_pid) do
    Req.new(
      base_url: "https://test.invalid",
      plug: conflicting_stub(test_pid),
      headers: [{"authorization", "Bearer fake-token"}]
    )
  end

  describe "publish/2 happy path" do
    @tag :tmp_dir
    test "creates a release and uploads every archive + checksum", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)

      File.write!(Path.join(input, "my_cli-1.2.3-aarch64-apple-darwin.tar.gz"), "arm64-bytes")

      File.write!(
        Path.join(input, "my_cli-1.2.3-aarch64-apple-darwin.tar.gz.sha256"),
        "aaa  my_cli-1.2.3-aarch64-apple-darwin.tar.gz\n"
      )

      File.write!(
        Path.join(input, "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz"),
        "linux-bytes"
      )

      File.write!(
        Path.join(input, "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz.sha256"),
        "bbb  my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz\n"
      )

      config = build_config()

      assert {:ok, result} =
               Publish.publish(config,
                 input_dir: input,
                 tag: "v1.2.3",
                 req: stub_req(self())
               )

      assert result.release_id == 42
      assert result.html_url =~ "owner/my_cli/releases"

      assert Enum.sort(result.uploaded) == [
               "checksums-sha256.txt",
               "my_cli-1.2.3-aarch64-apple-darwin.tar.gz",
               "my_cli-1.2.3-x86_64-unknown-linux-musl.tar.gz"
             ]

      # Combined checksums file was written before upload
      assert File.exists?(Path.join(input, "checksums-sha256.txt"))

      assert File.read!(Path.join(input, "checksums-sha256.txt")) =~
               "aaa  my_cli-1.2.3-aarch64-apple-darwin.tar.gz"

      # Release body was sent as JSON with the right fields
      assert_receive {:request, "POST", "/repos/owner/my_cli/releases", _qs, body, _headers}
      decoded = Jason.decode!(body)
      assert decoded["tag_name"] == "v1.2.3"
      assert decoded["generate_release_notes"] == true
      assert decoded["prerelease"] == false
      assert decoded["draft"] == false
    end

    @tag :tmp_dir
    test "auto-detects prerelease tags like v1.0.0-rc.1", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)
      File.write!(Path.join(input, "x.tar.gz"), "x")
      File.write!(Path.join(input, "x.tar.gz.sha256"), "xxx  x.tar.gz\n")

      {:ok, _} =
        Publish.publish(build_config(),
          input_dir: input,
          tag: "v1.0.0-rc.1",
          req: stub_req(self())
        )

      assert_receive {:request, "POST", "/repos/owner/my_cli/releases", _, body, _}
      assert Jason.decode!(body)["prerelease"] == true
    end
  end

  describe "publish/2 error paths" do
    test "errors when :repo is unresolved in config" do
      config = build_config()
      config = %{config | github: %{config.github | repo: nil}}

      assert {:error, msg} =
               Publish.publish(config, tag: "v1.2.3", req: stub_req(self()))

      assert msg =~ "repo"
    end

    @tag :tmp_dir
    test "errors when the input dir does not exist", %{tmp_dir: tmp} do
      assert {:error, {:missing_input_dir, _}} =
               Publish.publish(build_config(),
                 input_dir: Path.join(tmp, "nope"),
                 tag: "v1.2.3",
                 req: stub_req(self())
               )
    end

    test "errors when no tag is provided and GITHUB_REF_NAME is unset" do
      System.delete_env("GITHUB_REF_NAME")

      assert {:error, :missing_tag} =
               Publish.publish(build_config(), req: stub_req(self()))
    end
  end

  describe "publish/2 existing release handling" do
    setup do
      Process.delete(:release_deleted)
      :ok
    end

    @tag :tmp_dir
    test "returns :release_already_exists_no_replace when a release exists and replace is false",
         %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)
      File.write!(Path.join(input, "x.tar.gz"), "x")
      File.write!(Path.join(input, "x.tar.gz.sha256"), "xxx  x.tar.gz\n")

      assert {:error, :release_already_exists_no_replace} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 req: conflicting_req(self())
               )

      # Verify we did attempt the POST but never the GET/DELETE
      assert_receive {:request, "POST", "/repos/owner/my_cli/releases", _, _}
      refute_receive {:request, "GET", _, _, _}, 100
      refute_receive {:request, "DELETE", _, _, _}, 100
    end

    @tag :tmp_dir
    test "with replace: true finds, deletes, and recreates the release", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)
      File.write!(Path.join(input, "y.tar.gz"), "y")
      File.write!(Path.join(input, "y.tar.gz.sha256"), "yyy  y.tar.gz\n")

      assert {:ok, result} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 replace: true,
                 req: conflicting_req(self())
               )

      # Second POST succeeded and we got the post-delete release id back
      assert result.release_id == 99

      # Verify the full GET → DELETE → POST sequence happened
      assert_receive {:request, "POST", "/repos/owner/my_cli/releases", _, _}
      assert_receive {:request, "GET", "/repos/owner/my_cli/releases/tags/v1.2.3", _, _}
      assert_receive {:request, "DELETE", "/repos/owner/my_cli/releases/7", _, _}
      assert_receive {:request, "POST", "/repos/owner/my_cli/releases", _, _}
    end

    @tag :tmp_dir
    test "non-422 create errors are propagated regardless of replace flag", %{tmp_dir: tmp} do
      input = Path.join(tmp, "artifacts")
      File.mkdir_p!(input)
      File.write!(Path.join(input, "z.tar.gz"), "z")
      File.write!(Path.join(input, "z.tar.gz.sha256"), "zzz  z.tar.gz\n")

      # This stub returns 500 for every POST to /releases — replace should
      # not kick in because the error isn't "already_exists"
      internal_error_req =
        Req.new(
          base_url: "https://test.invalid",
          plug: fn conn ->
            if conn.method == "POST" and conn.request_path == "/repos/owner/my_cli/releases" do
              Plug.Conn.resp(conn, 500, "boom")
            else
              Plug.Conn.resp(conn, 404, "not found")
            end
          end,
          headers: [{"authorization", "Bearer fake-token"}]
        )

      assert {:error, {:create_release_failed, 500, _}} =
               Publish.publish(build_config(),
                 input_dir: input,
                 tag: "v1.2.3",
                 replace: true,
                 req: internal_error_req
               )
    end
  end

  describe "prerelease?/1" do
    test "matches common prerelease tags" do
      assert Publish.prerelease?("v1.0.0-rc.1")
      assert Publish.prerelease?("v0.5-beta")
      assert Publish.prerelease?("1.2.3-alpha")
    end

    test "does not match stable tags" do
      refute Publish.prerelease?("v1.0.0")
      refute Publish.prerelease?("1.2.3")
    end
  end
end
