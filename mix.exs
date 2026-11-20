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
      dialyzer: [flags: [:no_opaque]],
      docs: docs()
    ]
  end

  def application do
    [
      # Embeds Mix in the escript: the Mix API (e.g. `Mix.Project.in_project/4`) is available to
      # .pix.exs and pipeline.exs without depending on the Elixir installed on the host.
      extra_applications: [:logger, :inets, :ssl, :mix]
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
      extras: ["README.md", "guides/pipeline-authoring.md"],
      formatters: ["html"],
      groups_for_extras: [
        Guides: ["guides/pipeline-authoring.md"]
      ],
      groups_for_modules: [
        "Pipeline Authoring": [
          Pix.Pipeline.SDK,
          Pix.Pipeline.SDK.Stage,
          Pix.Pipeline.SDK.Extra,
          Pix.Pipeline.Project,
          Pix.Pipeline.Spec.Input
        ],
        "Project Configuration": [
          Pix.Project,
          Pix.Config,
          Pix.UserSettings
        ],
        Environment: [
          Pix.Env
        ]
      ],
      nest_modules_by_prefix: [
        Pix.Pipeline
      ]
    ]
  end
end
