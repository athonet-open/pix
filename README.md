# PIX

[![.github/workflows/ci.yml](https://github.com/athonet-open/pix/actions/workflows/ci.yml/badge.svg)](https://github.com/athonet-open/pix/actions/workflows/ci.yml) [![Docs](https://img.shields.io/badge/docs-latest-green.svg)](https://athonet-open.github.io/pix)

BuildKit pipelines.

Documentation [website](https://athonet-open.github.io/pix).

## Introduction

Pix is a portable pipeline executor - a CI framework to define and execute pipelines that can run on any host with docker support.
Pipelines are defined as code and executed via docker [BuildKit](https://github.com/moby/buildkit).

## Basic concepts

### The pipeline

The building blocks of a pipeline are:
- **stage**: this is where the actual work is done (ie. execute tests, build an application, perform a deployment, etc). A stage can be parameterized via **arguments**.
- **output**: a stage can produce outputs (ie. running a test suite and output a coverage report, generate documentation, etc).
- **dependency**: stages are connected via **dependencies** to define an execution graph.

Under the hood, a pipeline is an instrumented docker multistage build, it is programmatically defined via Elixir code (using the `Pix.Pipeline.SDK`).

### The pipeline executor

Pix generates the multistage docker build definition and execute it via `docker buildx build`.
The execution semantic (parallelism, cache, etc) is the same of a docker build graph.

### The Project

At the root of your project you can define a `.pix.exs` file that declare the pipeline available for your project.
In the .pix.exs file you declare the pipelines with their default arguments and targets.
The pipelines definition can be imported `from` a local `path` or a remote `git` repository.

More details in the `Pix.Project` module documentation.

### The Pipeline definition

The pipeline is a programmatic definition of a docker multistage build.
It is composed of a set of targets, each target is a named docker build stage and defined in a `pipeline.exs` using the `Pix.Pipeline.SDK`.

More details in the `Pix.Pipeline.SDK` module documentation.

## Installation

### Prerequisites

Pix requires a `docker` engine to be installed on the host.

### Installation options

Pix can be installed natively as an Elixir escript, in this can you need erlang/elixir installed on your system:

```bash
$ mix escript.install github athonet-open/pix ref vX.Y.Z
```

alternatively, you can use it as a docker image:

```bash
$ docker run --rm -it \
  --volume $PWD:/$PWD --workdir /$PWD \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --volume $SSH_AUTH_SOCK:$SSH_AUTH_SOCK \
  --env SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
  ghcr.io/athonet-open/pix:X.Y.Z "$@"
```

in this case is important to give the pix container access the docker engine.
You can use the Docker Socket Mounting (DooD - Docker outside of docker) or the Docker-in-Docker (dind) mode.

If you need SSH access, you need to forward the SSH agent socket to the pix container.
Note: if running on a Mac via docker-desktop, the SSH socket of the docker VM is accessible via:

```bash
--volume /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock \
--env SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
```

## Quick start

For this quick start, we will use the pix project itself.
The pix project declares a pipeline that can be used to build and test pix itself.

The project is declared with a [.pix.exs](https://github.com/athonet-open/pix/blob/main/.pix.exs) file, where a single pipeline - `pix` - has been defined with its default arguments and targets.

The [pipeline.exs](https://github.com/athonet-open/pix/blob/main/pipeline.exs) file define the `pix` pipeline.

To run the project pipeline, we can use the `pix run` command.

```bash
$ pix run pix
```

This will build the project, the docs, run the tests, etc..

The `pix ls --verbose pix` command can be used to list all the pipelines declared in the project along with their configuration.

Then the `pix graph pix` command can be used to generate a graph of a specific pipeline.

The Pix Elixir documentation is built by `pix.docs` target of the pipeline, run `pix run --output pix` to run the pipeline and output the produced artifacts to the current directory. The docs will be available under `.pipeline/output/doc/index.html`.

For more information about the available commands and their options, run `pix help`.

## User settings

User specific settings can be defined in the `~/.config/pix/settings.exs` file, the file is loaded automatically by pix.
Refer to `Pix.UserSettings` for more information.

## Security

- Import remote pipelines only from trusted sources.

## Limitations

- Service containers: currently service containers are not supported - ie. long-running sidecar containers that can be used to run integration tests while executing the pipeline.

A possible approach is to leverage docker compose to define and the test environment and run the tests.
