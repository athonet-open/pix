# PIX

[![.github/workflows/ci.yml](https://github.com/visciang/pix/actions/workflows/ci.yml/badge.svg)](https://github.com/visciang/pix/actions/workflows/ci.yml) [![Docs](https://img.shields.io/badge/docs-latest-green.svg)](https://visciang.github.io/pix/readme.html)

Pipelines for buildx.

## Introduction

Pix is a portable pipeline executor - a CI framework to define and execute pipelines that can run on any host with docker support.
Pipelines are defined as code and executed via docker `buildkit`.

## Basic concepts

### The pipeline

The pipeline is the core of the Pix framework.
It's just an instrumented docker multistage build programmatically defined via Elixir code (using the `Pix.Pipeline.SDK`).

### The pipeline executor

Pix generates the multistage docker build definition and execute it via `docker buildx build`.
The execution semantic (parallelism, cache, etc) is the same as a standard docker build.

## Installation

Pix can be installed nativelly as an Elixir escript.

```bash
$ mix escript.install github visciang/pix ref vX.Y.Z
```

alternatively, you can use it as a docker image:

```bash
$ docker run --rm -it \
  --volume $PWD:/code --workdir /code \
  # docker outside of docker mode \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  # SSH forwarding \
  --volume $SSH_AUTH_SOCK:$SSH_AUTH_SOCK \
  --env SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
  ghcr.io/visciang/pix:X.Y.Z
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

The project is defined with a [.pix.exs](.pix.exs) file.

In the .pix.exs file, we setup a single pipeline - `pix` - with its default arguments and targets.
The pipeline definition is imported `from` a local `path` (in this case `.`, root directory).

In the root directory we have the [pipeline.exs](pipeline.exs) file that defines the pipeline.
The pipeline definition is composed of a set of targets, each target is a named docker stage.

To run the project pipeline, we can use the `pix run` command.

```bash
$ pix run pix
```

This will build the project, the docs, run the tests, etc..

The `pix ls pix` command can be used to list all the pipelines declared in the project along with their configuration.

Then the `pix graph pix` command can be used to generate a graph of a specific pipeline.

The Pix Elixir documentation is built by `pix.docs` target of the pipeline, run `pix run --output pix` to run the pipeline and output the produced artifacts to the current directory. The docs will be available under `.pipeline/output/doc/index.html`.

For more information about the available commands and their options, run `pix help`.

## User settings

User specific settings can be defined in the `~/.config/pix/settings.exs` file, the file is loaded automatically by pix.
Refer to `Pix.UserSettings` for more information.
