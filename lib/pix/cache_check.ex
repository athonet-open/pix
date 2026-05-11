defmodule Pix.CacheCheck do
  @moduledoc false

  @spec start(Pix.Config.t()) :: Task.t() | nil
  def start(config) do
    if enabled?() do
      Task.async(fn -> Pix.Command.Cache.outdated_pipelines(config) end)
    end
  end

  @spec maybe_notify(Task.t() | nil) :: :ok
  def maybe_notify(nil), do: :ok

  def maybe_notify(%Task{} = task) do
    case Task.yield(task, 0) do
      {:ok, [_ | _] = stale_pipelines} ->
        notify_stale(stale_pipelines)

      _ ->
        Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp enabled? do
    not Pix.Env.ci?() and System.get_env("PIX_DISABLE_CACHE_CHECK") != "true"
  end

  defp notify_stale(stale_pipelines) do
    box_width = 57

    header_rule = pad_right("─ Outdated pipelines ", "─", box_width)
    rule = pad_right("", "─", box_width)
    empty_line = pad_right("", box_width)

    pipeline_lines =
      stale_pipelines
      |> Enum.take(3)
      |> Enum.map(fn entry ->
        repo_name = repo_display_name(entry.path)

        [
          "│",
          pad_right(
            "  • #{repo_name}@#{entry.ref} (#{short_sha(entry.local_sha)} → #{short_sha(entry.remote_sha)})",
            box_width
          ),
          "│",
          "\n"
        ]
      end)

    more_line =
      if length(stale_pipelines) > 3 do
        [["│", pad_right("  ... and #{length(stale_pipelines) - 3} more", box_width), "│", "\n"]]
      else
        []
      end

    update_line = pad_right("  Run 'pix cache update' to update", box_width)

    IO.write(
      IO.ANSI.format([
        ["\n", :yellow],
        ["╭", header_rule, "╮", "\n"],
        ["│", empty_line, "│", "\n"],
        pipeline_lines,
        more_line,
        ["│", empty_line, "│", "\n"],
        ["│", update_line, "│", "\n"],
        ["╰", rule, "╯", "\n"]
      ])
    )
  end

  defp short_sha(sha), do: String.slice(sha, 0, 7)

  defp repo_display_name(path) do
    path
    |> Path.dirname()
    |> Path.basename()
    |> String.trim_trailing(".git")
  end

  defp pad_right(text, pad_char \\ " ", width) do
    padding = max(width - String.length(text), 0)
    text <> String.duplicate(pad_char, padding)
  end
end
