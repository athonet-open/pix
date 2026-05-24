defmodule Pix.Command.Setup do
  @moduledoc false

  @spec cmd(OptionParser.argv()) :: :ok
  def cmd(_argv) do
    Pix.IO.with_input(fn -> do_setup() end)
  end

  defp do_setup do
    path = Pix.UserSettings.settings_path()

    if File.regular?(path) do
      Pix.Report.info("A settings file already exists at: #{path}\n\n")

      unless Pix.IO.ask_yes_no("Overwrite existing settings?", false) do
        Pix.Report.info("Setup cancelled.\n")
        System.halt(0)
      end
    end

    case Pix.SetupWizard.run() do
      {:ok, settings} ->
        Pix.SetupWizard.save(settings)

      :abort ->
        :ok
    end

    :ok
  end
end
