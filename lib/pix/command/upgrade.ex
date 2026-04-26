defmodule Pix.Command.Upgrade do
  @moduledoc false

  @github_user_repo "athonet-open/pix"

  @cli_args [dry_run: :boolean]

  @spec cmd(Pix.UserSettings.t(), OptionParser.argv()) :: :ok
  def cmd(user_settings, argv) do
    {cli_opts, _args} = Pix.Helper.option_parser_parse!(argv, strict: @cli_args)

    cli_opts = Keyword.merge(cli_opts, user_settings.command.upgrade.cli_opts)
    dry_run? = Keyword.get(cli_opts, :dry_run, false)

    current_version = Application.fetch_env!(:pix, :version)

    case Pix.UpgradeCheck.get_latest_version_from_github() do
      {:ok, latest_version} ->
        maybe_upgrade(latest_version, current_version, dry_run?)

      {:error, reason} ->
        Pix.Report.error("Upgrade failed: #{inspect(reason)}\n")
    end

    :ok
  end

  defp maybe_upgrade(latest_version, current_version, dry_run?) do
    if Version.compare(latest_version, current_version) == :gt do
      Pix.Report.info("A new version of Pix is available: #{latest_version}\n")
      if not dry_run?, do: upgrade(latest_version)
    else
      Pix.Report.info("Pix is up to date\n")
    end
  end

  @spec upgrade(String.t()) :: :ok
  defp upgrade(latest_version) do
    Pix.Report.info("Updating ...\n")

    {_, 0} =
      System.cmd("mix", ["escript.install", "--force", "github", @github_user_repo, "ref", "v#{latest_version}"],
        into: IO.stream()
      )

    Pix.Report.info("Update complete\n")

    :ok
  end
end
