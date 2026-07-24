defmodule Tinfoil.NifCheckReleaseDepsTest do
  # Not async: `release_deps/1` flips `Mix.env/1` and clears Mix's dep
  # cache, both of which are global.
  use ExUnit.Case, async: false

  alias Tinfoil.NifCheck

  describe "compile_time_only/1" do
    test "collects deps declared runtime: false" do
      deps = [
        {:jason, "~> 1.4"},
        {:tinfoil, "~> 0.2", runtime: false},
        {:burrito, "~> 1.0"}
      ]

      assert NifCheck.compile_time_only(deps) == MapSet.new([:tinfoil])
    end

    test "handles every dep tuple shape" do
      deps = [
        # {name, opts}
        {:path_dep, path: "../x", runtime: false},
        # {name, req, opts}
        {:hex_dep, "~> 1.0", runtime: false},
        # {name, req} -- no opts, so runtime defaults to true
        {:plain, "~> 1.0"},
        # bare atom
        :bare
      ]

      assert NifCheck.compile_time_only(deps) == MapSet.new([:path_dep, :hex_dep])
    end

    test "runtime: true and unset are both kept" do
      deps = [{:a, "~> 1.0", runtime: true}, {:b, "~> 1.0"}]
      assert NifCheck.compile_time_only(deps) == MapSet.new([])
    end

    test "empty deps list yields an empty set" do
      assert NifCheck.compile_time_only([]) == MapSet.new([])
    end
  end

  describe "release_deps/1" do
    # These run against tinfoil's own project, which declares
    # `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}`. Credo
    # pulls in `file_system`, which carries a `c_src/` directory -- the
    # exact false positive reported in #104.
    test "excludes dev/test-only deps and their transitive deps" do
      names = NifCheck.release_deps(:prod) |> Enum.map(&elem(&1, 0))

      refute :credo in names
      refute :file_system in names
      refute :ex_doc in names
      refute :dialyxir in names
    end

    test "keeps deps that are in the prod build" do
      names = NifCheck.release_deps(:prod) |> Enum.map(&elem(&1, 0))

      assert :req in names
      assert :jason in names
    end

    test "no NIF warnings for tinfoil's own prod deps" do
      assert NifCheck.check(NifCheck.release_deps(:prod)) == []
    end

    test "scanning the unfiltered dev set still reports file_system" do
      # Guards the regression: if this ever stops warning, the test above
      # is passing for the wrong reason.
      names =
        Mix.Project.deps_paths()
        |> Map.to_list()
        |> NifCheck.check()
        |> Enum.map(& &1.name)

      assert :file_system in names
    end

    test "restores Mix.env afterwards" do
      before = Mix.env()
      NifCheck.release_deps(:prod)
      assert Mix.env() == before
    end

    test "is idempotent across repeated calls" do
      # Clearing and rebuilding the dep cache must not degrade on the
      # second pass.
      assert NifCheck.release_deps(:prod) == NifCheck.release_deps(:prod)
    end

    test "returns the current env's deps without swapping when env matches" do
      # The suite runs under :test, where `{:plug, "~> 1.0", only: :test}`
      # is present. It is absent from the :prod set asserted above.
      current = Mix.env()
      names = NifCheck.release_deps(current) |> Enum.map(&elem(&1, 0))

      assert :plug in names, "test-env deps should be present when asking for the current env"
      refute :plug in (NifCheck.release_deps(:prod) |> Enum.map(&elem(&1, 0)))
      assert Mix.env() == current
    end

    test "runtime: false deps are excluded even in their own env" do
      # credo is `only: [:dev, :test], runtime: false`, so it is filtered
      # out by the runtime check even when the env would allow it.
      names = NifCheck.release_deps(Mix.env()) |> Enum.map(&elem(&1, 0))
      refute :credo in names
    end

    test "results are sorted and shaped as {name, path} tuples" do
      deps = NifCheck.release_deps(:prod)

      assert deps == Enum.sort(deps)
      assert Enum.all?(deps, fn {name, path} -> is_atom(name) and is_binary(path) end)
    end
  end
end
