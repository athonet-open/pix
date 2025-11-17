defmodule Pix.Command.Help do
  @moduledoc false

  defp _cmd(s), do: IO.ANSI.format([:green, s])
  defp _opt(s), do: IO.ANSI.format([:faint, :green, s])
  defp _var(s), do: IO.ANSI.format([:blue, s])
  defp _section(s), do: IO.ANSI.format([:bright, s])

  @spec cmd(OptionParser.argv()) :: :ok
  def cmd(argv) do
    argv =
      if argv == [] do
        ["ls", "graph", "run", "shell", "upgrade", "cache", "completion_script", "help"]
      else
        argv
      end

    commands = Enum.map_join(argv, "\n", &help_cmd/1)

    Pix.Report.info("""
    Pix - Pipelines for buildx.

    #{_section("COMMANDS")}:

    #{commands}

    #{_section("ENVIRONMENT VARIABLES")}:

      These environment variables can be used to force/override some "internal" behaviour of pix.

      #{_var("PIX_DEBUG")}:                    Set to "true" to diplay debug logs
      #{_var("PIX_FORCE_PLATFORM_ARCH")}:      Set to "amd64"/"arm64" if you want to run the pipeline (and build docker images) with a non-native architecture
      #{_var("PIX_DOCKER_RUN_OPTS")}:          Set extra options for the `docker run` command
      #{_var("PIX_DOCKER_BUILD_OPTS")}:        Set extra options for the `docker buildx build` command
      #{_var("PIX_DOCKER_BUILDKIT_VERSION")}:  Use a specific version of docker buildkit.
                                    If specified, pix will start and use a buildkit docker instance with the specified version.
                                    Otherwise, pix will use the current selected builder instance (ref: docker buildx ls, docker buildx use)
      #{_var("PIX_DOCKER_BUILDX_DEBUG")}:      Set to "true" to enable `docker buildx debug`.
                                    If enabled and an error occurs in a `RUN` command, an interactive shell is presented
                                    which can be used for investigating the error interactively.
    """)

    :ok
  end

  defp help_cmd("ls") do
    """
    #{_cmd("pix ls")} [#{_opt("--verbose")}] [#{_opt("--hidden")}] [PIPELINE]

      List the current project's pipelines.

      ARGS:
          PIPELINE            The selected pipeline (default: all the pipelines)

      FLAGS:
          #{_opt("--verbose")}           Show pipeline configuration details
          #{_opt("--hidden")}            Show also private pipelines targets
    """
  end

  defp help_cmd("graph") do
    """
    #{_cmd("pix graph")} [#{_opt("--format FORMAT")}] PIPELINE

      Prints the pipeline graph.

        ARGS:
            PIPELINE            The selected pipeline

        OPTIONS:
            #{_opt("--format")}            Output format - "pretty", "dot" (default "pretty").
                                "dot" produces a DOT graph description of the pipeline graph in graph.dot in the current directory (dot -Tpng graph.dot -o graph.png).
    """
  end

  defp help_cmd("run") do
    """
    #{_cmd("pix run")} [#{_opt("--output")}] [#{_opt("--ssh")}] [#{_opt("--arg ARG")} ...] [#{_opt("--progress PROGRESS")}] [#{_opt("--target TARGET")} [#{_opt("--tag TAG")}]] [#{_opt("--no-cache")}] [#{_opt("--no-cache-filter TARGET")} ...] PIPELINE

      Run PIPELINE.

      ARGS:
          PIPELINE            The selected pipeline

      FLAGS:
          #{_opt("--no-cache")}          Do not use cache when building the image
          #{_opt("--output")}            Output the target artifacts under #{Pix.Pipeline.output_dir()} directory

      OPTIONS:
          #{_opt("--arg")}*              Set one or more pipeline ARG (format KEY=value)
          #{_opt("--no-cache-filter")}*  Do not cache specified targets
          #{_opt("--progress")}          Set type of progress output - "auto", "plain", "tty", "rawjson" (default "auto")
          #{_opt("--secret")}*           Forward one or more secrets to `buildx build`
          #{_opt("--ssh")}               Forward SSH agent to `buildx build`
          #{_opt("--tag")}               Tag the TARGET's docker image (default: no tag)
          #{_opt("--target")}            Run PIPELINE for a specific TARGET (default: all the PIPELINE targets)
    """
  end

  defp help_cmd("shell") do
    """
    #{_cmd("pix shell")} [#{_opt("--ssh")}] [#{_opt("--arg ARG")} ...] [#{_opt("--target TARGET")}] [#{_opt("--host")}] PIPELINE [COMMAND]

      Shell into the specified target of the PIPELINE.

      ARGS:
          PIPELINE            The selected pipeline
          COMMAND             If specified the COMMAND will be execute as a one-off command in the shell

      FLAGS:
          #{_opt("--host")}              The shell bind mounts the current working dir (reflect files changes between the host and the shell container)

      OPTIONS:
          #{_opt("--arg")}*              Set one or more pipeline ARG (format KEY=value)
          #{_opt("--ssh")}               Forward SSH agent to shell container
          #{_opt("--target")}            The shell target
    """
  end

  defp help_cmd("upgrade") do
    """
    #{_cmd("pix upgrade [#{_opt("--dry-run")}]")}

      Upgrade pix to the latest version.

      FLAGS:
          #{_opt("--dry-run")}           Only check if an upgrade is available
    """
  end

  defp help_cmd("cache") do
    """
    #{_cmd("pix cache")} #{_opt("info")}|#{_opt("update")}|#{_opt("clear")}

      Cache management.

      ARGS:
          #{_opt("info")}                Show info about the cache
          #{_opt("update")}              Update the cache of remote git pipelines
          #{_opt("clear")}               Clear the cache of remote git pipelines
    """
  end

  defp help_cmd("completion_script") do
    """
    #{_cmd("pix completion_script")} #{_opt("fish")}

      Display completion script.

      ARGS:
          SHELL_TYPE          The shell type - (supported: "fish")
    """
  end

  defp help_cmd("help") do
    """
    #{_cmd("pix help")} [COMMAND ...]

      Display help.

      ARGS:
          COMMAND             The command for which you want to display the help
    """
  end

  defp help_cmd(_), do: ""
end
