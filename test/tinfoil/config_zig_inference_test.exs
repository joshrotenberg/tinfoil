defmodule Tinfoil.ConfigZigInferenceTest do
  # Not async: these tests define and purge a top-level `Burrito` module,
  # which is global to the VM. ExUnit runs every async module to
  # completion before any sync one starts, so no async test can observe
  # the stub.
  use ExUnit.Case, async: false

  alias Tinfoil.Config

  import Tinfoil.ProjectHelpers

  # Deliberately not a plausible Zig version. If inference silently falls
  # back, the assertion fails instead of accidentally matching whatever
  # @fallback_zig_version happens to be today. Pinning the expected value
  # to a real version is how this bug survived: the fallback and the
  # correct answer were the same string.
  @stub_zig "9.9.9"

  defp define_burrito_stub do
    defmodule Elixir.Burrito do
      def get_versions, do: %{zig: Version.parse!("9.9.9")}
    end

    on_exit(fn ->
      :code.purge(Elixir.Burrito)
      :code.delete(Elixir.Burrito)
    end)
  end

  defp load_config do
    {:ok, config} = Config.load(base_project(targets: [:darwin_arm64, :linux_x86_64]))
    config
  end

  describe "zig_version inference" do
    test "reads the real Burrito module rather than falling back" do
      define_burrito_stub()

      assert load_config().ci.zig_version == @stub_zig
    end

    test "the bare name Burrito resolves to Tinfoil.Burrito inside Config" do
      # This is the trap. Tinfoil.Config aliases Tinfoil.Burrito, so an
      # unqualified `Burrito` there is the tinfoil module, which loads
      # fine and has no get_versions/0 -- making the guard silently false
      # forever. The fix is the `Elixir.` prefix.
      define_burrito_stub()

      refute function_exported?(Tinfoil.Burrito, :get_versions, 0)
      assert function_exported?(Elixir.Burrito, :get_versions, 0)

      # Both modules exist and only one answers; inference must pick that one.
      assert load_config().ci.zig_version == @stub_zig
    end

    test "an explicit ci.zig_version still wins over detection" do
      define_burrito_stub()

      {:ok, config} =
        Config.load(
          base_project(targets: [:darwin_arm64, :linux_x86_64], ci: [zig_version: "0.13.0"])
        )

      assert config.ci.zig_version == "0.13.0"
    end

    test "falls back when no Burrito module is loaded" do
      refute Code.ensure_loaded?(Elixir.Burrito),
             "a leaked Burrito stub would make this test meaningless"

      # tinfoil has no burrito dep, so this exercises the real fallback.
      assert load_config().ci.zig_version =~ ~r/^\d+\.\d+\.\d+$/
    end
  end
end
