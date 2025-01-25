#!/usr/bin/env -S elixir --erl -noinput --erl +B

Mix.install([], elixir: "~> 1.18")

defmodule Pix.Project do
  @moduledoc """
  Defines Pix projects.

  A Pix project is defined by calling `use Pix.Project` in a module placed in `.pix.exs`:

    defmodule MyApp.Pix.Project do
      use Pix.Project

      @impl true
      def project() do
        %{
          pipelines: %{
            "elixir" => %{
              # ...
            },
            "deploy_aws" => %{
              # ...
            },
            # ...
          }
        }
      end
    end

  Module defining a `Pix.Project` should implement the `c:project/0` callback.

  ## Project configuration

  The project configuration, returned by `c:project/1`, should conform to a `t:Pix.Config.pix_exs/0` map.

  Here it's possible to define a set of names pipelines (ie. `"elixir"`, `"docs"`, ...):

    %{
      pipelines: %{
        "elixir" => %{
          # ...
        },
        "deploy_aws" => %{
          # ...
        }
      }
    }

  where every pipeline point defines the source, arguments and targets:

    %{
      pipelines: %{
        "elixir" => %{
          from: %{git: "git@github.com:user/group/repo.git", ref: "v1.0", subdir: "pipeline/elixir"},
          default_args: %{
            "ELIXIR_APP_NAME" => "..."
          },
          default_targets: [
            "elixir.format",
            "elixir.credo",
            "elixir.dialyzer",
            "elixir.test",
            "elixir.app",
            ...
          ]
        }
      }
    }

  ## TODO from / default_args / default_targets description
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @callback project() :: Pix.Config.pix_exs()
end

defmodule Pix.PipelineProject do
  @moduledoc """
  TODO
  """

  @type t() :: module()

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
    end
  end

  @callback pipeline() :: Pix.PipelineSDK.t()
  @callback shell(Pix.PipelineSDK.t(), shell_stage :: String.t(), from_target :: String.t() | :default) ::
              Pix.PipelineSDK.t()
  @optional_callbacks shell: 3
end

defmodule Pix.PipelineSDK do
  @moduledoc """
  Provides APIs for building Dockerfiles pipelines programmatically.
  """

  @type command :: String.t()
  @type options :: Keyword.t()
  @type iargs :: [String.t(), ...]
  @type instruction :: {command(), options(), iargs()}
  @type args() :: %{(name :: String.t()) => default_value :: nil | String.t()}
  @type stage :: %{
          stage: String.t(),
          instructions: [instruction()],
          args_: args(),
          outputs: [Path.t()],
          private: boolean(),
          cache: boolean()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          args: [instruction()],
          stages: [stage()],
          args_: args(),
          dockerignore: [String.t()]
        }

  @enforce_keys [:name]
  defstruct @enforce_keys ++ [description: "", args: [], stages: [], args_: %{}, dockerignore: []]

  @doc """
  Build context name of the pipeline ctx directory.

  `#{inspect(__MODULE__)}.copy("foo.sh", ".", from: #{inspect(__MODULE__)}.pipeline_ctx())`
  """
  @spec pipeline_ctx() :: String.t()
  def pipeline_ctx(), do: "pipeline_ctx"

  @doc """
  Creates a new pipeline.
  """
  @spec pipeline(name :: String.t(), [{:description, String.t()} | {:dockerignore, [String.t()]}]) :: t()
  def pipeline(name, options) do
    options = Keyword.validate!(options, description: "", dockerignore: [])

    %__MODULE__{
      name: name,
      description: options[:description],
      dockerignore: options[:dockerignore]
    }
  end

  @doc """
  Starts a new stage [`FROM`](https://docs.docker.com/reference/dockerfile/#from) the given base image.
  """
  @spec stage(t(), stage_name :: String.t(), [{:from, String.t()} | {:private, boolean()} | {:cache, boolean()}]) :: t()
  def stage(%__MODULE__{stages: stages} = dockerfile, stage_name, options \\ []) do
    options = Keyword.validate!(options, from: "scratch", private: false, cache: true)

    new_stage = %{
      stage: stage_name,
      private: options[:private],
      cache: options[:cache],
      args_: %{},
      outputs: [],
      instructions: []
    }

    %__MODULE__{dockerfile | stages: [new_stage | stages]}
    |> append_instruction("FROM", ["#{options[:from]} AS #{stage_name}"])
  end

  @doc """
  Declare a stage output artifact
  """
  @spec output(t(), Path.t() | [Path.t(), ...]) :: t()
  def output(%__MODULE__{} = dockerfile, path) do
    {_, dockerfile} =
      get_and_update_in(dockerfile, [Access.key!(:stages), Access.at!(0), :outputs], &{&1, &1 ++ List.wrap(path)})

    dockerfile
  end

  @doc """
  Adds a [`RUN`](https://docs.docker.com/reference/dockerfile/#run) instruction.
  """
  @spec run(t(), command :: String.t() | [String.t(), ...], options()) :: t()
  def run(%__MODULE__{} = dockerfile, command, options \\ []) do
    append_instruction(dockerfile, "RUN", options, shell_or_exec_form(command))
  end

  @doc """
  Adds a [`CMD`](https://docs.docker.com/reference/dockerfile/#cmd) instruction.
  """
  @spec cmd(t(), command :: String.t() | [String.t()]) :: t()
  def cmd(%__MODULE__{} = dockerfile, command) do
    append_instruction(dockerfile, "CMD", [], shell_or_exec_form(command))
  end

  @doc """
  Adds a [`LABEL`](https://docs.docker.com/reference/dockerfile/#label) instruction.
  """
  @spec label(t(), labels :: Enumerable.t({String.t(), String.t()})) :: t()
  def label(%__MODULE__{} = dockerfile, labels) do
    labels = Enum.map(labels, fn {k, v} -> "#{inspect(k)}=#{inspect(v)}" end)
    append_instruction(dockerfile, "LABEL", [], labels)
  end

  @doc """
  Adds a [`EXPOSE`](https://docs.docker.com/reference/dockerfile/#expose) instruction.
  """
  @spec expose(t(), port :: String.t()) :: t()
  def expose(%__MODULE__{} = dockerfile, port) do
    append_instruction(dockerfile, "EXPOSE", [], [port])
  end

  @doc """
  Adds a [`ENV`](https://docs.docker.com/reference/dockerfile/#env) instruction.
  """
  @spec env(t(), envs :: Enumerable.t({String.t() | atom(), String.t()})) :: t()
  def env(%__MODULE__{} = dockerfile, envs) do
    envs = Enum.map(envs, fn {k, v} -> "#{k}=#{inspect(v)}" end)
    append_instruction(dockerfile, "ENV", [], envs)
  end

  @doc """
  Adds a [`ADD`](https://docs.docker.com/reference/dockerfile/#add) instruction.
  """
  @spec add(t(), source :: String.t() | [String.t(), ...], destination :: String.t(), options()) ::
          t()
  def add(%__MODULE__{} = dockerfile, source, destination, options \\ []) do
    append_instruction(dockerfile, "ADD", options, List.wrap(source) ++ [destination])
  end

  @doc """
  Adds a [`COPY`](https://docs.docker.com/reference/dockerfile/#copy) instruction.
  """
  @spec copy(t(), source :: String.t() | [String.t(), ...], destination :: String.t(), options()) ::
          t()
  def copy(%__MODULE__{} = dockerfile, source, destination, options \\ []) do
    append_instruction(dockerfile, "COPY", options, List.wrap(source) ++ [destination])
  end

  @doc """
  Adds a [`ENTRYPOINT`](https://docs.docker.com/reference/dockerfile/#entrypoint) instruction.
  """
  @spec entrypoint(t(), command :: String.t() | [String.t()]) :: t()
  def entrypoint(%__MODULE__{} = dockerfile, command) do
    append_instruction(dockerfile, "ENTRYPOINT", [], shell_or_exec_form(command))
  end

  @doc """
  Adds a [`VOLUME`](https://docs.docker.com/reference/dockerfile/#volume) instruction.
  """
  @spec volume(t(), volume :: String.t() | [String.t(), ...]) :: t()
  def volume(%__MODULE__{} = dockerfile, volume) do
    append_instruction(dockerfile, "VOLUME", [], shell_or_exec_form(volume))
  end

  @doc """
  Adds a [`USER`](https://docs.docker.com/reference/dockerfile/#user) instruction.
  """
  @spec user(t(), user :: String.t()) :: t()
  def user(%__MODULE__{} = dockerfile, user) do
    append_instruction(dockerfile, "USER", [], [user])
  end

  @doc """
  Adds a [`WORKDIR`](https://docs.docker.com/reference/dockerfile/#workdir) instruction.
  """
  @spec workdir(t(), workdir :: String.t()) :: t()
  def workdir(%__MODULE__{} = dockerfile, workdir) do
    append_instruction(dockerfile, "WORKDIR", [], [workdir])
  end

  @doc """
  Adds a [`ARG`](https://docs.docker.com/reference/dockerfile/#arg) instruction in the global scope.
  """
  @spec global_arg(t(), name :: String.t() | atom(), default_value :: nil | String.t()) :: t()
  def global_arg(%__MODULE__{} = dockerfile, name, default_value \\ nil) do
    iargs =
      if default_value == nil do
        [to_string(name)]
      else
        ["#{name}=#{inspect(default_value)}"]
      end

    args = [{"ARG", [], iargs} | dockerfile.args]
    args_ = Map.put(dockerfile.args_, name, default_value)

    %__MODULE__{dockerfile | args: args, args_: args_}
  end

  @doc """
  Adds a [`ARG`](https://docs.docker.com/reference/dockerfile/#arg) instruction in a stage scope.
  """
  @spec arg(t(), name :: String.t() | atom(), default_value :: nil | String.t()) :: t()
  def arg(%__MODULE__{} = dockerfile, name, default_value \\ nil) do
    iargs =
      if default_value == nil do
        [to_string(name)]
      else
        ["#{name}=#{inspect(default_value)}"]
      end

    dockerfile = append_instruction(dockerfile, "ARG", [], iargs)

    {_, dockerfile} =
      get_and_update_in(
        dockerfile,
        [Access.key!(:stages), Access.at!(0), :args_],
        &{&1, Map.put(&1, name, default_value)}
      )

    dockerfile
  end

  @doc """
  Adds a [`STOPSIGNAL`](https://docs.docker.com/reference/dockerfile/#stopsignal) instruction.
  """
  @spec stopsignal(t(), name :: String.t()) :: t()
  def stopsignal(%__MODULE__{} = dockerfile, signal) do
    append_instruction(dockerfile, "STOPSIGNAL", [], [signal])
  end

  @doc """
  Adds a [`SHELL`](https://docs.docker.com/reference/dockerfile/#shell) instruction.
  """
  @spec shell(t(), command :: [String.t(), ...]) :: t()
  def shell(%__MODULE__{} = dockerfile, command) do
    append_instruction(dockerfile, "SHELL", [], command)
  end

  @doc """
  Adds a [`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck) instruction.
  """
  @spec healthcheck(t(), command :: nil | String.t() | [String.t(), ...], options :: options()) ::
          t()
  def healthcheck(%__MODULE__{} = dockerfile, command, options \\ []) do
    if command == nil do
      append_instruction(dockerfile, "HEALTHCHECK", [], ["NONE"])
    else
      command = shell_or_exec_form(command)
      append_instruction(dockerfile, "HEALTHCHECK", options, ["CMD" | command])
    end
  end

  @doc false
  @spec append_instruction(t(), command(), options(), iargs()) :: t()
  def append_instruction(dockerfile, command, options \\ [], iargs)

  def append_instruction(%__MODULE__{stages: []}, _, _, _) do
    raise("No stage defined. Use `stage/3` to start a stage first.")
  end

  def append_instruction(
        %__MODULE__{stages: [stage | rest_stages]} = dockerfile,
        command,
        options,
        iargs
      ) do
    stage = %{stage | instructions: [{command, options, iargs} | stage.instructions]}
    %__MODULE__{dockerfile | stages: [stage | rest_stages]}
  end

  @doc """
  Converts the Dockerfile into a string representation.
  """
  @spec dump(t()) :: String.t()
  def dump(%__MODULE__{args: args, stages: stages}) do
    global_args_string =
      args
      |> Enum.reverse()
      |> Enum.map_join("\n", &serialize_instruction/1)

    stages_string =
      stages
      |> Enum.reverse()
      |> Enum.map_join("\n\n", &serialize_stage/1)

    global_args_string <> "\n\n" <> stages_string
  end

  @spec shell_or_exec_form(String.t() | [String.t()]) :: iargs()
  defp shell_or_exec_form(command) do
    case command do
      command when is_list(command) ->
        ["[#{Enum.map_join(command, ", ", &inspect/1)}]"]

      command ->
        [command]
    end
  end

  @spec serialize_stage(stage()) :: String.t()
  defp serialize_stage(%{instructions: instructions}) do
    instructions
    |> Enum.reverse()
    |> Enum.map_join("\n", &serialize_instruction/1)
  end

  @spec serialize_instruction(instruction()) :: String.t()
  defp serialize_instruction({command, options, iargs}) do
    options_str = Enum.map_join(options, " ", fn {key, value} -> "--#{key}=#{inspect(value)}" end)
    args_str = Enum.join(iargs, " ")

    [command, options_str, args_str]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end
end

defmodule Pix.Env do
  @moduledoc """
  Environment information.
  """

  @spec ci?() :: boolean()
  def ci?(), do: System.get_env("CI", "") != ""

  @spec arch() :: Pix.Config.supported_arch() | (forced_arch :: atom())
  def arch() do
    case System.get_env("PIX_FORCE_PLATFORM_ARCH") do
      nil ->
        case to_string(:erlang.system_info(:system_architecture)) do
          "amd64" <> _ -> :amd64
          "x86_64" <> _ -> :amd64
          "arm64" <> _ -> :arm64
          "aarch64" <> _ -> :arm64
        end

      forced_arch ->
        String.to_atom(forced_arch)
    end
  end

  @spec git_commit_sha() :: String.t()
  def git_commit_sha() do
    {res, 0} = System.cmd("git", ~w[rev-parse HEAD])
    String.trim(res)
  end

  @spec git_project_name() :: String.t()
  def git_project_name() do
    {res, 0} = System.cmd("git", ~w[rev-parse --show-toplevel])
    res = String.trim(res)

    Path.basename(res)
  end
end

defmodule Pix.Helper do
  @moduledoc false

  @spec uuid() :: String.t()
  def uuid() do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end

  @spec compile_file(Path.t()) :: module()
  def compile_file(path) do
    case Code.with_diagnostics(fn -> Code.compile_file(path) end) do
      # accept exactly one module per file
      {[{module, _}], []} ->
        module

      {_, warnings} when warnings != [] ->
        Pix.Log.error("Failed to compile #{path} due to warnings:\n\n")

        for %{message: msg, position: {line, col}, severity: :warning} <- warnings,
            do: Pix.Log.error("warning: #{msg}\n  at line #{line}, column #{col}\n\n")

        System.halt(1)

      _ ->
        raise "Expected #{path} to define exactly one module per file"
    end
  rescue
    err ->
      Pix.Log.error("Failed to compile #{path} due to errors:\n\n")
      Pix.Log.error(Exception.format(:error, err, __STACKTRACE__))
      Pix.Log.error("\n")
      System.halt(1)
  end
end

defmodule Pix.Log do
  @moduledoc false

  @spec info(IO.chardata()) :: :ok
  def info(msg), do: IO.write(msg)

  @spec error(IO.chardata()) :: :ok
  def error(msg), do: IO.write(IO.ANSI.format([:red, msg]))

  @spec internal(IO.chardata()) :: :ok
  def internal(msg), do: IO.write(IO.ANSI.format([:faint, msg]))
end

defmodule Pix.System do
  @moduledoc false

  # Ref: https://hexdocs.pm/elixir/Port.html#module-zombie-operating-system-processes
  @cmd_wrapper """
  #!/usr/bin/env bash

  # Start the program in the background
  exec "$@" &
  pid1=$!

  # Silence warnings from here on
  exec >/dev/null 2>&1

  # Read from stdin in the background and
  # kill running program when stdin closes
  exec 0<&0 $(
    while read; do :; done
    kill -KILL $pid1
  ) &
  pid2=$!

  # Clean up
  wait $pid1
  ret=$?
  kill -KILL $pid2
  exit $ret
  """

  @spec setup() :: :ok
  def setup() do
    install_cmd_wrapper_script()
  end

  @spec install_cmd_wrapper_script :: :ok
  defp install_cmd_wrapper_script do
    path = Path.join(System.tmp_dir!(), "cmd_wrapper.sh")

    File.write!(path, @cmd_wrapper)
    File.chmod!(path, 0o700)

    :persistent_term.put({:pix, :cmd_wrapper_path}, path)

    :ok
  end

  @spec cmd_wrapper_path :: Path.t()
  def cmd_wrapper_path do
    :persistent_term.get({:pix, :cmd_wrapper_path})
  end
end

defmodule Pix.Docker do
  @moduledoc false

  @buildkit_version "v0.19.0"

  @docker_desktop_socket "/run/host-services/ssh-auth.sock"
  @type opts() :: [Keyword.key() | {Keyword.key(), Keyword.value()}]

  @spec buildx_builder() :: String.t()
  defp buildx_builder(), do: "pix-#{Pix.version()}-buildkit-#{@buildkit_version}-builder"

  @spec setup_buildx() :: :ok
  def setup_buildx() do
    assert_docker_installed()

    Pix.Log.internal("Setup docker buildx builder (#{buildx_builder()}, buildkit #{@buildkit_version}) ... ")

    case System.cmd("docker", ["buildx", "inspect", "--builder", buildx_builder()], stderr_to_stdout: true) do
      {_, 0} ->
        Pix.Log.internal("already present\n")

      _ ->
        opts = ["--driver", "docker-container", "--driver-opt", "image=moby/buildkit:#{@buildkit_version}"]
        {_, 0} = System.cmd("docker", ["buildx", "create", "--name", buildx_builder() | opts])

        Pix.Log.internal("created\n")
    end

    :ok
  end

  @spec version() :: map()
  def version() do
    {json, 0} = System.cmd("docker", ~w[version --format json])
    JSON.decode!(json)
  end

  @spec run(image :: String.t(), opts(), cmd_args :: [String.t()]) :: status :: non_neg_integer()
  def run(image, opts, cmd_args) do
    opts = opts ++ run_opts_ssh_forward() ++ run_opts_docker_outside_of_docker()
    args = ["run"] ++ opts_encode(opts) ++ [image] ++ cmd_args

    if System.get_env("PIX_DEBUG") == "true" do
      Pix.Log.internal("docker #{inspect(args)}")
    end

    debug_docker(opts, args)

    port_opts = [:nouse_stdio, :exit_status, args: args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, exit_status}} -> exit_status
    end
  end

  @spec run_opts_ssh_forward() :: opts()
  defp run_opts_ssh_forward() do
    ssh_sock =
      cond do
        :os.type() == {:unix, :darwin} ->
          Pix.Log.internal(">>> detected Darwin OS - assuming 'docker desktop' environment for SSH socket forwarding\n")
          @docker_desktop_socket

        System.get_env("SSH_AUTH_SOCK") == nil ->
          Pix.Log.internal(">>> SSH socket NOT forwarded\n")
          nil

        true ->
          ssh_auth_sock = System.get_env("SSH_AUTH_SOCK", "")
          Pix.Log.internal(">>> forwarding SSH socket via #{inspect(ssh_auth_sock)}\n")
          ssh_auth_sock
      end

    if ssh_sock do
      [env: "SSH_AUTH_SOCK=#{ssh_sock}", volume: "#{ssh_sock}:#{ssh_sock}"]
    else
      []
    end
  end

  @spec run_opts_docker_outside_of_docker() :: opts()
  defp run_opts_docker_outside_of_docker() do
    docker_socket = "/var/run/docker.sock"
    Pix.Log.internal(">>> Supporting docker outside-of docker via socket mount (#{docker_socket})\n")
    [volume: "#{docker_socket}:#{docker_socket}"]
  end

  @spec build(opts(), String.t()) :: exit_status :: non_neg_integer()
  def build(opts, ctx) do
    opts = [builder: buildx_builder(), ssh: "default"] ++ opts
    args = [System.find_executable("docker"), "buildx", "build"] ++ opts_encode(opts) ++ [ctx]

    debug_docker(opts, args)

    {_, exit_status} = System.cmd(Pix.System.cmd_wrapper_path(), args)

    exit_status
  end

  defp assert_docker_installed() do
    case System.cmd("docker", ["info", "--format", "json"], stderr_to_stdout: true) do
      {info, 0} ->
        info = JSON.decode!(info)
        Pix.Log.internal("Running on #{info["Name"]} #{info["OSType"]}-#{info["Architecture"]} ")
        Pix.Log.internal("(client #{info["ClientInfo"]["Version"]}, ")
        Pix.Log.internal("server #{info["ServerVersion"]} experimental_build=#{info["ExperimentalBuild"]})\n")

      {err, _} ->
        Pix.Log.error("Cannot run docker\n\n#{err}\n")
        System.halt(1)
    end
  end

  defp debug_docker(opts, args) do
    if System.get_env("PIX_DEBUG") == "true" do
      Pix.Log.internal("docker #{inspect(args)}\n")

      if opts[:file] do
        Pix.Log.internal(File.read!(opts[:file]) <> "\n")
      end
    end
  end

  @spec opts_encode(opts()) :: [String.t()]
  defp opts_encode(opts) do
    k_fn = fn k ->
      k = k |> to_string() |> String.replace("_", "-")
      "#{if String.length(k) == 1, do: "-", else: "--"}#{k}"
    end

    Enum.flat_map(opts, fn
      {opt_key, opt_value} -> [k_fn.(opt_key), to_string(opt_value)]
      opt_key -> [k_fn.(opt_key)]
    end)
  end
end

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
    build_opts = run_build_options(cli_opts, pipeline, pipeline_target, ctx_dir, default_args)
    execute_run_build(build_opts, dockerfile_path, cli_opts)
  end

  @spec shell(Pix.Config.pipeline(), shell_cli_opts(), [String.t()]) :: :ok
  def shell(pipeline_config, cli_opts, cmd_args) do
    %{default_args: default_args, ctx_dir: ctx_dir, pipeline_mod: pipeline_mod} = pipeline_config

    pipeline = pipeline_mod.pipeline()
    validate_shell_capability!(pipeline_mod, pipeline.name)

    shell_from_target = Keyword.get(cli_opts, :target, :default)
    validate_shell_target!(pipeline, shell_from_target)

    shell_target = "#{pipeline.name}.shell"
    shell_docker_image = "pix/#{pipeline.name}/shell"

    # Build shell image
    pipeline = pipeline_mod.shell(pipeline, shell_target, shell_from_target)
    dockerfile_path = write_pipeline_files(Pix.PipelineSDK.dump(pipeline), pipeline.dockerignore)
    build_opts = shell_build_options(shell_target, shell_docker_image, ctx_dir, default_args, dockerfile_path)

    execute_shell_build(build_opts, shell_target)

    # Enter the shell
    enter_shell(shell_docker_image, shell_target, cli_opts, cmd_args)
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

  @spec validate_run_targets!(Pix.PipelineSDK.t(), String.t()) :: :ok
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

  @spec build_run_pipeline_dockerfile(Pix.PipelineSDK.t(), String.t(), [String.t()]) :: String.t()
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

    Pix.PipelineSDK.dump(pipeline) <> "\n" <> pipeline_run_stage
  end

  @spec write_pipeline_files(String.t(), [String.t()] | nil) :: Path.t()
  defp write_pipeline_files(dockerfile_content, dockerignore) do
    dockerfile_path = Path.join([System.tmp_dir!(), Pix.Helper.uuid()]) <> ".Dockerfile"
    File.write!(dockerfile_path, dockerfile_content)

    if dockerignore do
      File.write!("#{dockerfile_path}.dockerignore", Enum.join(dockerignore, "\n"))
    end

    dockerfile_path
  end

  @spec run_build_options(run_cli_opts(), Pix.PipelineSDK.t(), String.t(), Path.t(), map()) :: Pix.Docker.opts()
  defp run_build_options(cli_opts, pipeline, pipeline_target, ctx_dir, default_args) do
    no_cache_filter_opts =
      for(%{cache: false, stage: stage} <- pipeline.stages, do: {:"no-cache-filter", stage}) ++
        for {:no_cache_filter, filter} <- cli_opts, do: {:"no-cache-filter", filter}

    base_opts = [
      target: pipeline_target,
      progress: Keyword.get(cli_opts, :progress, "auto"),
      platform: "linux/#{Pix.Env.arch()}",
      build_context: "#{Pix.PipelineSDK.pipeline_ctx()}=#{ctx_dir}"
    ]

    cli_args = for {:arg, arg} <- cli_opts, do: arg

    base_opts
    |> add_run_output_option(cli_opts)
    |> add_run_tag_option(cli_opts)
    |> add_run_cache_options(cli_opts, no_cache_filter_opts)
    |> Kernel.++(pipeline_build_args(default_args, cli_args))
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

  @spec execute_run_build(Pix.Docker.opts(), Path.t(), run_cli_opts()) :: :ok
  defp execute_run_build(build_opts, dockerfile_path, cli_opts) do
    Pix.Log.info("\nRunning pipeline\n\n")

    build_opts = Keyword.put(build_opts, :file, dockerfile_path)
    Pix.Docker.build(build_opts, ".") |> halt_on_error()

    if cli_opts[:output] do
      Pix.Log.info("\nExported pipeline outputs to .pipeline/output:\n")
      for f <- File.ls!(".pipeline/output"), do: Pix.Log.info("- #{f}\n")
    end
  end

  @spec validate_shell_capability!(module(), String.t()) :: :ok
  defp validate_shell_capability!(pipeline_mod, pipeline_name) do
    unless function_exported?(pipeline_mod, :shell, 3) do
      Pix.Log.error("Pipeline #{pipeline_name} does not provide a shell")
      System.halt(1)
    end
  end

  @spec validate_shell_target!(Pix.PipelineSDK.t(), :default | String.t()) :: :ok
  defp validate_shell_target!(pipeline, shell_from_target) do
    known_targets = pipeline_targets(pipeline, :all)

    if shell_from_target not in [:default | known_targets] do
      Pix.Log.error("Pipeline #{pipeline.name} does not define a #{shell_from_target} target\n")
      Pix.Log.error("Available shell targets #{inspect(known_targets)}\n")
      System.halt(1)
    end

    :ok
  end

  @spec shell_build_options(String.t(), String.t(), Path.t(), map(), Path.t()) :: Pix.Docker.opts()
  defp shell_build_options(shell_target, shell_docker_image, ctx_dir, default_args, dockerfile_path) do
    [
      :load,
      target: shell_target,
      file: dockerfile_path,
      build_context: "#{Pix.PipelineSDK.pipeline_ctx()}=#{ctx_dir}",
      tag: shell_docker_image
    ] ++ pipeline_build_args(default_args, [])
  end

  @spec shell_run_options(String.t(), shell_cli_opts()) :: Pix.Docker.opts()
  defp shell_run_options(shell_target, cli_opts) do
    base_opts = [:privileged, :rm, :interactive, network: "host"]
    tty_opts = if Pix.Env.ci?(), do: [], else: [:tty]

    host_opts =
      if cli_opts[:host] do
        [volume: "#{File.cwd!()}:#{File.cwd!()}", workdir: File.cwd!()]
      else
        []
      end

    base_opts ++ tty_opts ++ host_opts ++ pipeline_envs(shell_target)
  end

  @spec execute_shell_build(Pix.Docker.opts(), String.t()) :: :ok
  defp execute_shell_build(build_opts, shell_target) do
    Pix.Log.info("\nBuilding pipeline (target=#{shell_target})\n\n")

    Pix.Docker.build(build_opts, ".")
    |> halt_on_error()
  end

  @spec enter_shell(String.t(), String.t(), shell_cli_opts(), [String.t()]) :: :ok
  defp enter_shell(shell_docker_image, shell_target, cli_opts, cmd_args) do
    Pix.Log.info("\nEntering shell\n")

    shell_docker_image
    |> Pix.Docker.run(shell_run_options(shell_target, cli_opts), cmd_args)
    |> halt_on_error()
  end

  @spec pipeline_targets(Pix.PipelineSDK.t(), visibility :: :all | :private | :public) :: [String.t()]
  defp pipeline_targets(pipeline, visibility) do
    filter_stage =
      case visibility do
        :all -> Access.all()
        :private -> Access.filter(& &1.private)
        :public -> Access.filter(&(not &1.private))
      end

    get_in(pipeline, [Access.key!(:stages), filter_stage, :stage])
  end

  @spec pipeline_builtins_var(pipeline_target :: String.t()) :: Pix.Config.args()
  defp pipeline_builtins_var(pipeline_target) do
    %{
      "PIX_PROJECT_NAME" => Pix.Env.git_project_name(),
      "PIX_COMMIT_SHA" => Pix.Env.git_commit_sha(),
      "PIX_PIPELINE_TARGET" => pipeline_target
    }
  end

  @spec pipeline_envs(pipeline_target :: String.t()) :: Pix.Docker.opts()
  defp pipeline_envs(pipeline_target) do
    builtin_envs = pipeline_builtins_var(pipeline_target)

    for {env_k, env_v} <- builtin_envs do
      {:env, "#{env_k}=#{env_v}"}
    end
  end

  @spec pipeline_build_args(Pix.Config.args(), cli_args :: [String.t()]) :: Pix.Docker.opts()
  defp pipeline_build_args(default_args, cli_args) do
    default_args = Map.merge(default_args, pipeline_builtins_var(""))

    build_args = for {arg_k, arg_v} <- default_args, do: {:build_arg, "#{arg_k}=#{arg_v}"}
    cli_build_args = for arg <- cli_args, do: {:build_arg, arg}

    build_args ++ cli_build_args
  end

  @spec halt_on_error(non_neg_integer()) :: :ok
  defp halt_on_error(0), do: :ok
  defp halt_on_error(status), do: System.halt(status)
end

defmodule Pix.Pipeline.Graph do
  @moduledoc false

  @type edge() :: {from_node :: gnode(), to_node :: gnode()}
  @type gnode() :: String.t()
  @type t() :: [edge() | gnode()]

  @spec get(Pix.PipelineSDK.t()) :: t()
  def get(%Pix.PipelineSDK{} = pipeline) do
    stage_nodes = for stage <- pipeline.stages, do: stage.stage

    stage_deps_edges =
      for stage <- pipeline.stages, instruction <- stage.instructions, uniq: true do
        case instruction do
          {"FROM", _from_opts, [from_arg]} ->
            [depends_from | _] = from_arg |> String.split(" ")
            {depends_from, stage.stage}

          {"COPY", copy_opts, _copy_args} ->
            pipeline_ctx = Pix.PipelineSDK.pipeline_ctx()

            case copy_opts[:from] do
              nil -> nil
              ^pipeline_ctx -> nil
              depends_from -> {depends_from, stage.stage}
            end

          _ ->
            nil
        end
      end

    stage_deps_edges = Enum.reject(stage_deps_edges, &is_nil/1)

    stage_nodes ++ stage_deps_edges
  end

  @spec roots(t()) :: [gnode()]
  def roots(dag) do
    all_nodes = nodes(dag)
    child_nodes = MapSet.new(Enum.map(edges(dag), &elem(&1, 1)))
    MapSet.difference(all_nodes, child_nodes) |> MapSet.to_list()
  end

  @spec roots(t()) :: [gnode()]
  def nodes(dag), do: MapSet.new(Enum.flat_map(edges(dag), &Tuple.to_list/1) ++ single_nodes(dag))

  @spec edges(t()) :: [edge()]
  def edges(dag), do: dag |> Enum.split_with(&is_tuple/1) |> elem(0)

  @spec single_nodes(t()) :: [gnode()]
  def single_nodes(dag), do: dag |> Enum.split_with(&is_tuple/1) |> elem(1)

  @spec adjacency_list(t()) :: %{gnode() => [child :: gnode()]}
  def adjacency_list(dag), do: dag |> edges() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
end

defmodule Pix.Command do
  @moduledoc false

  @spec help() :: :ok
  def help() do
    Pix.Log.info("""
    Pix - Pipelines for buildx.

    COMMANDS:

    pix ls [--all]
        List the current project's pipelines configuration.

        FLAGS:
            --all               Show also private pipelines targets

    pix graph [--format FORMAT] PIPELINE
        Prints the pipeline graph.

        ARGS:
            PIPELINE            The selected pipeline

        OPTIONS:
            --format            Output format - "pretty", "dot" (default "pretty").
            
                                "dot" produces a DOT graph description of the pipeline graph in graph.dot
                                in the current directory override any previously generated file.
                                (dot -Tpng graph.dot -o xref_graph.png)

    pix help
        This help.

    pix run [--output] [--arg ARG]* [--progress PROGRESS] [--target TARGET [--tag TAG]] [--no-cache] [--no-cache-filter TARGET]* PIPELINE
        Run PIPELINE.

        ARGS:
            PIPELINE            The selected pipeline

        FLAGS:
            --output            Output the target artifacts under .pipeline/output directory
            --no-cache          Do not use cache when building the image

        OPTIONS:
            --arg*              Set pipeline one or more ARG (format KEY=value)
            --progress          Set type of progress output - "auto", "plain", "tty", "rawjson" (default "auto")
            --target            Run PIPELINE for a specific TARGET (default: all the PIPELINE targets)
            --tag               Tag the TARGET's docker image (default: no tag)
            --no-cache-filter*  Do not cache specified targets

    pix shell [--target TARGET] [--host] PIPELINE [COMMAND]
        Shell into the specified target of the PIPELINE.

        ARGS:
            PIPELINE            The selected pipeline
            COMMAND             If specified the COMMAND will be execute as a one-off command in the shell

        FLAGS:
            --host              The shell bind mounts the current working dir
                                (reflect files changes between the host and the shell container)

        OPTIONS:
            --target            The shell target

    ENVIRONMENT VARIABLES:

    PIX_DEBUG:                  Set to "true" to enable debug logs
    PIX_FORCE_PLATFORM_ARCH:    Set to "amd64"/"arm64" if you want to run the pipeline (and build docker images)
                                with a non-native architecture
    """)

    :ok
  end

  @spec graph(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_graph [format: :string]
  def graph(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_graph)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
        pipeline = config_pipelines[pipeline_alias].pipeline_mod.pipeline()

        case cli_opts[:format] do
          format when format in [nil, "pretty"] ->
            display_graph(pipeline)

          "dot" ->
            export_dot(pipeline)
        end

      [unknown_pipeline_alias] ->
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Log.error("'graph' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end

    :ok
  end

  defp export_dot(pipeline) do
    dag = Pix.Pipeline.Graph.get(pipeline)

    dot = [
      "strict digraph {\n",
      Enum.map(dag, fn
        {from_node, to_node} -> [inspect(from_node), " -> ", inspect(to_node), "\n"]
        single_node -> [inspect(single_node), "\n"]
      end),
      "\n}\n"
    ]

    File.write!("graph.dot", dot)

    Pix.Log.info("Generated graph.dot\n")
  end

  defp display_graph(pipeline) do
    dag = Pix.Pipeline.Graph.get(pipeline)
    roots = Pix.Pipeline.Graph.roots(dag)
    adj_list = Pix.Pipeline.Graph.adjacency_list(dag)

    ansi_colors = [
      :black,
      :blue,
      :cyan,
      :green,
      :magenta,
      :red,
      :white,
      :yellow,
      :light_black,
      :light_blue,
      :light_cyan,
      :light_green,
      :light_magenta,
      :light_red,
      :light_white,
      :light_yellow
    ]

    node_colors = dag |> Pix.Pipeline.Graph.nodes() |> Enum.zip(Stream.cycle(ansi_colors)) |> Map.new()

    Pix.Log.info("\nPipeline graph:\n\n")

    IO.puts(IO.ANSI.format([:bright, pipeline.name]))

    last_root = List.last(roots)

    for root <- roots do
      plot_graph(node_colors, root, adj_list, "", MapSet.new(), root == last_root)
    end

    :ok
  end

  defp plot_graph(node_colors, node, adj_list, prefix, seen, is_last) do
    children = Map.get(adj_list, node, [])
    last_child = List.last(children)

    # Print current node with proper spacing
    node_str = IO.ANSI.format([Map.fetch!(node_colors, node), node])
    x = if is_last, do: "└─", else: "├─"
    IO.puts("#{prefix}#{x} #{node_str}")

    # Process children
    seen = MapSet.put(seen, node)

    for child <- children do
      next_prefix = if is_last, do: prefix <> "   ", else: prefix <> "│  "

      if child not in seen,
        do: plot_graph(node_colors, child, adj_list, next_prefix, seen, child == last_child)
    end
  end

  @spec ls(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_ls [all: :boolean]
  def ls(config, argv) do
    {cli_opts, _args} = OptionParser.parse!(argv, strict: @cli_args_ls)
    display_pipelines(config.pipelines, Keyword.get(cli_opts, :all, false))
    :ok
  end

  defp display_pipelines(pipelines, show_all?) do
    IO.puts("")

    for {alias_, pipeline} <- pipelines do
      display_pipeline_header(alias_, pipeline)
      display_pipeline_details(pipeline)
      display_pipeline_targets(pipeline, show_all?)
      IO.puts("")
    end
  end

  defp display_pipeline_header(alias_, %{default_args: args}) do
    IO.puts(IO.ANSI.format([:bright, :underline, alias_, "\n"]))
    IO.puts("  default_args:")
    display_args(args, "    ")
  end

  defp display_pipeline_details(%{pipeline_mod: mod}) do
    pipeline = mod.pipeline()
    IO.puts("  pipeline: #{IO.ANSI.format([:faint, pipeline.name])}")

    # Display description
    IO.puts("    description:")

    pipeline.description
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(&IO.puts("      #{IO.ANSI.format([:faint, &1])}"))

    # Display args and shell status
    IO.puts("    args:")
    display_args(pipeline.args_, "      ")
    shell_status = if function_exported?(mod, :shell, 3), do: "available", else: "not available"
    IO.puts("    shell: #{IO.ANSI.format([:faint, shell_status])}")
  end

  defp display_pipeline_targets(%{default_targets: defaults, pipeline_mod: mod}, show_all?) do
    pipeline = mod.pipeline()
    IO.puts("    targets:")
    IO.puts("      default: #{IO.ANSI.format([:faint, :green, inspect(defaults)])}")

    for stage <- pipeline.stages, show_all? or not stage.private do
      display_stage(stage)
    end
  end

  defp display_stage(%{stage: name, args_: args, outputs: outputs, private: private, cache: cache}) do
    # Stage name with formatting based on privacy
    stage_format = if private, do: [:faint, :green], else: [:green]
    IO.puts("      #{IO.ANSI.format(stage_format ++ [name])}:")

    # Display stage properties
    if private, do: IO.puts("        private: true")
    if not cache, do: IO.puts("        cache: #{IO.ANSI.format([:faint, "disabled"])}")

    # Display args and outputs
    IO.puts("        args:")
    display_args(args, "          ")
    IO.puts("        outputs:")
    for output <- outputs, do: IO.puts("          #{IO.ANSI.format([:yellow, :faint, "- #{inspect(output)}"])}")
  end

  defp display_args(args, indent) do
    for {k, v} <- args,
        not String.starts_with?(k, "PIX_") do
      IO.puts([
        indent,
        IO.ANSI.format([:faint, :blue, k, :reset, :faint, ": #{inspect(v)}"])
      ])
    end
  end

  @spec run(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_run [
    arg: [:string, :keep],
    output: :boolean,
    progress: :string,
    tag: :string,
    target: :string,
    no_cache: :boolean,
    no_cache_filter: [:string, :keep]
  ]
  def run(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_run)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.run(config_pipelines[pipeline_alias], cli_opts)

      [unknown_pipeline_alias] ->
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)

      _ ->
        Pix.Log.error("'run' command accept exactly one pipeline but got #{inspect(args)}\n")
        System.halt(1)
    end
  end

  @spec shell(Pix.Config.t(), OptionParser.argv()) :: :ok
  @cli_args_shell [target: :string, host: :boolean]
  def shell(config, argv) do
    {cli_opts, args} = OptionParser.parse!(argv, strict: @cli_args_shell)
    config_pipelines = config.pipelines

    case args do
      [pipeline_alias | cmd_args] when is_map_key(config_pipelines, pipeline_alias) ->
        Pix.Pipeline.shell(config_pipelines[pipeline_alias], cli_opts, cmd_args)

      [unknown_pipeline_alias | _] ->
        Pix.Log.error("Unknown pipeline #{inspect(unknown_pipeline_alias)}\n")
        Pix.Log.error("Available pipelines #{inspect(Map.keys(config_pipelines))})\n")
        System.halt(1)
    end
  end
end

defmodule Pix.Config do
  @type t() :: %{
          pipelines: %{
            pipeline_alias() => pipeline()
          }
        }
  @type pipeline() :: %{
          default_args: args(),
          default_targets: [String.t()],
          ctx_dir: Path.t(),
          pipeline: Pix.PipelineSDK.t(),
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

  @spec get() :: t()
  def get() do
    pix_exs_path = ".pix.exs"

    if File.regular?(pix_exs_path) do
      mod = Pix.Helper.compile_file(pix_exs_path)
      pix_exs = validate_pix_exs(mod.project())

      pipelines = Map.keys(pix_exs.pipelines)
      Pix.Log.internal("Loaded project manifest (pipelines: #{inspect(pipelines)})\n")

      require_pipelines(pix_exs)
    else
      Pix.Log.error("Cannot find a #{pix_exs_path} file in the current working directory\n")
      System.halt(1)
    end
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
    |> Task.async_stream(&get_git_pipeline(&1.uri, &1.ref), ordered: false, timeout: :infinity)
    |> Stream.run()

    # Map pipeline configurations to their implementations
    pipelines =
      Map.new(pix_exs.pipelines, fn {alias_, config} ->
        {ctx_dir, pipeline_mod} = require_pipeline_from(config.from)

        {alias_,
         %{
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
    Pix.Log.internal("Fetching remote git pipeline #{uri} (#{ref}) ... ")

    checkout_dir = Path.join([".pipeline", "checkout", uri, ref])
    cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]

    if File.dir?(checkout_dir) do
      _ = System.cmd("git", ["fetch", "origin", ref], cmd_opts)
      _ = System.cmd("git", ["reset", "--hard", "FETCH_HEAD"], cmd_opts)

      Pix.Log.internal("local checkout updated\n")
    else
      File.mkdir_p!(checkout_dir)

      with {_, 0} <- System.cmd("git", ["clone", "--depth", "1", "--branch", ref, uri, "."], cmd_opts) do
        Pix.Log.internal("clone completed\n")
      else
        {err_msg, _} ->
          Pix.Log.internal("error\n\n")
          Pix.Log.error(err_msg)

          File.rm_rf!(checkout_dir)
          System.halt(1)
      end
    end

    :ok
  end

  @spec require_pipeline_from(from()) :: {ctx_dir :: Path.t(), pipeline_mod :: Pix.PipelineProject.t()}
  defp require_pipeline_from(from) do
    ctx_dir =
      case from do
        %{path: path} -> path
        %{git: uri, ref: ref} -> Path.join([".pipeline", "checkout", uri, ref])
      end

    pipeline_exs_dir = Path.join(ctx_dir, Map.get(from, :sub_dir, ""))
    pipeline_exs_path = Path.join(pipeline_exs_dir, "pipeline.exs")

    if not File.exists?(pipeline_exs_path) do
      Pix.Log.error("Pipeline specification '#{pipeline_exs_path}' file not found in #{inspect(from)}\n")

      System.halt(1)
    end

    pipeline_mod = Pix.Helper.compile_file(pipeline_exs_path)

    {ctx_dir, pipeline_mod}
  end
end

defmodule Pix do
  @moduledoc false

  @spec version() :: String.t()
  def version(), do: System.get_env("PIX_VERSION", "0.0.0")

  @spec main(OptionParser.argv()) :: :ok
  def main(argv) do
    Pix.Log.info("pix v#{version()}\n\n")
    Pix.System.setup()
    Pix.Log.info("\n")

    case argv do
      ["ls" | sub_argv] ->
        Pix.Command.ls(Pix.Config.get(), sub_argv)

      ["graph" | sub_argv] ->
        Pix.Command.graph(Pix.Config.get(), sub_argv)

      ["run" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.run(Pix.Config.get(), sub_argv)

      ["shell" | sub_argv] ->
        Pix.Docker.setup_buildx()
        Pix.Command.shell(Pix.Config.get(), sub_argv)

      ["help"] ->
        Pix.Command.help()

      cmd ->
        Pix.Log.error("Unknown command #{inspect(cmd)}\n")
        System.halt(1)
    end

    :ok
  end
end

Pix.main(System.argv())
