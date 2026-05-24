defmodule Pix do
  @moduledoc false

  @spec main(OptionParser.argv()) :: :ok
  def main(["__complete_" <> shell_type | sub_argv]) do
    Pix.Report.disable()
    Pix.Command.Completion.complete(shell_type, sub_argv, Pix.Config.get())
  end

  def main(["completion_script" | sub_argv]) do
    Pix.Report.disable()
    Pix.Command.Completion.script(sub_argv)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def main(argv) do
    Pix.Report.info("pix v#{Application.fetch_env!(:pix, :version)}\n\n")

    Pix.System.setup()

    user_settings = load_user_setting(argv)

    upgrade_check =
      case argv do
        ["upgrade" | _] -> nil
        _ -> Pix.UpgradeCheck.start()
      end

    cache_check =
      case argv do
        ["cache" | _] ->
          nil

        _ ->
          config = Pix.Config.get()
          if config != nil, do: Pix.CacheCheck.start(config)
      end

    case argv do
      ["cache" | sub_argv] ->
        Pix.Command.Cache.cmd(Pix.Config.get!(), sub_argv)

      ["ls" | sub_argv] ->
        Pix.Command.Ls.cmd(user_settings, Pix.Config.get!(), sub_argv)

      ["graph" | sub_argv] ->
        Pix.Command.Graph.cmd(user_settings, Pix.Config.get!(), sub_argv)

      ["run" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.Run.cmd(user_settings, Pix.Config.get!(), sub_argv)

      ["shell" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.Shell.cmd(user_settings, Pix.Config.get!(), sub_argv)

      ["upgrade" | sub_argv] ->
        Pix.Command.Upgrade.cmd(user_settings, sub_argv)

      ["setup" | sub_argv] ->
        Pix.Command.Setup.cmd(sub_argv)

      ["help" | sub_argv] ->
        Pix.Command.Help.cmd(sub_argv)

      cmd ->
        Pix.Report.error("Unknown command #{inspect(cmd)}\n")
        System.halt(1)
    end

    Pix.UpgradeCheck.maybe_notify(upgrade_check)
    Pix.CacheCheck.maybe_notify(cache_check)

    :ok
  end

  @spec load_user_setting(OptionParser.argv()) :: Pix.UserSettings.t()
  defp load_user_setting(argv) do
    maybe_run_setup_wizard(argv)

    user_settings = Pix.UserSettings.get()

    for {var_name, var_value} <- user_settings.env do
      System.put_env(var_name, var_value)
    end

    user_settings
  end

  defp maybe_run_setup_wizard(argv) do
    command = List.first(argv, "")
    skip_commands = ~w(help setup upgrade completion_script)

    skip? =
      command in skip_commands or
        String.starts_with?(command, "__complete_") or
        Pix.Env.ci?() or
        not Pix.IO.tty?() or
        File.regular?(Pix.UserSettings.settings_path())

    unless skip? do
      Pix.Report.internal("No user settings found. Starting setup wizard...\n")

      case Pix.SetupWizard.run() do
        {:ok, settings} ->
          Pix.SetupWizard.save(settings)

        :abort ->
          Pix.Report.info("Saving empty configuration to skip wizard on next run.\n")
          Pix.SetupWizard.save(%{})
      end
    end
  end
end
