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
    Pix.Log.info("pix v#{version()}\n")
    Pix.System.setup()
    Pix.Log.info("\n")

    case argv do
      ["ls" | sub_argv] ->
        Pix.Command.ls(Pix.Config.get(), sub_argv)

      ["graph" | sub_argv] ->
        Pix.Command.graph(Pix.Config.get(), sub_argv)

      ["run" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.run(Pix.Config.get(), sub_argv)

      ["shell" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.shell(Pix.Config.get(), sub_argv)

      ["upgrade"] ->
        Pix.Command.upgrade()

      ["help"] ->
        Pix.Command.help()

      cmd ->
        Pix.Log.error("Unknown command #{inspect(cmd)}\n")
        System.halt(1)
    end

    :ok
  end
end
