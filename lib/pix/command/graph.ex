defmodule Pix.Command.Graph do
  @moduledoc false

  @cli_args [format: :string]

  @spec cmd(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args)
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
end
