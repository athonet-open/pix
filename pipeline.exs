defmodule Pix2Pix.Pipeline do
  use Pix.Pipeline.Project
  import Pix.Pipeline.SDK

  @external_resource "Dockerfile"

  @elixir_image_tag Regex.named_captures(~r"ARG ELIXIR_VERSION=(?<version>.*)", File.read!("Dockerfile"))["version"]
  @workdir "/build"

  @impl true
  def pipeline do
    pipeline("pix", description: "Pix pipeline for Pix")
    |> stage_toolchain()
    |> stage_deps_get()
    |> stage_deps("dev")
    |> stage_deps("prod")
    |> stage_compile("dev")
    |> stage_compile("prod")
    |> stage_dialyzer_plt()
    |> stage_dialyzer()
    |> stage_format()
    |> stage_credo()
    |> stage_docs()
    |> stage_escript()
    |> stage_app()
  end

  @impl true
  def shell(pipeline, shell_stage, from_target) do
    from_target = if from_target == :default, do: "pix.toolchain", else: from_target

    pipeline
    |> stage(shell_stage, from: from_target, private: true)
    |> run("git config --global --add safe.directory '*'")
    |> entrypoint([])
    |> cmd(["bash"])
  end

  defp stage_toolchain(pipeline) do
    pipeline
    |> stage("pix.toolchain", from: "docker.io/hexpm/elixir:#{@elixir_image_tag}", private: true)
    |> workdir(@workdir)
    |> run("apk add --no-cache git bash build-base")
  end

  defp stage_deps_get(pipeline) do
    pipeline
    |> stage("pix.deps_get", from: "pix.toolchain", private: true)
    |> copy("mix.exs", ".")
    |> copy("mix.lock", ".")
    |> run("mix deps.get --check-locked")
    |> run("mix deps.unlock --check-unused")
  end

  defp stage_deps(pipeline, mix_env) do
    pipeline
    |> stage("pix.deps_#{mix_env}", from: "pix.deps_get", private: true)
    |> env(MIX_ENV: mix_env)
    |> run("mix deps.compile")
  end

  defp stage_compile(pipeline, mix_env) do
    pipeline
    |> stage("pix.compile_#{mix_env}", from: "pix.deps_#{mix_env}", private: true)
    |> copy("config", "./config")
    |> copy("lib", "./lib")
    |> copy("shell_completions", "./shell_completions")
    |> run("mix compile --warnings-as-errors")
  end

  defp stage_dialyzer_plt(pipeline) do
    pipeline
    |> stage("pix.dialyzer_plt", from: "pix.deps_dev", private: true)
    |> run("mix dialyzer --plt")
  end

  defp stage_dialyzer(pipeline) do
    pipeline
    |> stage("pix.dialyzer", from: "pix.compile_dev", description: "Run Dialyzer static analysis")
    |> copy("#{@workdir}/_build/dev/dialyxir_*", "./_build/dev/", from: "pix.dialyzer_plt")
    |> run("mix dialyzer --no-check")
  end

  defp stage_format(pipeline) do
    pipeline
    |> stage("pix.format", from: "pix.compile_dev", description: "Check code formatting")
    |> copy(".formatter.exs", ".")
    |> run("mix format --check-formatted")
  end

  defp stage_credo(pipeline) do
    pipeline
    |> stage("pix.credo", from: "pix.compile_dev", description: "Run Credo static analysis")
    |> copy(".credo.exs", ".")
    |> run("mix credo --strict --all")
  end

  defp stage_docs(pipeline) do
    pipeline
    |> stage("pix.docs", from: "pix.compile_dev", description: "Generate ExDoc documentation")
    |> copy("README.md", ".")
    |> run("mix docs")
    |> output("#{@workdir}/doc")
  end

  defp stage_escript(pipeline) do
    pipeline
    |> stage("pix.escript", from: "pix.compile_prod", private: true, description: "Build Pix escript")
    |> arg("VERSION")
    |> run("VERSION=${VERSION} mix escript.build")
  end

  defp stage_app(pipeline) do
    pipeline
    |> stage("pix.app", from: "docker.io/hexpm/elixir:#{@elixir_image_tag}", description: "Build Pix Docker image")
    |> run("""
      apk add --no-cache \
          bash \
          ca-certificates \
          coreutils \
          docker-cli \
          docker-cli-buildx \
          git
    """)
    |> copy("#{@workdir}/pix", "/usr/local/bin/pix", from: "pix.escript")
    |> entrypoint(["/usr/local/bin/pix"])
  end
end
