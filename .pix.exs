defmodule Pix2Pix.Project do
  use Pix.Project

  @impl true
  def project do
    %{
      pipelines: %{
        "pix" => %{
          from: %{
            path: "."
          },
          default_args: %{},
          default_targets: [
            "pix.docs",
            "pix.credo",
            "pix.format",
            "pix.dialyzer",
            "pix.app"
          ]
        }
      }
    }
  end
end
