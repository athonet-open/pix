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

Under the hood, a pipeline is an intelligent Docker multistage build, programmatically defined using Elixir code through the `Pix.Pipeline.SDK`.

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
It consists of targets (named Docker build stages) defined in `pipeline.exs` using the `Pix.Pipeline.SDK`.

More details in the `Pix.Pipeline.SDK` module documentation.

## Installation

### Prerequisites

Pix requires a `docker` engine installed and running on your host system.

### Installation options

#### Option 1: Native Installation (Requires Erlang/Elixir)

```bash
$ mix escript.install github athonet-open/pix ref vX.Y.Z
```

#### Option 2: Docker Installation

```bash
$ docker run --rm -it \
  --volume $PWD:/$PWD --workdir /$PWD \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume $SSH_AUTH_SOCK:$SSH_AUTH_SOCK \
  --env SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
  ghcr.io/athonet-open/pix:X.Y.Z "$@"
```

Important considerations:
- Docker engine access is required via either Docker Socket Mounting (DooD) or Docker-in-Docker (dind)
- For SSH access, forward the SSH agent socket to the Pix container
- For macOS users with Docker Desktop:
```bash
--volume /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock \
--env SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
```

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
See `Pix.UserSettings` documentation for configuration options.

## Security

- Only import remote pipelines from verified, trusted sources

## Current limitations

- Service containers are not currently supported (e.g., sidecar containers for integration testing)

Workaround: Use Docker Compose to define and manage test environments.
