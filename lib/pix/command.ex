defmodule Pix.Command do
  @moduledoc false

  @github_user_repo "visciang/pix"

  @spec help :: :ok
  def help do
    section = &IO.ANSI.format([:bright, &1])
    cmd = &IO.ANSI.format([:green, &1])
    opt = &IO.ANSI.format([:faint, :green, &1])
    var = &IO.ANSI.format([:blue, &1])

    Pix.Log.info("""
    Pix - Pipelines for buildx.

    #{section.("COMMANDS")}:

    #{cmd.("pix ls")} [#{opt.("--all")}]
        List the current project's pipelines configuration.

        FLAGS:
            #{opt.("--all")}               Show also private pipelines targets

    #{cmd.("pix graph")} [#{opt.("--format FORMAT")}] PIPELINE
        Prints the pipeline graph.

        ARGS:
            PIPELINE            The selected pipeline

        OPTIONS:
            #{opt.("--format")}            Output format - "pretty", "dot" (default "pretty").
                                "dot" produces a DOT graph description of the pipeline graph in graph.dot in the current directory (dot -Tpng graph.dot -o graph.png).

    #{cmd.("pix run")} [#{opt.("--output")}] [#{opt.("--arg ARG")}]* [#{opt.("--progress PROGRESS")}] [#{opt.("--target TARGET")} [#{opt.("--tag TAG")}]] [#{opt.("--no-cache")}] [#{opt.("--no-cache-filter TARGET")}]* PIPELINE
        Run PIPELINE.

        ARGS:
            PIPELINE            The selected pipeline

        FLAGS:
            #{opt.("--output")}            Output the target artifacts under .pipeline/output directory
            #{opt.("--no-cache")}          Do not use cache when building the image

        OPTIONS:
            #{opt.("--arg")}*              Set pipeline one or more ARG (format KEY=value)
            #{opt.("--progress")}          Set type of progress output - "auto", "plain", "tty", "rawjson" (default "auto")
            #{opt.("--target")}            Run PIPELINE for a specific TARGET (default: all the PIPELINE targets)
            #{opt.("--tag")}               Tag the TARGET's docker image (default: no tag)
            #{opt.("--no-cache-filter")}*  Do not cache specified targets

    #{cmd.("pix shell")} [#{opt.("--target TARGET")}] [#{opt.("--host")}] PIPELINE [COMMAND]
        Shell into the specified target of the PIPELINE.

        ARGS:
            PIPELINE            The selected pipeline
            COMMAND             If specified the COMMAND will be execute as a one-off command in the shell

        FLAGS:
            #{opt.("--host")}              The shell bind mounts the current working dir (reflect files changes between the host and the shell container)

        OPTIONS:
            #{opt.("--target")}            The shell target

    #{cmd.("pix upgrade")}
        Upgrade pix to the latest version.

    #{cmd.("pix help")}
        This help.


    #{section.("ENVIRONMENT VARIABLES")}:

      These environment variables can be used to force/override some "internal" behaviour of pix.

      #{var.("PIX_DEBUG")}:                Set to "true" to diplay debug logs
      #{var.("PIX_FORCE_PLATFORM_ARCH")}:  Set to "amd64"/"arm64" if you want to run the pipeline (and build docker images) with a non-native architecture
      #{var.("PIX_DOCKER_RUN_OPTS")}:      Set extra options for the `docker run` command
      #{var.("PIX_DOCKER_BUILD_OPTS")}:    Set extra options for the `docker buildx build` command
    """)

    :ok
  end

  @spec graph(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_graph [format: :string]
  def graph(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_graph)
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
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Log.error("'graph' command accept exactly one pipeline but got #{inspect(args)}\n")
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

    Pix.Log.info("Generated graph.dot\n")
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

    Pix.Log.info("\nPipeline graph:\n\n")

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

  @spec ls(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_ls [all: :boolean]
  def ls(config, argv) do
    {cli_opts, _args} = OptionParser.parse!(argv, strict: @cli_args_ls)
    display_pipelines(config.pipelines, Keyword.get(cli_opts, :all, false))
    :ok
  end

  defp display_pipelines(pipelines, show_all?) do
    IO.puts("")

    for {alias_, pipeline} <- pipelines do
      display_pipeline_header(alias_, pipeline)
      display_pipeline_details(pipeline)
      display_pipeline_targets(pipeline, show_all?)
      IO.puts("")
    end
  end

  defp display_pipeline_header(alias_, %{default_args: args}) do
    IO.puts(IO.ANSI.format([:bright, :underline, alias_, "\n"]))
    IO.puts("  default_args:")
    display_args(args, "    ")
  end

  defp display_pipeline_details(%{pipeline_mod: mod}) do
    pipeline = mod.pipeline()
    IO.puts("  pipeline: #{IO.ANSI.format([:faint, pipeline.name])}")

    # Display description
    IO.puts("    description:")

    pipeline.description
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(&IO.puts("      #{IO.ANSI.format([:faint, &1])}"))

    # Display args and shell status
    IO.puts("    args:")
    display_args(pipeline.args_, "      ")
    shell_status = if function_exported?(mod, :shell, 3), do: "available", else: "not available"
    IO.puts("    shell: #{IO.ANSI.format([:faint, shell_status])}")
  end

  defp display_pipeline_targets(%{default_targets: defaults, pipeline_mod: mod}, show_all?) do
    pipeline = mod.pipeline()
    IO.puts("    targets:")
    IO.puts("      default: #{IO.ANSI.format([:faint, :green, inspect(defaults)])}")

    for stage <- pipeline.stages, show_all? or not stage.private do
      display_stage(stage)
    end
  end

  defp display_stage(%{stage: name, args_: args, outputs: outputs, private: private, cache: cache}) do
    # Stage name with formatting based on privacy
    stage_format = if private, do: [:faint, :green], else: [:green]
    IO.puts("      #{IO.ANSI.format(stage_format ++ [name])}:")

    # Display stage properties
    if private, do: IO.puts("        private: true")
    if not cache, do: IO.puts("        cache: #{IO.ANSI.format([:faint, "disabled"])}")

    # Display args and outputs
    IO.puts("        args:")
    display_args(args, "          ")
    IO.puts("        outputs:")
    for output <- outputs, do: IO.puts("          #{IO.ANSI.format([:yellow, :faint, "- #{inspect(output)}"])}")
  end

  defp display_args(args, indent) do
    for {k, v} <- args, not String.starts_with?(k, "PIX_") do
      IO.puts([indent, IO.ANSI.format([:faint, :blue, k, :reset, :faint, ": #{inspect(v)}"])])
    end
  end

  @spec run(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_run [
    arg: [:string, :keep],
    output: :boolean,
    progress: :string,
    tag: :string,
    target: :string,
    no_cache: :boolean,
    no_cache_filter: [:string, :keep]
  ]
  def run(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_run)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.run(config_pipelines[pipeline_alias], cli_opts)

      [unknown_pipeline_alias] ->
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Log.error("'run' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end

    :ok
  end

  @spec shell(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_shell [target: :string, host: :boolean]
  def shell(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_shell)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias | cmd_args] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.shell(config_pipelines[pipeline_alias], cli_opts, cmd_args)

      [unknown_pipeline_alias | _] ->
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)
    end

    :ok
  end

  @spec upgrade() :: :ok
  def upgrade do
    latest_version = get_latest_version_from_github()

    if Version.compare(latest_version, Pix.version()) == :gt do
      Pix.Log.info("A new version of Pix is available: #{latest_version}\n")

      Pix.Log.info("Updating ...\n")

      {_, 0} =
        System.cmd("mix", ["escript.install", "--force", "github", @github_user_repo, "ref", "v#{latest_version}"],
          into: IO.stream()
        )

      Pix.Log.info("Update complete\n")
    else
      Pix.Log.info("Pix is up to date\n")
    end

    :ok
  end

  @spec get_latest_version_from_github() :: String.t()
  defp get_latest_version_from_github do
    endpoint_uri = "https://api.github.com/repos/#{@github_user_repo}/tags?per_page=1"
    headers = [{~c"User-Agent", ~c"pix"}, {~c"Accept", ~c"application/vnd.github+json"}]

    case :httpc.request(:get, {endpoint_uri, headers}, [], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body = body |> IO.iodata_to_binary() |> JSON.decode!()

        case body do
          [%{"name" => "v" <> latest_tag}] ->
            latest_tag

          _ ->
            Pix.Log.error("Failed to parse latest version from GitHub\n")
            Pix.Log.error("Body: #{inspect(body)}\n")
            System.halt(1)
        end

      {:error, reason} ->
        Pix.Log.error("Failed to fetch latest version from GitHub: #{inspect(reason)}\n")
        System.halt(1)
    end
  end
end
