defmodule Pix.Command.Cache do
  @moduledoc false

  @cli_args []

  @spec cmd(Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(config, argv) do
    {_cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args)

    case args do
      ["info"] ->
        info(config)

      ["update"] ->
        update(config)

      ["clear"] ->
        clear(config)

      cmd ->
        Pix.Report.error("Unknow cache command #{inspect(cmd)}\n")
        System.halt(1)
    end

    :ok
  end

  @spec info(Pix.Config.t()) :: :ok
  defp info(config) do
    Pix.Report.info("\nPIPELINES:\n")

    for {pipeline_alias, pipeline} <- config.pipelines do
      case pipeline do
        %{from: %{git: repo, ref: ref}} ->
          checkout_dir = Pix.Config.pipeline_checkout_dir(repo, ref)

          if File.dir?(checkout_dir) do
            Pix.Report.info("  - #{pipeline_alias}: git pipeline #{repo}@#{ref}\n    CACHED #{checkout_dir}\n")
          else
            Pix.Report.info("  - #{pipeline_alias}: git pipeline #{repo}@#{ref}\n    NOT CACHED\n")
          end

        %{from: %{path: _} = from} ->
          Pix.Report.info("  - #{pipeline_alias}: local pipeline #{inspect(from)}\n")
      end
    end

    Pix.Report.info("\nBUILDKIT:\n")

    builder =
      case System.get_env("PIX_DOCKER_BUILDKIT_VERSION") do
        nil ->
          {:ok, %{"ClientInfo" => %{"Context" => default_builder}}} = Pix.Docker.info()
          default_builder

        buildkit_version ->
          "pix-buildkit-#{buildkit_version}"
      end

    Pix.Report.info("  builder: #{builder}\n")

    :ok
  end

  @spec update(Pix.Config.t()) :: :ok
  defp update(config) do
    Pix.Report.info("\nUpdating remote git pipelines cache...\n")

    for {pipeline_alias, pipeline} <- config.pipelines do
      case pipeline do
        %{from: %{git: repo, ref: ref}} ->
          checkout_dir = Pix.Config.pipeline_checkout_dir(repo, ref)

          if File.dir?(checkout_dir) do
            cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]
            {_, 0} = System.cmd("git", ["fetch", "origin", ref], cmd_opts)
            {_, 0} = System.cmd("git", ["reset", "--hard", "FETCH_HEAD"], cmd_opts)

            Pix.Report.info("  - #{pipeline_alias}: git pipeline #{repo}@#{ref}\n    UPDATED #{checkout_dir}\n")
          else
            Pix.Report.info("  - #{pipeline_alias}: git pipeline #{repo}@#{ref}\n    NOT CACHED\n")
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  @spec clear(Pix.Config.t()) :: :ok
  defp clear(config) do
    Pix.Report.info("\nClearing remote git pipelines cache...\n")

    for {pipeline_alias, pipeline} <- config.pipelines do
      case pipeline do
        %{from: %{git: repo, ref: ref}} ->
          checkout_dir = Pix.Config.pipeline_checkout_dir(repo, ref)

          File.rm_rf!(checkout_dir)
          Pix.Report.info("  - #{pipeline_alias}: git pipeline #{repo}@#{ref}\n    CLEARED #{checkout_dir}\n")

        _ ->
          :ok
      end
    end

    :ok
  end
end
