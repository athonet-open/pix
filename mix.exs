defmodule Pix.MixProject do
  use Mix.Project

  def project do
    [
      app: :pix,
      version: "0.0.0",
      elixir: "~> 1.17",
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
      {:jason, "~> 1.0"},
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
end
