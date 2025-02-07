defmodule Pix.Pipeline do
  @moduledoc false

  @type run_cli_opts :: [
          {:arg, String.t()}
          | {:no_cache_filter, String.t()}
          | {:no_cache, boolean()}
          | {:output, boolean()}
          | {:progress, String.t()}
          | {:tag, String.t()}
          | {:target, String.t()}
        ]

  @type shell_cli_opts :: [
          {:host, boolean()}
          | {:target, String.t()}
        ]

  @spec run(Pix.Config.pipeline(), run_cli_opts()) :: :ok
  def run(pipeline_config, cli_opts) do
    %{
      from: from,
      default_targets: default_targets,
      default_args: default_args,
      ctx_dir: ctx_dir,
      pipeline_mod: pipeline_mod
    } = pipeline_config

    # Compile the pipeline
    pipeline = pipeline_mod.pipeline()

    # Pipeline targets
    targets = resolve_run_targets(default_targets, cli_opts)
    validate_run_targets!(pipeline, targets)
    pipeline_target = "#{pipeline.name}.pipeline"

    # Create combined Dockerfile
    pipeline_dockerfile = build_run_pipeline_dockerfile(pipeline, pipeline_target, targets)
    dockerfile_path = write_pipeline_files(pipeline_dockerfile, pipeline.dockerignore)

    # Run the build
    build_opts = run_build_options(cli_opts, pipeline, pipeline_target, from, ctx_dir, default_args)
    execute_run_build(build_opts, dockerfile_path, cli_opts, targets)

    :ok
  end

  @spec shell(Pix.Config.pipeline(), shell_cli_opts(), [String.t()]) :: :ok
  def shell(pipeline_config, cli_opts, cmd_args) do
    %{
      from: from,
      default_args: default_args,
      ctx_dir: ctx_dir,
      pipeline_mod: pipeline_mod
    } = pipeline_config

    pipeline = pipeline_mod.pipeline()
    validate_shell_capability!(pipeline_mod, pipeline.name)

    shell_from_target = Keyword.get(cli_opts, :target, :default)
    validate_shell_target!(pipeline, shell_from_target)

    shell_target = "#{pipeline.name}.shell"
    shell_docker_image = "pix/#{pipeline.name}/shell"

    # Build shell image
    pipeline = pipeline_mod.shell(pipeline, shell_target, shell_from_target)
    dockerfile_path = write_pipeline_files(Pix.Pipeline.SDK.dump(pipeline), pipeline.dockerignore)
    build_opts = shell_build_options(shell_target, shell_docker_image, from, ctx_dir, default_args, dockerfile_path)

    execute_shell_build(build_opts, shell_target)

    # Enter the shell
    enter_shell(shell_docker_image, shell_target, from, cli_opts, cmd_args)

    :ok
  end

  @spec resolve_run_targets([String.t()], run_cli_opts()) :: [String.t()]
  defp resolve_run_targets(default_targets, cli_opts) do
    case cli_opts[:target] do
      nil ->
        default_targets

      target ->
        [target]
    end
  end

  @spec validate_run_targets!(Pix.Pipeline.SDK.t(), [String.t()]) :: :ok
  defp validate_run_targets!(pipeline, targets) do
    known_public_targets = pipeline_targets(pipeline, :public)

    for target <- targets do
      if target not in known_public_targets do
        Pix.Log.error("Unknown target #{inspect(target)}\n")
        Pix.Log.error("Available run targets #{inspect(known_public_targets)}\n")
        System.halt(1)
      end
    end

    :ok
  end

  @spec build_run_pipeline_dockerfile(Pix.Pipeline.SDK.t(), String.t(), [String.t()]) :: String.t()
  defp build_run_pipeline_dockerfile(pipeline, pipeline_target, targets) do
    pipeline_run_stage =
      for target_id <- targets,
          stage = Enum.find(pipeline.stages, &(&1.stage == target_id)),
          outputs = if(stage.outputs == [], do: [nil], else: stage.outputs),
          output <- outputs,
          into: "FROM scratch AS #{pipeline_target}\n" do
        if output do
          "COPY --from=#{target_id} #{output} /#{Path.basename(output)}\n"
        else
          "COPY --from=#{target_id} /pix.nothing* /\n"
        end
      end

    Pix.Pipeline.SDK.dump(pipeline) <> "\n" <> pipeline_run_stage
  end

  @spec write_pipeline_files(String.t(), [String.t()]) :: Path.t()
  defp write_pipeline_files(dockerfile_content, dockerignore) do
    dockerfile_path = Path.join([System.tmp_dir!(), Pix.Helper.uuid()]) <> ".Dockerfile"
    File.write!(dockerfile_path, dockerfile_content)

    File.write!("#{dockerfile_path}.dockerignore", Enum.join(dockerignore, "\n"))

    dockerfile_path
  end

  @spec run_build_options(run_cli_opts(), Pix.Pipeline.SDK.t(), String.t(), Pix.Config.from(), Path.t(), map()) ::
          Pix.Docker.opts()
  defp run_build_options(cli_opts, pipeline, pipeline_target, from, ctx_dir, default_args) do
    no_cache_filter_opts =
      for(%{cache: false, stage: stage} <- pipeline.stages, do: {:"no-cache-filter", stage}) ++
        for {:no_cache_filter, filter} <- cli_opts, do: {:"no-cache-filter", filter}

    base_opts = [
      target: pipeline_target,
      progress: Keyword.get(cli_opts, :progress, "auto"),
      platform: "linux/#{Pix.Env.arch()}",
      build_context: "#{Pix.Pipeline.SDK.pipeline_ctx()}=#{ctx_dir}"
    ]

    cli_args = for {:arg, arg} <- cli_opts, do: arg

    base_opts
    |> add_run_output_option(cli_opts)
    |> add_run_tag_option(cli_opts)
    |> add_run_cache_options(cli_opts, no_cache_filter_opts)
    |> Kernel.++(pipeline_build_args(pipeline_target, from, default_args, cli_args))
  end

  @spec add_run_output_option(Pix.Docker.opts(), run_cli_opts()) :: Pix.Docker.opts()
  defp add_run_output_option(opts, cli_opts) do
    if cli_opts[:output] do
      File.rm_rf!(".pipeline/output")
      opts ++ [output: "type=local,dest=./.pipeline/output"]
    else
      opts
    end
  end

  @spec add_run_tag_option(Pix.Docker.opts(), run_cli_opts()) :: Pix.Docker.opts()
  defp add_run_tag_option(opts, cli_opts) do
    if cli_opts[:tag], do: opts ++ [:load, tag: cli_opts[:tag]], else: opts
  end

  @spec add_run_cache_options(Pix.Docker.opts(), run_cli_opts(), Pix.Docker.opts()) :: Pix.Docker.opts()
  defp add_run_cache_options(opts, cli_opts, no_cache_filter_opts) do
    if cli_opts[:no_cache], do: opts ++ [:"no-cache"], else: opts ++ no_cache_filter_opts
  end

  @spec execute_run_build(Pix.Docker.opts(), Path.t(), run_cli_opts(), [String.t()]) :: :ok
  defp execute_run_build(build_opts, dockerfile_path, cli_opts, targets) do
    Pix.Log.info("\nRunning pipeline (targets: #{inspect(targets)})\n\n")

    build_opts = Keyword.put(build_opts, :file, dockerfile_path)
    Pix.Docker.build(build_opts, ".") |> halt_on_error()

    if cli_opts[:output] do
      Pix.Log.info("\nExported pipeline outputs to .pipeline/output:\n")
      for f <- File.ls!(".pipeline/output"), do: Pix.Log.info("- #{f}\n")
    end

    :ok
  end

  @spec validate_shell_capability!(module(), String.t()) :: :ok
  defp validate_shell_capability!(pipeline_mod, pipeline_name) do
    unless function_exported?(pipeline_mod, :shell, 3) do
      Pix.Log.error("Pipeline #{pipeline_name} does not provide a shell")
      System.halt(1)
    end

    :ok
  end

  @spec validate_shell_target!(Pix.Pipeline.SDK.t(), :default | String.t()) :: :ok
  defp validate_shell_target!(pipeline, shell_from_target) do
    known_targets = pipeline_targets(pipeline, :all)

    if shell_from_target not in [:default | known_targets] do
      Pix.Log.error("Pipeline #{pipeline.name} does not define a #{shell_from_target} target\n")
      Pix.Log.error("Available shell targets #{inspect(known_targets)}\n")
      System.halt(1)
    end

    :ok
  end

  @spec shell_build_options(String.t(), String.t(), Pix.Config.from(), Path.t(), map(), Path.t()) :: Pix.Docker.opts()
  defp shell_build_options(shell_target, shell_docker_image, from, ctx_dir, default_args, dockerfile_path) do
    [
      :load,
      target: shell_target,
      file: dockerfile_path,
      build_context: "#{Pix.Pipeline.SDK.pipeline_ctx()}=#{ctx_dir}",
      tag: shell_docker_image
    ] ++ pipeline_build_args(shell_target, from, default_args, [])
  end

  @spec shell_run_options(String.t(), Pix.Config.from(), shell_cli_opts()) :: Pix.Docker.opts()
  defp shell_run_options(shell_target, from, cli_opts) do
    base_opts = [:privileged, :rm, :interactive, network: "host"]
    tty_opts = if Pix.Env.ci?(), do: [], else: [:tty]

    host_opts =
      if cli_opts[:host] do
        [volume: "#{File.cwd!()}:#{File.cwd!()}", workdir: File.cwd!()]
      else
        []
      end

    base_opts ++ tty_opts ++ host_opts ++ pipeline_envs(shell_target, from)
  end

  @spec execute_shell_build(Pix.Docker.opts(), String.t()) :: :ok
  defp execute_shell_build(build_opts, shell_target) do
    Pix.Log.info("\nBuilding pipeline (target=#{shell_target})\n\n")

    Pix.Docker.build(build_opts, ".")
    |> halt_on_error()

    :ok
  end

  @spec enter_shell(String.t(), String.t(), Pix.Config.from(), shell_cli_opts(), [String.t()]) :: :ok
  defp enter_shell(shell_docker_image, shell_target, from, cli_opts, cmd_args) do
    Pix.Log.info("\nEntering shell\n")

    opts = shell_run_options(shell_target, from, cli_opts)

    shell_docker_image
    |> Pix.Docker.run(opts, cmd_args)
    |> halt_on_error()

    :ok
  end

  @spec pipeline_targets(Pix.Pipeline.SDK.t(), visibility :: :all | :public) :: [String.t()]
  defp pipeline_targets(pipeline, visibility) do
    filter_stage =
      case visibility do
        :all -> Access.all()
        :public -> Access.filter(&(not &1.private))
      end

    get_in(pipeline, [Access.key!(:stages), filter_stage, Access.key!(:stage)])
  end

  @spec pipeline_envs(target :: String.t(), Pix.Config.from()) :: Pix.Docker.opts()
  defp pipeline_envs(target, from) do
    builtin_envs = pipeline_builtins_var(target, from)

    for {env_k, env_v} <- builtin_envs do
      {:env, "#{env_k}=#{env_v}"}
    end
  end

  @spec pipeline_build_args(target :: String.t(), Pix.Config.from(), Pix.Config.args(), cli_args :: [String.t()]) ::
          Pix.Docker.opts()
  defp pipeline_build_args(target, from, default_args, cli_args) do
    default_args = Map.merge(default_args, pipeline_builtins_var(target, from))

    build_args = for {arg_k, arg_v} <- default_args, do: {:build_arg, "#{arg_k}=#{arg_v}"}
    cli_build_args = for arg <- cli_args, do: {:build_arg, arg}

    build_args ++ cli_build_args
  end

  @spec pipeline_builtins_var(target :: String.t(), Pix.Config.from()) :: Pix.Config.args()
  defp pipeline_builtins_var(target, from) do
    base = %{
      "PIX_PROJECT_NAME" => Pix.Env.git_project_name(),
      "PIX_COMMIT_SHA" => Pix.Env.git_commit_sha(),
      "PIX_PIPELINE_TARGET" => target
    }

    from_vars =
      case from do
        %{path: path} ->
          %{
            "PIX_PIPELINE_FROM_PATH" => path,
            "PIX_PIPELINE_FROM_SUB_DIR" => Map.get(from, :sub_dir, "")
          }

        %{git: repo} ->
          %{
            "PIX_PIPELINE_FROM_GIT_REPO" => repo,
            "PIX_PIPELINE_FROM_GIT_REF" => Map.get(from, :ref, ""),
            "PIX_PIPELINE_FROM_GIT_SUB_DIR" => Map.get(from, :sub_dir, "")
          }
      end

    Map.merge(base, from_vars)
  end

  @spec halt_on_error(non_neg_integer()) :: :ok
  defp halt_on_error(0), do: :ok
  defp halt_on_error(status), do: System.halt(status)
end
