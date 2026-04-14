defmodule Tinfoil.NifCheckTest do
  use ExUnit.Case, async: true

  alias Tinfoil.NifCheck

  @moduletag :tmp_dir

  defp write_dep(tmp, name, files) do
    path = Path.join(tmp, to_string(name))
    File.mkdir_p!(path)

    Enum.each(files, fn {rel, contents} ->
      full = Path.join(path, rel)
      File.mkdir_p!(Path.dirname(full))

      case contents do
        :dir -> File.mkdir_p!(full)
        str when is_binary(str) -> File.write!(full, str)
      end
    end)

    {name, path}
  end

  test "empty when nothing looks like a NIF", %{tmp_dir: tmp} do
    pure = write_dep(tmp, :jason, [{"mix.exs", "defmodule Jason.MixProject do\nend"}])
    assert NifCheck.check([pure]) == []
  end

  test "detects Rustler", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :strsim, [
        {"mix.exs", ~s|{:rustler, "~> 0.30"}|}
      ])

    assert [%{name: :strsim, reasons: [:rustler]}] = NifCheck.check([dep])
  end

  test "prefers rustler_precompiled over plain rustler", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :tokenizers, [
        {"mix.exs", ~s|{:rustler_precompiled, "~> 0.7"}, {:rustler, ">= 0.0.0", optional: true}|}
      ])

    assert [%{reasons: [:rustler_precompiled]}] = NifCheck.check([dep])
  end

  test "detects elixir_make via compilers + Makefile", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :bcrypt_elixir, [
        {"mix.exs", "compilers: [:make, :elixir]"},
        {"Makefile", "all:\n\ttrue"}
      ])

    assert [%{reasons: [:elixir_make]}] = NifCheck.check([dep])
  end

  test "detects elixir_make via direct dep declaration", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :fast_yaml, [
        {"mix.exs", ~s|{:elixir_make, "~> 0.6", runtime: false}|}
      ])

    assert [%{reasons: [:elixir_make]}] = NifCheck.check([dep])
  end

  test "detects c_src/ directory", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :some_c_nif, [
        {"mix.exs", "defmodule SomeCNif.MixProject do\nend"},
        {"c_src", :dir}
      ])

    assert [%{reasons: [:c_sources]}] = NifCheck.check([dep])
  end

  test "multiple signals collapse into ordered reason list", %{tmp_dir: tmp} do
    dep =
      write_dep(tmp, :complicated, [
        {"mix.exs", ~s|{:rustler, "~> 0.30"}, {:elixir_make, "~> 0.6"}|},
        {"c_src", :dir}
      ])

    assert [%{reasons: [:rustler, :elixir_make, :c_sources]}] = NifCheck.check([dep])
  end

  test "missing mix.exs is tolerated", %{tmp_dir: tmp} do
    dep = write_dep(tmp, :broken, [])
    assert NifCheck.check([dep]) == []
  end

  test "describe/1 returns non-empty strings for every reason" do
    for r <- [:rustler, :rustler_precompiled, :elixir_make, :c_sources] do
      assert is_binary(NifCheck.describe(r))
      assert byte_size(NifCheck.describe(r)) > 0
    end
  end
end
