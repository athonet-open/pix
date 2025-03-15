defmodule Pix do
  @moduledoc false

  @spec main(OptionParser.argv()) :: :ok
  def main(["__complete_" <> shell_type | sub_argv]) do
    Pix.Report.disable()
    Pix.Command.Help.complete(shell_type, sub_argv, Pix.Config.get())
  end

  def main(argv) do
    Pix.Report.info("pix v#{Application.fetch_env!(:pix, :version)}\n\n")

    Pix.System.setup()

    user_settings = load_user_setting()

    case argv do
      ["cache" | sub_argv] ->
        Pix.Command.Cache.cmd(Pix.Config.get(), sub_argv)

      ["ls" | sub_argv] ->
        Pix.Command.Ls.cmd(user_settings, Pix.Config.get(), sub_argv)

      ["graph" | sub_argv] ->
        Pix.Command.Graph.cmd(user_settings, Pix.Config.get(), sub_argv)

      ["run" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.Run.cmd(user_settings, Pix.Config.get(), sub_argv)

      ["shell" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.Shell.cmd(user_settings, Pix.Config.get(), sub_argv)

      ["upgrade" | sub_argv] ->
        Pix.Command.Upgrade.cmd(user_settings, sub_argv)

      ["help" | sub_argv] ->
        Pix.Command.Help.cmd(sub_argv)

      cmd ->
        Pix.Report.error("Unknown command #{inspect(cmd)}\n")
        System.halt(1)
    end

    :ok
  end

  @spec load_user_setting :: Pix.UserSettings.t()
  defp load_user_setting do
    user_settings = Pix.UserSettings.get()

    for {var_name, var_value} <- user_settings.env do
      System.put_env(var_name, var_value)
    end

    user_settings
  end
end
