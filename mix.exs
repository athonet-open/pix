defmodule Pix.MixProject do
  use Mix.Project

  def project() do
    [
      app: :pix,
      version: "0.0.0",
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
      extra_applications: [:logger]
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
