defmodule Pix.Command.Upgrade do
  @moduledoc false

  @github_user_repo "athonet-open/pix"

  @cli_args [dry_run: :boolean]

  @spec cmd(Pix.UserSettings.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, argv) do
    {cli_opts, _args} = OptionParser.parse!(argv, strict: @cli_args)
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
end
