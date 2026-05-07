defmodule Pix.UpgradeCheck do
  @moduledoc false

  @github_user_repo "athonet-open/pix"

  @spec start() :: Task.t() | nil
  def start do
    if enabled?() do
      Task.async(&get_latest_version_from_github/0)
    end
  end

  @spec maybe_notify(Task.t() | nil) :: :ok
  def maybe_notify(nil), do: :ok

  def maybe_notify(%Task{} = task) do
    case Task.yield(task, 0) do
      {:ok, {:ok, latest_version}} ->
        current_version = Application.fetch_env!(:pix, :version)

        if Version.compare(latest_version, current_version) == :gt do
          notify_upgrade(current_version, latest_version)
        end

      _ ->
        Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  @spec get_latest_version_from_github() :: {:ok, String.t()} | {:error, term()}
  def get_latest_version_from_github do
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

  defp enabled? do
    not Pix.Env.ci?() and System.get_env("PIX_DISABLE_UPGRADE_CHECK") != "true"
  end

  defp notify_upgrade(current_version, latest_version) do
    box_width = 57

    version_line = pad_right("  v#{current_version} → v#{latest_version}", box_width)
    upgrade_line = pad_right("  Run 'pix upgrade' to update", box_width)
    empty_line = pad_right("", box_width)
    header_rule = pad_right("─ Upgrade available ", "─", box_width)
    rule = pad_right("", "─", box_width)

    IO.write(
      IO.ANSI.format([
        ["\n", :yellow],
        ["╭", header_rule, "╮", "\n"],
        ["│", empty_line, "│", "\n"],
        ["│", version_line, "│", "\n"],
        ["│", empty_line, "│", "\n"],
        ["│", upgrade_line, "│", "\n"],
        ["╰", rule, "╯", "\n"]
      ])
    )
  end

  defp pad_right(text, pad_char \\ " ", width) do
    padding = max(width - String.length(text), 0)
    text <> String.duplicate(pad_char, padding)
  end
end
