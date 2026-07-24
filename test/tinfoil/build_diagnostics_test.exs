defmodule Tinfoil.BuildDiagnosticsTest do
  # Not async: creates and removes a directory under the shared
  # Mix.Project.build_path().
  use ExUnit.Case, async: false

  alias Tinfoil.Build

  @binary "burrito_out/my_cli_linux_x86_64"

  defp rel_path(app), do: Path.join([Mix.Project.build_path(), "rel", to_string(app)])

  # Stand in for a release that assembled but was never wrapped. Uses a
  # name no real project would collide with, and removes it afterwards.
  defp with_assembled_release(app, fun) do
    path = rel_path(app)
    File.mkdir_p!(path)

    try do
      fun.()
    after
      File.rm_rf!(path)
    end
  end

  describe "missing_binary_message/3 when no release was assembled" do
    test "keeps the did-the-release-succeed framing" do
      app = :tinfoil_test_never_assembled
      refute File.dir?(rel_path(app))

      message = Build.missing_binary_message(@binary, app, :linux_x86_64)

      assert message =~ "no Burrito output at #{@binary}"
      assert message =~ "Did `mix release` succeed for BURRITO_TARGET=linux_x86_64?"
      refute message =~ "wrap step"
    end
  end

  describe "missing_binary_message/3 when a release was assembled" do
    test "diagnoses the missing wrap step instead of blaming the release" do
      app = :tinfoil_test_assembled

      with_assembled_release(app, fn ->
        message = Build.missing_binary_message(@binary, app, :linux_x86_64)

        # The actual diagnosis, not the misleading one.
        assert message =~ "an assembled release exists at"
        assert message =~ "`mix release` succeeded"
        assert message =~ "wrap step did not run"

        refute message =~ "Did `mix release` succeed"
      end)
    end

    test "explains why the BURRITO_TARGET gate reads nil" do
      app = :tinfoil_test_assembled

      with_assembled_release(app, fn ->
        message = Build.missing_binary_message(@binary, app, :linux_x86_64)

        assert message =~ "mix.exs is evaluated at Mix startup"
        assert message =~ "BURRITO_TARGET is always nil"
      end)
    end

    test "gives the argv workaround" do
      app = :tinfoil_test_assembled

      with_assembled_release(app, fn ->
        message = Build.missing_binary_message(@binary, app, :linux_x86_64)

        assert message =~ "System.argv"
        assert message =~ "tinfoil.build"
        assert message =~ "burrito_build?"
      end)
    end

    test "names the assembled release path so it can be verified" do
      app = :tinfoil_test_assembled

      with_assembled_release(app, fn ->
        message = Build.missing_binary_message(@binary, app, :linux_x86_64)

        assert message =~ rel_path(app)
      end)
    end
  end
end
