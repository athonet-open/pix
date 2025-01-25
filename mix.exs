defmodule Pix.MixProject do
  use Mix.Project

  case System.cmd("git", ["describe", "--tags"], stderr_to_stdout: true) do
    {"v" <> version, 0} ->
      @version String.trim(version)

    _ ->
      case System.get_env("VERSION") do
        nil -> @version "0.0.0"
        "" -> @version "0.0.0"
        version -> @version String.trim(version)
      end
  end

  def project do
    [
      app: :pix,
      version: @version,
      elixir: "~> 1.18",
      deps: deps(),
      escript: [
        main_module: Pix,
        emu_args: "-noinput +B"
      ]
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
end
