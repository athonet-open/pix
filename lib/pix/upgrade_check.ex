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

  @spec get_latest_version_from_github() :: {:ok, String.t()} | {:error, term()} | nil
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

      {:ok, {{_, status, _}, _headers, _body}} ->
        Pix.Report.internal("Upgrade check failed: HTTP #{status}")
        nil

      {:error, reason} ->
        Pix.Report.internal("Upgrade check failed: #{inspect(reason)}")
        nil
    end
  end

  defp enabled? do
    not Pix.Env.ci?() and System.get_env("PIX_DISABLE_UPGRADE_CHECK") != "true"
  end

  defp notify_upgrade(current_version, latest_version) do
    Pix.IO.notify_box("Pix upgrade available", [
      "  v#{current_version} → v#{latest_version}",
      "",
      "  Run 'pix upgrade' to update"
    ])
  end
end
