defmodule Pix.Command.Ls do
  @moduledoc false

  @cli_args [verbose: :boolean, hidden: :boolean]

  @spec cmd(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, config, argv) do
    {cli_opts, args} = Pix.Helper.option_parser_parse!(argv, strict: @cli_args)
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
    for {arg_name, %{default: default, description: description}} <- args, not String.starts_with?(arg_name, "PIX_") do
      desc_suffix = if description, do: " — #{description}", else: ""

      IO.puts([
        indent,
        IO.ANSI.format([:faint, :blue, arg_name, :reset, :faint, ": #{inspect(default)}#{desc_suffix}"])
      ])
    end
  end
end
