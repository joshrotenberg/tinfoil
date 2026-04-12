defmodule Tinfoil.Build.ValidateTagTest do
  use ExUnit.Case, async: false

  alias Tinfoil.Build

  setup do
    original = System.get_env("GITHUB_REF_NAME")

    on_exit(fn ->
      if original,
        do: System.put_env("GITHUB_REF_NAME", original),
        else: System.delete_env("GITHUB_REF_NAME")
    end)
  end

  describe "validate_tag_version/1" do
    test "returns :ok when GITHUB_REF_NAME is not set" do
      System.delete_env("GITHUB_REF_NAME")
      assert :ok = Build.validate_tag_version("1.2.3")
    end

    test "returns :ok when tag matches version (with v prefix)" do
      System.put_env("GITHUB_REF_NAME", "v1.2.3")
      assert :ok = Build.validate_tag_version("1.2.3")
    end

    test "returns :ok when tag matches version (without v prefix)" do
      System.put_env("GITHUB_REF_NAME", "1.2.3")
      assert :ok = Build.validate_tag_version("1.2.3")
    end

    test "returns error when tag does not match version" do
      System.put_env("GITHUB_REF_NAME", "v1.2.3")
      assert {:error, msg} = Build.validate_tag_version("1.2.2")
      assert msg =~ "tag v1.2.3 does not match mix.exs version 1.2.2"
    end

    test "returns error for prerelease tag vs release version" do
      System.put_env("GITHUB_REF_NAME", "v1.2.3-rc.1")
      assert {:error, msg} = Build.validate_tag_version("1.2.3")
      assert msg =~ "tag v1.2.3-rc.1 does not match mix.exs version 1.2.3"
    end
  end
end
