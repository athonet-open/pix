defmodule Pix.Pipeline.Project do
  @moduledoc """
  Defines Pix pipeline projects.

  A Pix pipeline project is defined by calling `use Pix.Pipeline.Project` in a module placed in `pipeline.exs`:

  ```elixir
  defmodule MyApp.Pipeline do
    use Pix.Pipeline.Project
    import Pix.Pipeline.SDK

    @impl true
    def pipeline() do
      pipeline("myapp",
        description: "MyApp pipeline",
        dockerignore: [".git", "_build", "deps"]
      )
      |> stage("base", from: "alpine:3.18")
      |> run("apk add --no-cache git")
      |> stage("build", from: "elixir:1.15")
      |> arg("MIX_ENV", "prod")
      |> copy("mix.exs", ".")
      |> run("mix deps.get")
      |> copy("lib", "lib")
      |> run("mix compile")
      |> output("/app/_build")
    end

    @impl true
    def shell(pipeline, shell_stage, from_target) do
      from_target = if from_target == :default, do: "base", else: from_target

      pipeline
      |> stage(shell_stage, from: from_target)
      |> run("apk add --no-cache bash")
      |> cmd(["bash"])
    end
  end
  ```

  ## Pipeline Definition

  A pipeline project must implement the `c:pipeline/0` callback to define the pipeline stages and instructions.
  The pipeline is built using the `Pix.Pipeline.SDK` module which provides a fluent API for:

  - Creating pipeline stages
  - Adding Docker instructions (RUN, COPY, ARG etc)
  - Defining outputs
  - Setting build arguments
  - Configuring .dockerignore

  ## Shell Support

  Optionally, a pipeline can implement the `c:shell/3` callback to provide an interactive shell environment.
  The shell callback receives:

  - The pipeline definition
  - The shell stage name
  - The target stage to base the shell from (or :default)

  This enables debugging and interactive development within pipeline stages.

  ## Pipeline Stages

  Each stage in a pipeline:

  - Has a unique name
  - Can be marked as private
  - Can enable/disable caching
  - Can define outputs
  - Can have stage-specific build arguments

  ## Pipeline SDK

  The `Pix.Pipeline.SDK` module provides a complete API for building Dockerfiles programmatically:

  - Stage management (FROM)
  - File operations (COPY, ADD)
  - Command execution (RUN, CMD)
  - Environment setup (ENV, ARG)
  - Output artifacts
  - And more every other Docker instruction

  ## Pipeline COPY context

  When using the `Pix.Pipeline.SDK.copy/3` function, it's possible to specify a context directory to copy from.
  To copy files from the directory where the pipeline is defined (the directory where the `pipeline.exs` file is located),
  use `copy(src, dest, from: pipeline_ctx()`.


  See `Pix.Pipeline.SDK` for the complete API reference.
  """

  @type t() :: module()

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @callback pipeline() :: Pix.Pipeline.SDK.t()
  @callback shell(Pix.Pipeline.SDK.t(), shell_stage :: String.t(), from_target :: String.t() | :default) ::
              Pix.Pipeline.SDK.t()
  @optional_callbacks shell: 3
end
