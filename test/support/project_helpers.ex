defmodule Tinfoil.ProjectHelpers do
  @moduledoc false

  @doc """
  A minimal Burrito releases block with all four tinfoil targets using
  tinfoil's own atom names, so `burrito_name == tinfoil target atom` in
  default-case assertions.
  """
  def default_releases do
    [
      my_cli: [
        steps: [:assemble],
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  @doc """
  Build a mix project keyword list with the given `:tinfoil` options
  and sensible defaults for everything else.

  ## Options

    * `:releases` -- override the releases block (default: `default_releases/0`)
    * `:app` -- override the app name (default: `:my_cli`)
    * `:version` -- override the version (default: `"1.2.3"`)

  """
  def base_project(tinfoil_opts, opts \\ []) do
    [
      app: Keyword.get(opts, :app, :my_cli),
      version: Keyword.get(opts, :version, "1.2.3"),
      description: "A test CLI",
      homepage_url: "https://example.com/my_cli",
      package: [licenses: ["Apache-2.0"]],
      releases: Keyword.get(opts, :releases, default_releases()),
      tinfoil: tinfoil_opts
    ]
  end
end
