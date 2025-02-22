defmodule Pix do
  @moduledoc false

  # We should recompile if the version changes.
  # Reading the version from `Mix.Project.config()[:version]` is not correct
  # since the mix.exs file does not change if the env var VERSION change.
  @external_resource "VERSION"
  @version File.read!("VERSION")

  @spec version :: String.t()
  def version, do: @version

  @spec main(OptionParser.argv()) :: :ok
  def main(argv) do
    Pix.Report.info("pix v#{version()}\n")
    Pix.System.setup()
    Pix.Report.info("\n")

    user_settings = load_user_setting()

    case argv do
      ["ls" | sub_argv] ->
        Pix.Command.ls(user_settings, Pix.Config.get(), sub_argv)

      ["graph" | sub_argv] ->
        Pix.Command.graph(user_settings, Pix.Config.get(), sub_argv)

      ["run" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.run(user_settings, Pix.Config.get(), sub_argv)

      ["shell" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.shell(user_settings, Pix.Config.get(), sub_argv)

      ["upgrade" | sub_argv] ->
        Pix.Command.upgrade(user_settings, sub_argv)

      ["help"] ->
        Pix.Command.help()

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
