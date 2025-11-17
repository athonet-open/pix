defmodule Pix.Command.Shell do
  @moduledoc false

  @cli_args [
    arg: [:string, :keep],
    host: :boolean,
    secret: [:string, :keep],
    ssh: :boolean,
    target: :string
  ]

  @spec cmd(Pix.UserSettings.t(), Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args)
    cli_opts = Keyword.merge(cli_opts, user_settings.command.shell.cli_opts)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias | cmd_args] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.shell(config_pipelines[pipeline_alias], cli_opts, cmd_args)

      [unknown_pipeline_alias | _] ->
        Pix.Report.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Report.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Report.error("'shell' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end

    :ok
  end
end
