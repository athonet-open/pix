defmodule Pix.Docker do
  @moduledoc false

  @docker_desktop_socket "/run/host-services/ssh-auth.sock"
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

  @spec run(image :: String.t(), ssh_fwd? :: boolean(), opts(), cmd_args :: [String.t()]) :: status :: non_neg_integer()
  def run(image, ssh_fwd?, opts, cmd_args) do
    ssh_opts = if ssh_fwd?, do: run_opts_ssh_forward(), else: []
    opts = opts ++ ssh_opts ++ run_opts_docker_outside_of_docker()
    args = ["run"] ++ opts_encode(opts) ++ Pix.Env.pix_docker_run_opts() ++ [image] ++ cmd_args

    debug_docker(opts, args)

    port_opts = [:nouse_stdio, :exit_status, args: args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, exit_status}} -> exit_status
    end
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

  @spec run_opts_ssh_forward :: opts()
  defp run_opts_ssh_forward do
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

  @spec run_opts_docker_outside_of_docker :: opts()
  defp run_opts_docker_outside_of_docker do
    docker_socket = "/var/run/docker.sock"
    Pix.Report.internal(">>> Supporting docker outside-of docker via socket mount (#{docker_socket})\n")
    [volume: "#{docker_socket}:#{docker_socket}"]
  end

  @spec build(ssh_fwd? :: boolean(), opts(), String.t()) :: exit_status :: non_neg_integer()
  def build(ssh_fwd?, opts, ctx) do
    ssh_opts = if ssh_fwd?, do: [ssh: "default"], else: []

    builder_opts =
      case buildx_builder() do
        nil -> []
        builder_id -> [builder: builder_id]
      end

    opts = builder_opts ++ ssh_opts ++ opts

    debug_opt = if System.get_env("PIX_DOCKER_BUILDX_DEBUG") == "true", do: ["debug"], else: []

    args =
      [System.find_executable("docker"), "buildx"] ++
        debug_opt ++
        ["build"] ++
        opts_encode(opts) ++ Pix.Env.pix_docker_build_opts() ++ [ctx]

    debug_docker(opts, args)

    {_, exit_status} = System.cmd(Pix.System.cmd_wrapper_path(), args, env: [{"BUILDX_EXPERIMENTAL", "1"}])

    exit_status
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
end
