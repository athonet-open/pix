defmodule Pix.Command do
  @moduledoc false

  @github_user_repo "athonet-open/pix"

  defp _cmd(s), do: IO.ANSI.format([:green, s])
  defp _opt(s), do: IO.ANSI.format([:faint, :green, s])
  defp _var(s), do: IO.ANSI.format([:blue, s])
  defp _section(s), do: IO.ANSI.format([:bright, s])

  @spec help(OptionParser.argv()) :: :ok
  def help(argv) do
    argv = if argv == [], do: ["ls", "graph", "run", "shell", "upgrade", "help"], else: argv
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
          #{_opt("--output")}            Output the target artifacts under .pipeline/output directory

      OPTIONS:
          #{_opt("--arg")}*              Set one or more pipeline ARG (format KEY=value)
          #{_opt("--no-cache-filter")}*  Do not cache specified targets
          #{_opt("--progress")}          Set type of progress output - "auto", "plain", "tty", "rawjson" (default "auto")
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

  defp help_cmd("help") do
    """
    #{_cmd("pix help")} [COMMAND ...]

      Display help.

      ARGS:
          COMMAND             The command for which you want to display the help
    """
  end

  defp help_cmd(_), do: ""

  @spec graph(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_graph [format: :string]
  def graph(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_graph)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.graph.cli_opts)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
        pipeline = config_pipelines[pipeline_alias].pipeline_mod.pipeline()

        case cli_opts[:format] do
          format when format in [nil, "pretty"] ->
            display_graph(pipeline)

          "dot" ->
            export_dot(pipeline)
        end

      [unknown_pipeline_alias] ->
        Pix.Report.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Report.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Report.error("'graph' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end

    :ok
  end

  defp export_dot(pipeline) do
    dag = Pix.Pipeline.Graph.get(pipeline)

    dot = [
      "strict digraph {\n",
      Enum.map(dag, fn
        {from_node, to_node} -> [inspect(from_node), " -> ", inspect(to_node), "\n"]
        single_node -> [inspect(single_node), "\n"]
      end),
      "\n}\n"
    ]

    File.write!("graph.dot", dot)

    Pix.Report.info("Generated graph.dot\n")

    case System.find_executable("dot") do
      nil ->
        Pix.Report.info("'dot' command not found, cannot generate graph.png\n")

      dot ->
        System.cmd(dot, ["-Tpng", "graph.dot", "-o", "graph.png"])
        Pix.Report.info("Generated graph.png\n")
    end
  end

  defp display_graph(pipeline) do
    dag = Pix.Pipeline.Graph.get(pipeline)
    roots = Pix.Pipeline.Graph.roots(dag)
    adj_list = Pix.Pipeline.Graph.adjacency_list(dag)

    ansi_colors = [
      :black,
      :blue,
      :cyan,
      :green,
      :magenta,
      :red,
      :white,
      :yellow,
      :light_black,
      :light_blue,
      :light_cyan,
      :light_green,
      :light_magenta,
      :light_red,
      :light_white,
      :light_yellow
    ]

    node_colors = dag |> Pix.Pipeline.Graph.nodes() |> Enum.zip(Stream.cycle(ansi_colors)) |> Map.new()

    Pix.Report.info("\nPipeline graph:\n\n")

    IO.puts(IO.ANSI.format([:bright, pipeline.name]))

    last_root = List.last(roots)

    for root <- roots do
      plot_graph(node_colors, root, adj_list, "", MapSet.new(), root == last_root)
    end

    :ok
  end

  defp plot_graph(node_colors, node, adj_list, prefix, seen, is_last) do
    children = Map.get(adj_list, node, [])
    last_child = List.last(children)

    # Print current node with proper spacing
    node_str = IO.ANSI.format([Map.fetch!(node_colors, node), node])
    x = if is_last, do: "└─", else: "├─"
    IO.puts("#{prefix}#{x} #{node_str}")

    # Process children
    seen = MapSet.put(seen, node)

    for child <- children do
      next_prefix = if is_last, do: prefix <> "   ", else: prefix <> "│  "

      if child not in seen,
        do: plot_graph(node_colors, child, adj_list, next_prefix, seen, child == last_child)
    end
  end

  @spec ls(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_ls [verbose: :boolean, hidden: :boolean]
  def ls(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_ls)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.ls.cli_opts)
    verbose? = Keyword.get(cli_opts, :verbose, false)
    hidden? = Keyword.get(cli_opts, :hidden, false)
    config_pipelines = config.pipelines

    config_pipelines =
      case args do
        [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
          Map.take(config_pipelines, [pipeline_alias])

        _ ->
          config_pipelines
      end

    display_pipelines(config_pipelines, verbose?, hidden?)

    :ok
  end

  defp display_pipelines(pipelines, verbose?, hidden?) do
    IO.puts(IO.ANSI.format([:bright, "\nAvailable pipelines:\n"]))

    for {alias_, pipeline} <- pipelines do
      display_pipeline_header(alias_)

      if verbose? do
        display_pipeline_details(pipeline)
        display_pipeline_targets(pipeline, hidden?)
        IO.puts("")
      end
    end
  end

  defp display_pipeline_header(alias_) do
    IO.puts(IO.ANSI.format([:bright, "📦 #{alias_}"]))
    IO.puts(String.duplicate("─", String.length(alias_) + 4))
    IO.puts("")
  end

  defp display_pipeline_details(%{pipeline_mod: mod, default_args: args}) do
    pipeline = mod.pipeline()

    if args != %{} do
      IO.puts("📝 Default Arguments:")
      display_args(args, "   ")
      IO.puts("")
    end

    IO.puts("📝 Description:")

    pipeline.description
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(&IO.puts("   #{IO.ANSI.format([:faint, &1])}"))

    IO.puts("")

    shell_status = if function_exported?(mod, :shell, 3), do: "Available", else: "Not Available"
    IO.puts("🐚 Shell Access: #{IO.ANSI.format([:faint, shell_status])}")
    IO.puts("")
  end

  defp display_pipeline_targets(%{default_targets: defaults, pipeline_mod: mod}, hidden?) do
    pipeline = mod.pipeline()
    IO.puts("🎯 Default Targets: #{IO.ANSI.format([:faint, :green, inspect(defaults)])}")
    IO.puts("")
    IO.puts("📋 Targets:")
    IO.puts("")

    for stage <- pipeline.stages, hidden? or not stage.private do
      display_stage(stage)
    end
  end

  defp display_stage(%Pix.Pipeline.SDK.Stage{
         stage: name,
         args_: args,
         outputs: outputs,
         description: description,
         private: private,
         cache: cache
       }) do
    stage_format = if private, do: [:faint, :green], else: [:green]
    IO.puts("   ▶️ #{IO.ANSI.format(stage_format ++ [name])}")

    if description, do: IO.puts("      • Description: #{IO.ANSI.format([:faint, description])}")
    if private, do: IO.puts("      • Private: true")
    if not cache, do: IO.puts("      • Cache: #{IO.ANSI.format([:faint, "Disabled"])}")

    if args != %{} do
      IO.puts("      • Arguments:")
      display_args(args, "        - ")
    end

    if outputs != [] do
      IO.puts("      • Outputs:")

      for output <- outputs do
        IO.puts("        - #{IO.ANSI.format([:yellow, :faint, output])}")
      end
    end

    IO.puts("")
  end

  defp display_args(args, indent) do
    for {k, v} <- args, not String.starts_with?(k, "PIX_") do
      IO.puts([indent, IO.ANSI.format([:faint, :blue, k, :reset, :faint, ": #{inspect(v)}"])])
    end
  end

  @spec run(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_run [
    arg: [:string, :keep],
    no_cache: :boolean,
    no_cache_filter: [:string, :keep],
    output: :boolean,
    progress: :string,
    ssh: :boolean,
    tag: :string,
    target: :string
  ]
  def run(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_run)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.run.cli_opts)
    config_pipelines = config.pipelines

    validate_run_cli_opts!(cli_opts)

    case args do
      [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.run(config_pipelines[pipeline_alias], cli_opts)

      [unknown_pipeline_alias] ->
        Pix.Report.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Report.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Report.error("'run' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end

    :ok
  end

  @spec shell(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_shell [
    arg: [:string, :keep],
    host: :boolean,
    ssh: :boolean,
    target: :string
  ]
  def shell(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_shell)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.shell.cli_opts)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias | cmd_args] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.shell(config_pipelines[pipeline_alias], cli_opts, cmd_args)

      [unknown_pipeline_alias | _] ->
        Pix.Report.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Report.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)
    end

    :ok
  end

  @spec upgrade(Pix.UserSettings.t(), OptionParser.argv()) :: :ok
  @cli_args_upgrade [dry_run: :boolean]
  def upgrade(user_settings, argv) do
    {cli_opts, _args} = OptionParser.parse!(argv, strict: @cli_args_upgrade)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.upgrade.cli_opts)
    dry_run? = Keyword.get(cli_opts, :dry_run, false)

    current_version = Application.fetch_env!(:pix, :version)

    with {:ok, latest_version} <- get_latest_version_from_github(),
         {:vsn, :gt} <- {:vsn, Version.compare(latest_version, current_version)} do
      Pix.Report.info("A new version of Pix is available: #{latest_version}\n")

      if not dry_run?, do: do_upgrade(latest_version)
    else
      {:error, reason} ->
        Pix.Report.error("Upgrade failed: #{inspect(reason)}\n")

      {:vsn, _} ->
        Pix.Report.info("Pix is up to date\n")
    end

    :ok
  end

  @spec get_latest_version_from_github() :: {:ok, String.t()} | {:error, term()}
  defp get_latest_version_from_github do
    timeout = 3_000
    endpoint_uri = "https://api.github.com/repos/#{@github_user_repo}/tags?per_page=1"
    headers = [{~c"User-Agent", ~c"pix"}, {~c"Accept", ~c"application/vnd.github+json"}]

    case :httpc.request(:get, {endpoint_uri, headers}, [timeout: timeout], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body = body |> IO.iodata_to_binary() |> Jason.decode!()

        case body do
          [%{"name" => "v" <> latest_tag}] ->
            {:ok, latest_tag}

          _ ->
            {:error, "Failed to parse latest version from GitHub"}
        end

      {:error, reason} ->
        {:error, "Failed to fetch latest version from GitHub: #{inspect(reason)}"}
    end
  end

  @spec do_upgrade(String.t()) :: :ok
  defp do_upgrade(latest_version) do
    Pix.Report.info("Updating ...\n")

    {_, 0} =
      System.cmd("mix", ["escript.install", "--force", "github", @github_user_repo, "ref", "v#{latest_version}"],
        into: IO.stream()
      )

    Pix.Report.info("Update complete\n")

    :ok
  end

  @spec validate_run_cli_opts!(OptionParser.parsed()) :: :ok
  defp validate_run_cli_opts!(cli_opts) do
    if Keyword.has_key?(cli_opts, :tag) and not Keyword.has_key?(cli_opts, :target) do
      Pix.Report.error("--tag option requires a --target\n")
      System.halt(1)
    end

    :ok
  end
end
