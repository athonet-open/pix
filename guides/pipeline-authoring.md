# Pipeline Authoring Guide

This guide walks you through writing a `pipeline.exs` file — the programmatic definition of a Pix pipeline.

## Overview

A pipeline is a Docker multistage build defined in Elixir using the `Pix.Pipeline.SDK`.
The pipeline file lives in `pipeline.exs` and defines exactly one module that `use`s `Pix.Pipeline.Project`.

```elixir
defmodule MyApp.Pipeline do
  use Pix.Pipeline.Project
  import Pix.Pipeline.SDK

  @impl true
  def pipeline do
    pipeline("myapp",
      description: "Build and test MyApp",
      dockerignore: [".git", "_build", "deps"]
    )
    |> stage("deps", from: "elixir:1.18", private: true)
    |> copy(["mix.exs", "mix.lock"], ".")
    |> run("mix deps.get")
    |> stage("test", from: "deps")
    |> copy(["config", "lib", "test"], ".")
    |> run("mix test --cover")
    |> output("/app/_build/test/cover")
  end
end
```

## Key concepts

### Stages

Each `stage/3` call starts a new `FROM … AS <name>` block. Stages support three flags:

| Option      | Default | Purpose |
|-------------|---------|---------|
| `:from`     | `"scratch"` | Base image or another stage name |
| `:private`  | `false` | When `true`, the stage is hidden from `pix run` / `pix ls` |
| `:cache`    | `true`  | When `false`, the stage is always rebuilt from scratch |

Private stages are useful for shared base layers that should not be run independently.

### Instructions

The SDK exposes one function per Dockerfile command:
`run/3`, `copy/4`, `add/4`, `env/2`, `arg/3`, `global_arg/3`, `workdir/2`, `cmd/2`,
`entrypoint/2`, `user/2`, `expose/2`, `volume/2`, `label/2`, `shell/2`,
`healthcheck/3`, `stopsignal/2`.

Refer to `Pix.Pipeline.SDK` for full API documentation.

### Outputs

Declare stage output artifacts with `output/2`:

```elixir
|> stage("docs", from: "build")
|> run("mix docs")
|> output("/app/doc")
```

Running `pix run --output PIPELINE` copies declared outputs to `.pipeline/output/` on the host.

### Build arguments

Use `arg/3` for stage-scoped arguments and `global_arg/3` for arguments available to all stages:

```elixir
pipeline("myapp")
|> global_arg("ELIXIR_VERSION", "1.17")
|> stage("build", from: "elixir:${ELIXIR_VERSION}")
|> arg("MIX_ENV", "prod")
```

Arguments can be overridden at runtime with `pix run --arg KEY=value`.

To require an argument without a default value, combine `arg/3` with
`Pix.Pipeline.SDK.Extra.assert_required_arg/2`:

```elixir
import Pix.Pipeline.SDK.Extra

|> arg("DEPLOY_TARGET")
|> assert_required_arg("DEPLOY_TARGET")
```

### Pipeline context (`pipeline_ctx`)

When the pipeline itself ships supporting files (scripts, configuration), copy them
using the pipeline context:

```elixir
|> copy("setup.sh", "/opt/", from: pipeline_ctx())
```

This copies from the directory containing `pipeline.exs`, not from the project root.

### Here-documents

Use the `~h` sigil for multi-line shell scripts that need `if`/`for` or quotes:

```elixir
|> run(~h"""
  if [ "$ENV" = "prod" ]; then
    mix release
  fi
""")
```

### Dockerignore

Pass `:dockerignore` to `pipeline/2` to exclude files from the Docker build context:

```elixir
pipeline("myapp", dockerignore: [".git", "_build", "deps", "node_modules"])
```

### Parser directives

Pass `:directives` to `pipeline/2` for Dockerfile parser directives (e.g. custom syntax):

```elixir
pipeline("myapp", directives: ["syntax=docker/dockerfile:1.4"])
```

## Shell support

Optionally implement the `c:Pix.Pipeline.Project.shell/3` callback to enable
`pix shell PIPELINE`:

```elixir
@impl true
def shell(pipeline, shell_stage, from_target) do
  from_target = if from_target == :default, do: "deps", else: from_target

  pipeline
  |> stage(shell_stage, from: from_target)
  |> run("apk add --no-cache bash")
  |> cmd(["bash"])
end
```

The `from_target` is `:default` unless the user passes `--target`.

## Built-in variables

Pix automatically injects several variables into every pipeline. See the
"Built-in Variables" section in `Pix.Project` for the full list.

## Project integration

The project's `.pix.exs` file (see `Pix.Project`) references your pipeline and
supplies default arguments and targets:

```elixir
defmodule MyApp.Pix.Project do
  use Pix.Project

  @impl true
  def project do
    %{
      pipelines: %{
        "myapp" => %{
          from: %{path: "."},
          default_args: %{"MIX_ENV" => "test"},
          default_targets: ["test"]
        }
      }
    }
  end
end
```

## Visualising the pipeline

Use `pix graph PIPELINE` to render the stage dependency graph, or
`pix graph --format dot PIPELINE` to export a Graphviz DOT file.
