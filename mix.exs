defmodule Pix.MixProject do
  use Mix.Project

  def project do
    [
      app: :pix,
      version: version(),
      elixir: "~> 1.18",
      deps: deps(),
      escript: [
        main_module: Pix,
        emu_args: "-noinput +B"
      ],
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.16", only: [:dev], runtime: false},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      formatters: ["html"]
    ]
  end

  defp version do
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

    version =
      (env_version || git_tag || "v0.0.0")
      |> String.trim()
      |> String.trim_leading("v")

    File.write!("VERSION", version)

    version
  end
end
