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

  describe "insert_burrito_dep/1" do
    test "adds a burrito entry to deps/0" do
      {:ok, updated, :inserted} = ProjectEditor.insert_burrito_dep(@mix_new_source)
      assert updated =~ ~s({:burrito, "~> 1.0"})
    end

    test "is idempotent" do
      already = """
      defp deps do
        [
          {:burrito, "~> 1.0"}
        ]
      end
      """

      {:ok, same, :already_present} = ProjectEditor.insert_burrito_dep(already)
      assert same == already
    end
  end

  describe "insert_releases_entry/1" do
    test "inserts releases: releases() after deps: deps()" do
      {:ok, updated, :inserted} = ProjectEditor.insert_releases_entry(@mix_new_source)
      assert updated =~ "releases: releases()"
      assert updated =~ "deps: deps(),"
      refute updated =~ ",,"
    end

    test "is idempotent" do
      already = """
      def project do
        [
          deps: deps(),
          releases: releases()
        ]
      end
      """

      {:ok, same, :already_present} = ProjectEditor.insert_releases_entry(already)
      assert same == already
    end
  end

  describe "insert_releases_block/3" do
    test "appends a defp releases function before the module end" do
      {:ok, updated, :inserted} =
        ProjectEditor.insert_releases_block(@mix_new_source, :my_cli, [
          :darwin_arm64,
          :linux_x86_64
        ])

      assert updated =~ "defp releases do"
      assert updated =~ "my_cli: ["
      assert updated =~ "steps: [:assemble, &Burrito.wrap/1]"
      assert updated =~ "darwin_arm64: [os: :darwin, cpu: :aarch64]"
      assert updated =~ "linux_x86_64: [os: :linux, cpu: :x86_64]"

      # The module end must still be there and close everything cleanly.
      assert {:ok, _ast} = Code.string_to_quoted(updated)
    end

    test "is idempotent" do
      already = """
      defmodule MyCli.MixProject do
        use Mix.Project
        defp releases do
          []
        end
      end
      """

      {:ok, same, :already_present} =
        ProjectEditor.insert_releases_block(already, :my_cli, [:darwin_arm64])

      assert same == already
    end
  end

  describe "insert_application_mod/2" do
    test "adds mod: {App.Application, []} after extra_applications" do
      {:ok, updated, :inserted} =
        ProjectEditor.insert_application_mod(@mix_new_source, "MyCli")

      assert updated =~ "extra_applications: [:logger],"
      assert updated =~ "mod: {MyCli.Application, []}"
      refute updated =~ ",,"
    end

    test "is idempotent when mod: is already present" do
      already = """
      def application do
        [
          extra_applications: [:logger],
          mod: {MyCli.Application, []}
        ]
      end
      """

      {:ok, same, :already_present} =
        ProjectEditor.insert_application_mod(already, "MyCli")

      assert same == already
    end
  end

  describe "full --install pipeline" do
    test "applying every splicer produces a parseable mix.exs" do
      targets = [:darwin_arm64, :linux_x86_64]

      {:ok, s1, :inserted} = ProjectEditor.insert_tinfoil_dep(@mix_new_source, "0.2")
      {:ok, s2, :inserted} = ProjectEditor.insert_burrito_dep(s1)
      {:ok, s3, :inserted} = ProjectEditor.insert_tinfoil_config(s2, targets)
      {:ok, s4, :inserted} = ProjectEditor.insert_releases_entry(s3)
      {:ok, s5, :inserted} = ProjectEditor.insert_releases_block(s4, :my_cli, targets)
      {:ok, final, :inserted} = ProjectEditor.insert_application_mod(s5, "MyCli")

      assert {:ok, _ast} = Code.string_to_quoted(final)

      assert final =~ ~s({:tinfoil, "~> 0.2", runtime: false})
      assert final =~ ~s({:burrito, "~> 1.0"})
      assert final =~ "releases: releases()"
      assert final =~ "defp releases do"
      assert final =~ "mod: {MyCli.Application, []}"
      assert final =~ "tinfoil: ["
    end

    test "running the pipeline twice is a full no-op" do
      targets = [:darwin_arm64]

      {:ok, s1, _} = ProjectEditor.insert_tinfoil_dep(@mix_new_source, "0.2")
      {:ok, s2, _} = ProjectEditor.insert_burrito_dep(s1)
      {:ok, s3, _} = ProjectEditor.insert_tinfoil_config(s2, targets)
      {:ok, s4, _} = ProjectEditor.insert_releases_entry(s3)
      {:ok, s5, _} = ProjectEditor.insert_releases_block(s4, :my_cli, targets)
      {:ok, first_pass, _} = ProjectEditor.insert_application_mod(s5, "MyCli")

      # Second pass: every splicer should short-circuit as :already_present
      assert {:ok, ^first_pass, :already_present} =
               ProjectEditor.insert_tinfoil_dep(first_pass, "0.2")

      assert {:ok, ^first_pass, :already_present} = ProjectEditor.insert_burrito_dep(first_pass)

      assert {:ok, ^first_pass, :already_present} =
               ProjectEditor.insert_tinfoil_config(first_pass, targets)

      assert {:ok, ^first_pass, :already_present} =
               ProjectEditor.insert_releases_entry(first_pass)

      assert {:ok, ^first_pass, :already_present} =
               ProjectEditor.insert_releases_block(first_pass, :my_cli, targets)

      assert {:ok, ^first_pass, :already_present} =
               ProjectEditor.insert_application_mod(first_pass, "MyCli")
    end
  end
end
