defmodule Pix.UserSettings do
  @moduledoc """
  Pix user settings.

  You can set some global settings in your `~/.config/pix/settings.exs` file.

  The file should evaluate to a map conform to `t:t/0`.

  For example:

  ```elixir
  %{
    env: %{
      "PIX_DEBUG" => true
    },
    command: %{
      run: %{
        cli_opts: [
          ssh: true
        ]
      },
      shell: %{
        cli_opts: [
          ssh: true
        ]
      }
    }
  }
  ```
  """

  @enforce_keys [:env, :command]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          env: %{String.t() => String.t()},
          command: %{
            run: %{cli_opts: OptionParser.parsed()},
            shell: %{cli_opts: OptionParser.parsed()},
            graph: %{cli_opts: OptionParser.parsed()},
            ls: %{cli_opts: OptionParser.parsed()}
          }
        }

  @spec get :: t()
  def get do
    user_settings_path = Path.join(System.user_home!(), ".config/pix/settings.exs")

    user_settings =
      if File.regular?(user_settings_path) do
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
        }
      }
    }
  end
end
