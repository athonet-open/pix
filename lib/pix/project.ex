defmodule Pix.Project do
  @moduledoc """
  Defines Pix projects.

  A Pix project is defined by calling `use Pix.Project` in a module placed in `.pix.exs`:

  ```elixir
  defmodule MyApp.Pix.Project do
    use Pix.Project

    @impl true
    def project() do
      %{
        pipelines: %{
          "elixir" => %{
            from: %{
              git: "git@github.com:user/group/repo.git",
              ref: "v1.0",
              sub_dir: "pipeline/elixir"
            },
            default_args: %{
              "ELIXIR_APP_NAME" => "myapp"
            },
            default_targets: [
              "elixir.format",
              "elixir.credo",
              "elixir.dialyzer",
              "elixir.test"
            ]
          },
          "deploy_aws" => %{
            from: %{
              path: "pipelines/deploy",
              sub_dir: "aws"
            },
            default_args: %{
              "AWS_REGION" => "eu-west-1"
            },
            default_targets: [
              "deploy.plan",
              "deploy.apply"
            ]
          }
        }
      }
    end
  end

  ## Project Configuration

  The project configuration returned by `c:project/0` must conform to a `t:Pix.Config.pix_exs/0` map.

  ### Pipeline Sources

  Pipeline sources can be defined in two ways:

  1. From a Git repository:

  ```elixir
  from: %{
    git: "git@github.com:user/group/repo.git",
    ref: "v1.0",                    # Git reference (branch, tag, commit)
    sub_dir: "pipeline/elixir"      # Optional subdirectory containing pipeline.exs
  }
  ```

  2. From a local path:

  ```elixir
  from: %{
    path: "pipelines/deploy",       # Local directory path
    sub_dir: "aws"                  # Optional subdirectory containing pipeline.exs
  }
  ```

  ### Pipeline Arguments

  Default arguments for pipelines can be specified:

  ```elixir
  default_args: %{
    "AWS_REGION" => "eu-west-1",
    "ANOTHER_ARG" => "value"
  }
  ```

  ### Built-in Variables

  The following built-in variables are automatically available in all pipelines both as environment variables and as build ARGS in the pipeline:

  - `PIX_PROJECT_NAME`: Name of the current Git project
  - `PIX_COMMIT_SHA`: Current Git commit SHA
  - `PIX_PIPELINE_TARGET`: Name of the current pipeline target being executed

  ### Pipeline Targets

  Default targets define which pipeline stages should be executed by default when runninng `pix run PIPELINE_NAME`:

  ```elixir
  default_targets: [
    "target1",
    "target2"
  ]
  ```
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @callback project() :: Pix.Config.pix_exs()
end
