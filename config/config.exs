import Config

version = fn ->
  git_tag =
    case System.cmd("git", ["describe", "--tags", "--abbrev"]) do
      {git_tag, 0} -> git_tag
      _ -> nil
    end

  env_version =
    case System.get_env("VERSION", nil) do
      nil -> nil
      "" -> nil
      env_version -> env_version
    end

  (env_version || git_tag || "v0.0.0")
  |> String.trim()
  |> String.trim_leading("v")
end

config :pix, version: version.()
