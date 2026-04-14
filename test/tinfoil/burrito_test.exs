defmodule Tinfoil.BurritoTest do
  use ExUnit.Case, async: true

  alias Tinfoil.Burrito

  describe "extract_targets/2" do
    test "pulls targets from the release whose key matches the app name" do
      project = [
        app: :my_cli,
        releases: [
          my_cli: [
            burrito: [
              targets: [
                macos: [os: :darwin, cpu: :x86_64],
                linux: [os: :linux, cpu: :x86_64]
              ]
            ]
          ]
        ]
      ]

      assert {:ok, targets} = Burrito.extract_targets(project, :my_cli)

      assert targets == %{
               macos: [os: :darwin, cpu: :x86_64],
               linux: [os: :linux, cpu: :x86_64]
             }
    end

    test "falls back to the single release when no key matches the app name" do
      project = [
        app: :my_cli,
        releases: [
          cli: [burrito: [targets: [linux: [os: :linux, cpu: :x86_64]]]]
        ]
      ]

      assert {:ok, %{linux: [os: :linux, cpu: :x86_64]}} =
               Burrito.extract_targets(project, :my_cli)
    end

    test "errors with the available names when multiple releases and no match" do
      project = [
        app: :my_cli,
        releases: [
          foo: [burrito: [targets: [l: [os: :linux, cpu: :x86_64]]]],
          bar: [burrito: [targets: [l: [os: :linux, cpu: :x86_64]]]]
        ]
      ]

      assert {:error, {:multiple_releases_no_match, [:foo, :bar], :my_cli}} =
               Burrito.extract_targets(project, :my_cli)
    end

    test "errors when :releases is missing" do
      assert {:error, :missing_releases} =
               Burrito.extract_targets([app: :my_cli], :my_cli)
    end

    test "errors when the release has no :burrito key" do
      project = [app: :my_cli, releases: [my_cli: [steps: [:assemble]]]]

      assert {:error, :missing_burrito_in_release} =
               Burrito.extract_targets(project, :my_cli)
    end

    test "errors when :burrito has no :targets list" do
      project = [app: :my_cli, releases: [my_cli: [burrito: []]]]

      assert {:error, :missing_burrito_targets} =
               Burrito.extract_targets(project, :my_cli)
    end

    test "errors on a target spec missing :os or :cpu" do
      project = [
        app: :my_cli,
        releases: [my_cli: [burrito: [targets: [weird: [os: :darwin]]]]]
      ]

      assert {:error, {:invalid_burrito_target, :weird}} =
               Burrito.extract_targets(project, :my_cli)
    end
  end

  describe "resolve/2" do
    test "matches a tinfoil target to the user's burrito name by os+cpu" do
      burrito = %{
        macos: [os: :darwin, cpu: :x86_64],
        macos_m1: [os: :darwin, cpu: :aarch64],
        linux: [os: :linux, cpu: :x86_64]
      }

      assert {:ok, :macos_m1} = Burrito.resolve(:darwin_arm64, burrito)
      assert {:ok, :macos} = Burrito.resolve(:darwin_x86_64, burrito)
      assert {:ok, :linux} = Burrito.resolve(:linux_x86_64, burrito)
    end

    test "errors when no burrito target has the right os+cpu" do
      burrito = %{linux: [os: :linux, cpu: :x86_64]}

      assert {:error, {:no_matching_burrito_target, :darwin_arm64, _}} =
               Burrito.resolve(:darwin_arm64, burrito)
    end
  end

  describe "resolve_all/2" do
    test "returns a map from every tinfoil target to its burrito name" do
      burrito = %{
        m: [os: :darwin, cpu: :x86_64],
        mm: [os: :darwin, cpu: :aarch64],
        l: [os: :linux, cpu: :x86_64]
      }

      assert {:ok, names} =
               Burrito.resolve_all(
                 [:darwin_x86_64, :darwin_arm64, :linux_x86_64],
                 burrito
               )

      assert names == %{darwin_x86_64: :m, darwin_arm64: :mm, linux_x86_64: :l}
    end

    test "halts and returns the first unresolved target" do
      burrito = %{l: [os: :linux, cpu: :x86_64]}

      assert {:error, {:no_matching_burrito_target, :darwin_arm64, _}} =
               Burrito.resolve_all([:linux_x86_64, :darwin_arm64], burrito)
    end
  end
end
