defmodule Pix.UserSettings do
  @moduledoc """
  Pix user settings.

  You can set some global settings in your `~/.config/pix/settings.exs` file.
  The file should evaluate to a map conform to `t:t/0`.

  See the pix help command for a list of environment variables that can be set in the `env`
  section of the user settings, and the documentation of each command for the available `cli_opts`
  that can be set for each command.

  For example:

  ```elixir
  %{
    env: %{
      "PIX_DEBUG" => "true"
    },
    command: %{
      run: %{
        cli_opts: [
          ssh: "default"
        ]
      },
      shell: %{
        cli_opts: [
          ssh: "default"
        ]
      }
    }
  }
  ```
  """

  @enforce_keys [:env, :command]
  defstruct @enforce_keys

  @typedoc "User settings loaded from `~/.config/pix/settings.exs`."
  @type t() :: %__MODULE__{
          env: %{String.t() => String.t()},
          command: %{
            run: %{cli_opts: OptionParser.parsed()},
            shell: %{cli_opts: OptionParser.parsed()},
            graph: %{cli_opts: OptionParser.parsed()},
            ls: %{cli_opts: OptionParser.parsed()},
            upgrade: %{cli_opts: OptionParser.parsed()}
          }
        }

  @doc false
  @spec get :: t()
  def get do
    user_settings_path = Path.join(System.user_home!(), ".config/pix/settings.exs")

    user_settings =
      if File.regular?(user_settings_path) do
        Pix.Report.internal("Loading user settings from #{user_settings_path}\n")
        {user_settings, _} = Pix.Helper.eval_file(user_settings_path)
        user_settings
      else
        %{}
      end

    %__MODULE__{
      env: get_in(user_settings[:env]) || %{},
      command: %{
        run: %{
          cli_opts: get_in(user_settings[:command][:run][:cli_opts]) || []
        },
        shell: %{
          cli_opts: get_in(user_settings[:command][:shell][:cli_opts]) || []
        },
        graph: %{
          cli_opts: get_in(user_settings[:command][:graph][:cli_opts]) || []
        },
        ls: %{
          cli_opts: get_in(user_settings[:command][:ls][:cli_opts]) || []
        },
        upgrade: %{
          cli_opts: get_in(user_settings[:command][:upgrade][:cli_opts]) || []
        }
      }
    }
  end
end
