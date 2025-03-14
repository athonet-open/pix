defmodule Pix.Config do
  @moduledoc """
  Configuration module.
  """

  @type t() :: %{
          pipelines: %{
            pipeline_alias() => pipeline()
          }
        }
  @type pipeline() :: %{
          from: from(),
          default_args: args(),
          default_targets: [String.t()],
          ctx_dir: Path.t(),
          pipeline_mod: module()
        }
  @type pix_exs() :: %{
          pipelines: %{
            pipeline_alias() => pix_exs_pipeline()
          }
        }
  @type pix_exs_pipeline() :: %{
          from: from_path() | from_git(),
          default_args: args(),
          default_targets: [String.t()]
        }
  @type pipeline_alias :: String.t()
  @type arch() :: :noarch | supported_arch()
  @type supported_arch() :: :amd64 | :arm64
  @type from() :: from_path() | from_git()
  @type from_path() :: %{
          :path => Path.t(),
          optional(:sub_dir) => Path.t()
        }
  @type from_git() :: %{
          :git => String.t(),
          optional(:ref) => String.t(),
          optional(:sub_dir) => Path.t()
        }
  @type args() :: %{String.t() => String.t()}

  @spec get :: t()
  def get do
    pix_exs_path = ".pix.exs"

    if File.regular?(pix_exs_path) do
      mod = Pix.Helper.compile_file(pix_exs_path)
      pix_exs = validate_pix_exs(mod.project())

      Pix.Report.internal("Loaded project manifest\n")

      require_pipelines(pix_exs)
    else
      Pix.Report.error("Cannot find a #{pix_exs_path} file in the current working directory\n")
      System.halt(1)
    end
  end

  @spec pipeline_checkout_dir(repo :: String.t(), ref :: String.t()) :: Path.t()
  def pipeline_checkout_dir(repo, ref) do
    Path.join([".pipeline", "checkout", repo, ref])
  end

  @spec validate_pix_exs(map()) :: pix_exs()
  defp validate_pix_exs(pix_exs) do
    # TODO
    pix_exs
  end

  @spec require_pipelines(pix_exs()) :: t()
  defp require_pipelines(pix_exs) do
    # First fetch all git pipelines in parallel
    pix_exs.pipelines
    |> Stream.filter(&git_pipeline?/1)
    |> Stream.map(&extract_git_info/1)
    |> Stream.uniq()
    |> Task.async_stream(
      &get_git_pipeline(&1.uri, &1.ref),
      ordered: false,
      timeout: :infinity
    )
    |> Stream.run()

    # Map pipeline configurations to their implementations
    pipelines =
      Map.new(pix_exs.pipelines, fn {alias_, config} ->
        {ctx_dir, pipeline_mod} = require_pipeline_from(config.from)

        {alias_,
         %{
           from: config.from,
           default_args: config.default_args,
           default_targets: config.default_targets,
           ctx_dir: ctx_dir,
           pipeline_mod: pipeline_mod
         }}
      end)

    %{pipelines: pipelines}
  end

  @spec git_pipeline?({String.t(), map()}) :: boolean()
  defp git_pipeline?({_alias, %{from: %{git: _}}}), do: true
  defp git_pipeline?(_), do: false

  @spec extract_git_info({String.t(), map()}) :: %{uri: String.t(), ref: String.t()}
  defp extract_git_info({_alias, %{from: %{git: uri, ref: ref}}}) do
    %{uri: uri, ref: ref}
  end

  @spec get_git_pipeline(uri :: String.t(), ref :: String.t()) :: :ok
  defp get_git_pipeline(uri, ref) do
    checkout_dir = pipeline_checkout_dir(uri, ref)
    cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]

    if not File.dir?(checkout_dir) do
      Pix.Report.internal("Fetching remote git pipeline #{uri} (#{ref}) ... ")

      File.mkdir_p!(checkout_dir)

      case System.cmd("git", ["clone", "--depth", "1", "--branch", ref, uri, "."], cmd_opts) do
        {_, 0} ->
          :ok

        {err_msg, _} ->
          Pix.Report.internal("error\n\n")
          Pix.Report.error(err_msg)

          File.rm_rf!(checkout_dir)
          System.halt(1)
      end
    end

    :ok
  end

  @spec require_pipeline_from(from()) :: {ctx_dir :: Path.t(), pipeline_mod :: Pix.Pipeline.Project.t()}
  defp require_pipeline_from(from) do
    ctx_dir =
      case from do
        %{path: path} -> path
        %{git: uri, ref: ref} -> pipeline_checkout_dir(uri, ref)
      end

    pipeline_exs_dir = Path.join(ctx_dir, Map.get(from, :sub_dir, ""))
    pipeline_exs_path = Path.join(pipeline_exs_dir, "pipeline.exs")

    if not File.exists?(pipeline_exs_path) do
      Pix.Report.error("Pipeline specification '#{pipeline_exs_path}' file not found in #{inspect(from)}\n")

      System.halt(1)
    end

    pipeline_mod = Pix.Helper.compile_file(pipeline_exs_path)

    {ctx_dir, pipeline_mod}
  end
end
