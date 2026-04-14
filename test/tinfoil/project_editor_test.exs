defmodule Tinfoil.ProjectEditorTest do
  use ExUnit.Case, async: true

  alias Tinfoil.ProjectEditor

  @mix_new_source """
  defmodule MyCli.MixProject do
    use Mix.Project

    def project do
      [
        app: :my_cli,
        version: "0.1.0",
        elixir: "~> 1.15",
        start_permanent: Mix.env() == :prod,
        deps: deps()
      ]
    end

    def application do
      [
        extra_applications: [:logger]
      ]
    end

    defp deps do
      [
        # {:dep_from_hexpm, "~> 0.3.0"},
      ]
    end
  end
  """

  describe "insert_dep/2" do
    test "injects tinfoil as the first dep in a fresh mix new project" do
      {:ok, updated, :inserted} = ProjectEditor.insert_dep(@mix_new_source, "0.2")

      assert updated =~ ~s({:tinfoil, "~> 0.2", runtime: false})
      # Injected before the existing commented-out example dep
      assert String.contains?(
               updated,
               "{:tinfoil, \"~> 0.2\", runtime: false},\n      # {:dep_from_hexpm"
             )
    end

    test "preserves indentation used by the existing deps list" do
      {:ok, updated, :inserted} = ProjectEditor.insert_dep(@mix_new_source, "0.2")

      # The original deps list indents with 6 spaces (2 for defp, 4 for list entries).
      # Confirm our entry sits at the same indent.
      assert updated =~ ~r/\n\s{6}\{:tinfoil,/
    end

    test "is idempotent when tinfoil is already a dep" do
      already = """
      defp deps do
        [
          {:tinfoil, "~> 0.2", runtime: false}
        ]
      end
      """

      {:ok, same, :already_present} = ProjectEditor.insert_dep(already, "0.2")
      assert same == already
    end

    test "returns an error if the deps/0 anchor isn't there" do
      weird = """
      defmodule Weird do
        def deps_from_the_config, do: []
      end
      """

      assert {:error, :deps_anchor_not_found} = ProjectEditor.insert_dep(weird, "0.2")
    end
  end

  describe "insert_tinfoil_config/2" do
    test "injects a :tinfoil block after deps: deps() in project/0" do
      targets = [:darwin_arm64, :linux_x86_64]

      {:ok, updated, :inserted} =
        ProjectEditor.insert_tinfoil_config(@mix_new_source, targets)

      assert updated =~ "tinfoil: ["
      assert updated =~ "targets: [:darwin_arm64, :linux_x86_64]"
      # The original `deps: deps()` line must still be present
      assert updated =~ "deps: deps(),"
    end

    test "is idempotent when a :tinfoil config is already present" do
      already = """
      def project do
        [
          app: :my_cli,
          deps: deps(),
          tinfoil: [targets: [:darwin_arm64]]
        ]
      end
      """

      {:ok, same, :already_present} =
        ProjectEditor.insert_tinfoil_config(already, [:darwin_arm64])

      assert same == already
    end

    test "returns an error if the project/0 anchor isn't there" do
      weird = "def project, do: [app: :weird]"

      assert {:error, :project_anchor_not_found} =
               ProjectEditor.insert_tinfoil_config(weird, [:darwin_arm64])
    end

    test "handles an existing trailing comma on deps: deps()" do
      with_comma = """
      def project do
        [
          app: :my_cli,
          deps: deps(),
        ]
      end
      """

      {:ok, updated, :inserted} =
        ProjectEditor.insert_tinfoil_config(with_comma, [:darwin_arm64])

      assert updated =~ "tinfoil: ["
      # Should not produce a double comma like `deps: deps(),,`
      refute updated =~ ",,"
    end
  end

  describe "both edits against a full mix new file" do
    test "produces a valid mix.exs that Code.string_to_quoted can parse" do
      {:ok, with_dep, :inserted} = ProjectEditor.insert_dep(@mix_new_source, "0.2")

      {:ok, with_both, :inserted} =
        ProjectEditor.insert_tinfoil_config(with_dep, [:darwin_arm64, :linux_x86_64])

      assert {:ok, _ast} = Code.string_to_quoted(with_both)
    end
  end
end
