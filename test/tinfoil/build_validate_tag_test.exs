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

  describe "validate_tag_version/2 with an explicit tag" do
    test "the flag wins over GITHUB_REF_NAME" do
      System.put_env("GITHUB_REF_NAME", "main")
      assert :ok = Build.validate_tag_version("1.2.3", tag: "v1.2.3")
    end

    test "a mismatched flag is still an error even when the env agrees" do
      System.put_env("GITHUB_REF_NAME", "v1.2.3")
      assert {:error, msg} = Build.validate_tag_version("1.2.3", tag: "v9.9.9")
      assert msg =~ "tag v9.9.9 does not match mix.exs version 1.2.3"
    end

    test "a blank flag falls back to the env var" do
      System.put_env("GITHUB_REF_NAME", "v1.2.3")
      assert :ok = Build.validate_tag_version("1.2.3", tag: "")
    end

    test "a blank flag and a blank env var check nothing" do
      System.put_env("GITHUB_REF_NAME", "")
      assert :ok = Build.validate_tag_version("1.2.3", tag: "")
    end
  end

  # The bug in #116: a workflow_call run inherits the caller's ref, so the
  # version check compared mix.exs against a branch name and told the user
  # to bump mix.exs or re-tag, neither of which was the problem.
  describe "validate_tag_version/2 with a branch ref" do
    test "skips rather than failing when the ref is a branch name" do
      System.put_env("GITHUB_REF_NAME", "main")
      assert {:skip, msg} = Build.validate_tag_version("1.2.3")
      assert msg =~ ~s(GITHUB_REF_NAME is "main")
      assert msg =~ "workflow_call"
      refute msg =~ "does not match"
    end

    test "skips for a hyphenated branch name" do
      System.put_env("GITHUB_REF_NAME", "my-feature-branch")
      assert {:skip, _msg} = Build.validate_tag_version("1.2.3")
    end

    test "skips for a slash-prefixed branch that mentions a version" do
      System.put_env("GITHUB_REF_NAME", "release/1.2.3")
      assert {:skip, _msg} = Build.validate_tag_version("9.9.9")
    end

    test "a non-version explicit tag skips without blaming the env" do
      System.delete_env("GITHUB_REF_NAME")
      assert {:skip, msg} = Build.validate_tag_version("1.2.3", tag: "main")
      assert msg =~ "--tag \"main\""
      refute msg =~ "GITHUB_REF_NAME"
    end

    test "a version-shaped ref that disagrees is still a hard error" do
      System.put_env("GITHUB_REF_NAME", "v1.2.4")
      assert {:error, _msg} = Build.validate_tag_version("1.2.3")
    end
  end
end
