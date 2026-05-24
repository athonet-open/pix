defmodule Pix.SetupWizard do
  @moduledoc false

  @doc """
  Run the interactive setup wizard.
  Returns `{:ok, settings_map}` if the user completes or skips the wizard,
  or `:abort` if the user aborts.
  """
  @spec run() :: {:ok, map()} | :abort
  def run do
    Pix.IO.with_input(fn -> do_run() end)
  end

  defp do_run do
    welcome()

    if Pix.IO.ask_yes_no("Would you like to configure pix now?", true) do
      settings = configure()
      recap(settings)

      if Pix.IO.confirm("Save this configuration?") do
        {:ok, settings}
      else
        Pix.Report.info("\nConfiguration discarded.\n")
        :abort
      end
    else
      Pix.Report.info("\nSkipping setup. An empty configuration will be saved.\n")
      {:ok, empty_settings()}
    end
  end

  @doc """
  Save settings map to the user settings file.
  Creates the directory if it doesn't exist.
  """
  @spec save(map()) :: :ok
  def save(settings) do
    path = Pix.UserSettings.settings_path()
    dir = Path.dirname(path)

    File.mkdir_p!(dir)

    content = format_settings(settings)
    File.write!(path, content)

    Pix.IO.success("Settings saved to #{path}")
    :ok
  end

  # --- Private ---

  defp welcome do
    Pix.IO.banner("Pix Initial Setup Wizard", [
      "This wizard helps you configure default options for pix commands.\n",
      "Your settings will be saved to: ",
      :faint,
      Pix.UserSettings.settings_path(),
      :reset,
      "\n",
      "\nYou can re-run this wizard anytime with: ",
      :bright,
      "pix setup",
      :reset,
      "\n\n"
    ])
  end

  defp configure do
    ssh_opts = configure_ssh()
    output_opt = configure_output()
    progress_opt = configure_progress()

    build_settings(ssh_opts, output_opt, progress_opt)
  end

  defp configure_ssh do
    Pix.IO.section("SSH Forwarding")

    Pix.IO.note("SSH forwarding allows pipeline builds and shell sessions to access")
    Pix.IO.note("private git repositories, pull dependencies over SSH, or connect to")
    Pix.IO.note("remote hosts. The SSH agent or explicit keys from your host are")
    Pix.IO.note("forwarded into the build/shell container.")
    Pix.IO.note("")

    if Pix.IO.ask_yes_no("Enable SSH forwarding by default?", true) do
      configure_ssh_spec()
    else
      nil
    end
  end

  defp configure_ssh_spec do
    Pix.IO.note("SSH spec format:")
    Pix.IO.note("  \"default\"              - forward the default SSH agent")
    Pix.IO.note("  \"id=path/to/key\"       - forward a specific key file")
    Pix.IO.note("  \"id=socket_path\"       - forward a specific agent socket")
    Pix.IO.note("")

    choice =
      Pix.IO.ask_choice(
        "Which SSH forwarding mode?",
        [
          {:default, {"Forward default SSH agent (recommended)", :default}},
          {"Specify custom SSH spec(s)", :custom}
        ]
      )

    case choice do
      :default ->
        ["default"]

      :custom ->
        collect_ssh_specs([])
    end
  end

  defp collect_ssh_specs(acc) do
    spec = Pix.IO.ask_string("Enter SSH spec", validator: &validate_ssh_spec/1)
    specs = acc ++ [spec]

    if Pix.IO.ask_yes_no("Add another SSH spec?", false) do
      collect_ssh_specs(specs)
    else
      specs
    end
  end

  defp validate_ssh_spec(value) do
    cond do
      value == "" ->
        {:error, "SSH spec cannot be empty. Use \"default\" or \"id=path\"."}

      value == "default" ->
        :ok

      String.contains?(value, "=") ->
        :ok

      true ->
        {:error, "Invalid format. Expected \"default\" or \"id=<socket>|<key>[,<key>]\"."}
    end
  end

  defp configure_output do
    Pix.IO.section("Pipeline Output")

    Pix.IO.note("The --output flag extracts build artifacts from the pipeline to")
    Pix.IO.note("your local `#{Pix.Pipeline.output_dir()}` directory after a successful run.")
    Pix.IO.note("This is useful if you always want to inspect build results locally.")
    Pix.IO.note("")

    Pix.IO.ask_yes_no("Always enable --output by default?", false)
  end

  defp configure_progress do
    Pix.IO.section("Progress Output")

    Pix.IO.note("Controls how Docker BuildKit displays build progress.")
    Pix.IO.note("  auto    - automatic detection (default Docker behavior)")
    Pix.IO.note("  plain   - plain text output (good for CI or log capture)")
    Pix.IO.note("  tty     - rich TTY output with colors and progress bars")
    Pix.IO.note("  rawjson - raw JSON output for programmatic consumption")
    Pix.IO.note("")

    if Pix.IO.ask_yes_no("Customize progress output? (default is \"auto\")", false) do
      Pix.IO.ask_choice(
        "Select progress output type:",
        [
          {:default, {"auto - automatic detection", "auto"}},
          {"plain - plain text output", "plain"},
          {"tty - rich TTY output", "tty"},
          {"rawjson - raw JSON output", "rawjson"}
        ]
      )
    end
  end

  defp build_settings(ssh_specs, output?, progress) do
    run_cli_opts =
      []
      |> add_ssh_opts(ssh_specs)
      |> maybe_add_opt(:output, if(output?, do: true, else: nil))
      |> maybe_add_opt(:progress, progress)

    shell_cli_opts =
      []
      |> add_ssh_opts(ssh_specs)

    %{
      env: %{},
      command: %{
        run: %{cli_opts: run_cli_opts},
        shell: %{cli_opts: shell_cli_opts}
      }
    }
  end

  defp add_ssh_opts(opts, nil), do: opts
  defp add_ssh_opts(opts, specs), do: opts ++ Enum.map(specs, &{:ssh, &1})

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: opts ++ [{key, value}]

  defp recap(settings) do
    Pix.IO.section("Configuration Summary")

    Pix.IO.text("File: #{Pix.UserSettings.settings_path()}\n")
    Pix.IO.code_block(format_settings(settings), "settings.exs")
  end

  defp format_settings(settings) do
    inspect(settings, pretty: true, width: 80) <> "\n"
  end

  defp empty_settings do
    %{
      env: %{},
      command: %{
        run: %{cli_opts: []},
        shell: %{cli_opts: []}
      }
    }
  end
end
