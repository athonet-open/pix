defmodule Pix.Docker do
  @moduledoc false

  @docker_desktop_socket "/run/host-services/ssh-auth.sock"

  @typedoc "Docker CLI option list — atoms for flags, `{key, value}` tuples for options."
  @type opts() :: [Keyword.key() | {Keyword.key(), Keyword.value()}]

  @spec buildx_builder :: String.t() | nil
  defp buildx_builder, do: :persistent_term.get(:pix_buildx_builder, nil)
  defp set_buildx_builder(builder_id), do: :persistent_term.put(:pix_buildx_builder, builder_id)

  @spec setup_buildx :: :ok
  def setup_buildx do
    assert_docker_installed()

    case System.get_env("PIX_DOCKER_BUILDKIT_VERSION") do
      nil ->
        # use the default builder
        :ok

      buildkit_version ->
        set_buildx_builder("pix-buildkit-#{buildkit_version}-")
        create_buildx_builder(buildkit_version)
    end
  end

  @spec version :: map()
  def version do
    {json, 0} = System.cmd("docker", ~w[version --format json])
    Jason.decode!(json)
  end

  @spec info :: {:ok, map()} | {:error, String.t()}
  def info do
    case System.cmd("docker", ~w[info --format json]) do
      {json, 0} ->
        {:ok, Jason.decode!(json)}

      {err, _} ->
        {:error, err}
    end
  end

  @spec run(image :: String.t(), ssh_specs :: [String.t()], opts(), cmd_args :: [String.t()]) ::
          status :: non_neg_integer()
  def run(image, ssh_specs, opts, cmd_args) do
    ssh_opts = if ssh_specs != [], do: run_opts_ssh_forward(ssh_specs), else: []
    opts = opts ++ ssh_opts ++ run_opts_docker_outside_of_docker()
    args = ["run"] ++ opts_encode(opts) ++ Pix.Env.pix_docker_run_opts() ++ [image] ++ cmd_args

    debug_docker(opts, args)
    docker_cmd_with_stdio(args)
  end

  @spec create_buildx_builder(String.t()) :: :ok
  defp create_buildx_builder(buildkit_version) do
    Pix.Report.internal("Setup docker buildx builder (#{buildx_builder()}, buildkit #{buildkit_version}) ... ")

    case System.cmd("docker", ["buildx", "inspect", "--builder", buildx_builder()], stderr_to_stdout: true) do
      {_, 0} ->
        Pix.Report.internal("already present\n")

      _ ->
        opts = ["--driver", "docker-container", "--driver-opt", "image=moby/buildkit:#{buildkit_version}"]
        {_, 0} = System.cmd("docker", ["buildx", "create", "--bootstrap", "--name", buildx_builder() | opts])

        Pix.Report.internal("\n\nCreated builder:`\n")

        {inspect, 0} =
          System.cmd("docker", ["buildx", "inspect", "--builder", buildx_builder()], stderr_to_stdout: true)

        Pix.Report.internal("\n#{inspect}\n")
    end

    :ok
  end

  @spec run_opts_ssh_forward([String.t()]) :: opts()
  defp run_opts_ssh_forward(ssh_specs) do
    has_default = Enum.any?(ssh_specs, &String.starts_with?(&1, "default"))
    agent_opts = if has_default, do: run_opts_ssh_agent_forward(), else: []
    {volume_opts, key_paths} = run_opts_ssh_key_mounts(ssh_specs)
    git_ssh_opts = run_opts_git_ssh_command(key_paths)
    agent_opts ++ volume_opts ++ git_ssh_opts
  end

  @spec run_opts_ssh_agent_forward :: opts()
  defp run_opts_ssh_agent_forward do
    ssh_sock =
      cond do
        :os.type() == {:unix, :darwin} ->
          Pix.Report.internal(
            ">>> detected Darwin OS - assuming 'docker desktop' environment for SSH socket forwarding\n"
          )

          @docker_desktop_socket

        System.get_env("SSH_AUTH_SOCK") == nil ->
          Pix.Report.internal(">>> SSH socket NOT forwarded\n")
          nil

        true ->
          ssh_auth_sock = System.get_env("SSH_AUTH_SOCK", "")
          Pix.Report.internal(">>> forwarding SSH socket via #{inspect(ssh_auth_sock)}\n")
          ssh_auth_sock
      end

    if ssh_sock do
      [env: "SSH_AUTH_SOCK=#{ssh_sock}", volume: "#{ssh_sock}:#{ssh_sock}"]
    else
      []
    end
  end

  @spec run_opts_ssh_key_mounts([String.t()]) :: {opts(), key_paths :: [String.t()]}
  defp run_opts_ssh_key_mounts(ssh_specs) do
    ssh_specs
    |> Enum.flat_map(&parse_ssh_key_paths/1)
    |> Enum.reduce({[], []}, fn path, {vol_acc, key_path_acc} ->
      path = Path.expand(path)
      container_path = "/root/.ssh/#{Path.basename(path)}"
      Pix.Report.internal(">>> mounting SSH key #{inspect(path)} as #{container_path} into shell container\n")
      {[{:volume, "#{path}:#{container_path}:ro"} | vol_acc], [container_path | key_path_acc]}
    end)
  end

  # Parses an --ssh spec and returns the list of key file paths (if any).
  # Handles: "default", "default=key1,key2", "id=key", "/bare/path".
  @spec parse_ssh_key_paths(String.t()) :: [String.t()]
  defp parse_ssh_key_paths("default"), do: []

  defp parse_ssh_key_paths(spec) do
    case String.split(spec, "=", parts: 2) do
      [_id, paths] when paths != "" -> String.split(paths, ",")
      [path] when path != "" -> [path]
      _ -> []
    end
  end

  @spec expand_ssh_spec(String.t()) :: String.t()
  defp expand_ssh_spec(spec) do
    case String.split(spec, "=", parts: 2) do
      [id, paths] when paths != "" ->
        expanded = paths |> String.split(",") |> Enum.map_join(",", &Path.expand/1)
        "#{id}=#{expanded}"

      _ ->
        spec
    end
  end

  @spec run_opts_git_ssh_command([String.t()]) :: opts()
  defp run_opts_git_ssh_command([]), do: []

  defp run_opts_git_ssh_command(key_paths) do
    identity_flags = Enum.map_join(key_paths, " ", &"-i #{&1}")
    [env: "GIT_SSH_COMMAND=ssh #{identity_flags} -o StrictHostKeyChecking=no"]
  end

  @spec run_opts_docker_outside_of_docker :: opts()
  defp run_opts_docker_outside_of_docker do
    docker_socket = "/var/run/docker.sock"
    Pix.Report.internal(">>> Supporting docker outside-of docker via socket mount (#{docker_socket})\n")
    [volume: "#{docker_socket}:#{docker_socket}"]
  end

  @spec build(ssh_specs :: [String.t()], opts(), String.t()) :: exit_status :: non_neg_integer()
  def build(ssh_specs, opts, ctx) do
    ssh_opts = Enum.map(ssh_specs, fn spec -> {:ssh, expand_ssh_spec(spec)} end)

    builder_opts =
      case buildx_builder() do
        nil -> []
        builder_id -> [builder: builder_id]
      end

    opts = builder_opts ++ ssh_opts ++ opts

    buildx_args = ["build"] ++ opts_encode(opts) ++ Pix.Env.pix_docker_build_opts() ++ [ctx]

    if System.get_env("PIX_DOCKER_BUILDX_DEBUG") == "true" do
      args = ["buildx", "debug" | buildx_args]
      envs = [{"BUILDX_EXPERIMENTAL", "1"}]

      debug_docker(opts, args)
      docker_cmd_with_stdio(args, envs)
    else
      args = [System.find_executable("docker"), "buildx" | buildx_args]

      debug_docker(opts, args)
      {_, exit_status} = System.cmd(Pix.System.cmd_wrapper_path(), args)
      exit_status
    end
  end

  @spec assert_docker_installed() :: :ok
  defp assert_docker_installed do
    case info() do
      {:ok, info} ->
        Pix.Report.internal("Running on #{info["Name"]} #{info["OSType"]}-#{info["Architecture"]} ")
        Pix.Report.internal("(client #{info["ClientInfo"]["Version"]}, ")
        Pix.Report.internal("server #{info["ServerVersion"]} experimental_build=#{info["ExperimentalBuild"]}, ")

        case Enum.find(info["ClientInfo"]["Plugins"], &match?(%{"Name" => "buildx"}, &1)) do
          nil ->
            Pix.Report.error("buildx plugin not installed\n")
            System.halt(1)

          %{"Version" => version} ->
            Pix.Report.internal("buildx plugin version #{version})\n\n")
        end

      {err, _} ->
        Pix.Report.error("Cannot run docker\n\n#{err}\n")
        System.halt(1)
    end
  end

  @spec debug_docker(opts(), OptionParser.argv()) :: :ok
  defp debug_docker(opts, args) do
    Pix.Report.debug("docker #{inspect(args, limit: :infinity)}\n")

    if opts[:file] do
      Pix.Report.debug(File.read!(opts[:file]) <> "\n")
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

  @spec docker_cmd_with_stdio(args :: [String.t()], envs :: [{String.t(), String.t()}]) ::
          exit_status :: non_neg_integer()
  defp docker_cmd_with_stdio(args, envs \\ []) do
    env = Enum.map(envs, fn {a, b} -> {to_charlist(a), to_charlist(b)} end)
    port_opts = [:nouse_stdio, :exit_status, args: args, env: env]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, exit_status}} -> exit_status
    end
  end
end
