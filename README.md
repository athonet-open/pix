# PIX

[![.github/workflows/ci.yml](https://github.com/athonet-open/pix/actions/workflows/ci.yml/badge.svg)](https://github.com/athonet-open/pix/actions/workflows/ci.yml) [![Docs](https://img.shields.io/badge/docs-latest-green.svg)](https://athonet-open.github.io/pix)

BuildKit pipelines.

Documentation [website](https://athonet-open.github.io/pix).

## Introduction

Pix is a portable pipeline executor - a CI framework that enables you to define and execute pipelines that can run on any host with Docker support. Pipelines are defined as code and executed efficiently via Docker [BuildKit](https://github.com/moby/buildkit).

## Basic concepts

### The pipeline

The building blocks of a pipeline are:
- **stage**: The core execution unit where work is performed (e.g., running tests, building applications, deploying services). Each stage can be customized via **arguments**.
- **output**: Stages can produce tangible outputs (e.g., test coverage reports, documentation, build artifacts).
- **dependency**: Stages are interconnected via **dependencies** to create a structured execution graph.

Under the hood, a pipeline is an intelligent Docker multistage build, programmatically defined using Elixir code through the `Pix.Pipeline.SDK` module.

### The pipeline executor

Pix generates optimized multistage Docker build definitions and executes them via `docker buildx build`.
The execution follows Docker build semantics for parallelism, caching, and resource management.

### The Project

Your project's root directory can contain a `.pix.exs` file that declares available pipelines.
This configuration file specifies pipelines with their default arguments and targets.
Pipeline definitions can be imported either from a local `path` or a remote `git` repository.

More details in the `Pix.Project` module documentation.

### The Pipeline definition

A pipeline is a programmatic definition of a Docker multistage build.
It consists of targets (named Docker build stages) defined in `pipeline.exs` using the `Pix.Pipeline.SDK` module.

More details in the `Pix.Pipeline.SDK` module documentation and the [Pipeline Authoring Guide](guides/pipeline-authoring.md).

## Installation

### Prerequisites

Pix requires a `docker` engine installed and running on your host system.

### Installation options

#### Option 1: Native Installation (Requires Erlang/Elixir)

```bash
$ mix escript.install github athonet-open/pix ref vX.Y.Z
```

Requires Erlang/Elixir to be installed on the host.

#### Option 2: Wrapper Script

A self-managing shell script that automatically resolves the latest version, builds the Docker image from source, and keeps itself up to date.

```bash
$ curl -fsSL https://raw.githubusercontent.com/athonet-open/pix/main/bin/pix -o /usr/local/bin/pix && chmod +x /usr/local/bin/pix
```

Requirements: `bash`, `docker`, `git`, `curl`.

On first run, the script will:
1. Detect the latest release tag from GitHub
2. Build the Pix Docker image locally from source
3. Run the requested command

On subsequent runs, the cached image is reused. When a new version is released, the script
automatically updates itself and rebuilds the image.

The script handles Docker socket mounting, SSH agent forwarding (with macOS Docker Desktop support),
and mounts `~/.ssh`, `~/.gitconfig*`, and `~/.config/pix/settings.exs` if present.

### Shell completion

Shell completion scripts are available for the following shells:

- fish shell
  ```bash
  # install completion with
  pix completion_script fish > ~/.config/fish/completions/pix.fish
  ```

## Quick start

Let's explore Pix using its own project as an example:

1. The project configuration is in [.pix.exs](https://github.com/athonet-open/pix/blob/main/.pix.exs), defining the `pix` pipeline with default settings.
2. The [pipeline.exs](https://github.com/athonet-open/pix/blob/main/pipeline.exs) contains the actual pipeline definition.

Key commands:

```bash
$ pix run pix                   # Run the complete pipeline
$ pix ls --verbose pix          # List pipeline configuration
$ pix graph pix                 # Generate pipeline visualization
$ pix run --output pix          # Run pipeline and output artifacts
```

Access documentation at `.pipeline/output/doc/index.html` after running with output.

For detailed command information, use `pix help`.

## User settings

Customize Pix behavior through `~/.config/pix/settings.exs`.
See the `Pix.UserSettings` module documentation for configuration options.

## Security

- Only import remote pipelines from verified, trusted sources

## Current limitations

- Service containers are not currently supported (e.g., sidecar containers for integration testing)

Workaround: Use Docker Compose to define and manage test environments.
