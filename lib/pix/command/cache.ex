defmodule Pix.Command.Cache do
  @moduledoc false

  @cli_args []

  @spec cmd(Pix.Config.t(), OptionParser.argv()) :: :ok
  def cmd(config, argv) do
    {_cli_opts, args} = Pix.Helper.option_parser_parse!(argv, strict: @cli_args)

    case args do
      ["info"] ->
        info(config)

      ["update"] ->
        update(config)

      ["outdated"] ->
        outdated()

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

          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
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

          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
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

  @spec outdated() :: :ok
  defp outdated do
    case outdated_pipelines() do
      [] ->
        Pix.Report.info("\nAll cached pipelines are up-to-date.\n")

      stale ->
        Pix.Report.info("\nOutdated cached pipelines:\n")

        for entry <- stale do
          Pix.Report.info(
            "  - #{entry.path} (#{entry.ref})\n" <>
              "    local:  #{entry.local_sha}\n" <>
              "    remote: #{entry.remote_sha}\n"
          )
        end

        Pix.Report.info("\nRun 'pix cache update' to update.\n")
        System.halt(1)
    end

    :ok
  end

  @ls_remote_timeout 3_000

  @spec outdated_pipelines() :: [%{path: String.t(), ref: String.t(), local_sha: String.t(), remote_sha: String.t()}]
  def outdated_pipelines do
    checkout_base_dir = Pix.Config.checkout_base_dir()

    if File.dir?(checkout_base_dir) do
      checkout_base_dir
      |> find_git_repos()
      |> Task.async_stream(&check_repo_staleness/1, timeout: @ls_remote_timeout, on_timeout: :kill_task)
      |> Enum.flat_map(fn
        {:ok, {:stale, entry}} -> [entry]
        _ -> []
      end)
    else
      []
    end
  end

  defp find_git_repos(base_dir) do
    base_dir
    |> Path.join("**/.git")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(&Path.dirname/1)
  end

  defp check_repo_staleness(checkout_dir) do
    cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]

    # The ref is encoded in the directory path: <checkout_base_dir>/<repo>/<ref>
    ref = Path.basename(checkout_dir)

    with {local_sha, 0} <- System.cmd("git", ["rev-parse", "HEAD"], cmd_opts),
         local_sha = String.trim(local_sha),
         {ls_remote_output, exit_code} when exit_code == 0 <-
           System.cmd("git", ["ls-remote", "origin", ref], cmd_opts) do
      remote_sha =
        ls_remote_output
        |> String.split("\t")
        |> List.first("")
        |> String.trim()

      if remote_sha != "" and remote_sha != local_sha do
        {:stale, %{path: checkout_dir, ref: ref, local_sha: local_sha, remote_sha: remote_sha}}
      else
        :up_to_date
      end
    else
      _ -> :skip
    end
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
