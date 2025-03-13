defmodule Pix.Command.Run do
  @moduledoc false

  @cli_args [
    arg: [:string, :keep],
    no_cache: :boolean,
    no_cache_filter: [:string, :keep],
    output: :boolean,
    progress: :string,
    ssh: :boolean,
    tag: :string,
    target: :string
  ]

  @spec cmd(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args)
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

  @spec validate_run_cli_opts!(OptionParser.parsed()) :: :ok
  defp validate_run_cli_opts!(cli_opts) do
    if Keyword.has_key?(cli_opts, :tag) and not Keyword.has_key?(cli_opts, :target) do
      Pix.Report.error("--tag option requires a --target\n")
      System.halt(1)
    end

    :ok
  end
end
