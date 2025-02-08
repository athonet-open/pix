defmodule Pix.Docker do
  @moduledoc false

  @buildkit_version "v0.19.0"

  @docker_desktop_socket "/run/host-services/ssh-auth.sock"
  @type opts() :: [Keyword.key() | {Keyword.key(), Keyword.value()}]

  @spec buildx_builder :: String.t()
  defp buildx_builder, do: "pix-buildkit-#{@buildkit_version}-"

  @spec setup_buildx :: :ok
  def setup_buildx do
    assert_docker_installed()

    Pix.Log.internal("Setup docker buildx builder (#{buildx_builder()}, buildkit #{@buildkit_version}) ... ")

    case System.cmd("docker", ["buildx", "inspect", "--builder", buildx_builder()], stderr_to_stdout: true) do
      {_, 0} ->
        Pix.Log.internal("already present\n")

      _ ->
        opts = ["--driver", "docker-container", "--driver-opt", "image=moby/buildkit:#{@buildkit_version}"]
        {_, 0} = System.cmd("docker", ["buildx", "create", "--bootstrap", "--name", buildx_builder() | opts])

        Pix.Log.internal("\n\nCreated builder:`\n")

        {inspect, 0} =
          System.cmd("docker", ["buildx", "inspect", "--builder", buildx_builder()], stderr_to_stdout: true)

        Pix.Log.internal("\n#{inspect}\n")
    end

    :ok
  end

  @spec version :: map()
  def version do
    {json, 0} = System.cmd("docker", ~w[version --format json])
    JSON.decode!(json)
  end

  @spec run(image :: String.t(), opts(), cmd_args :: [String.t()]) :: status :: non_neg_integer()
  def run(image, opts, cmd_args) do
    opts = opts ++ run_opts_ssh_forward() ++ run_opts_docker_outside_of_docker()
    args = ["run"] ++ opts_encode(opts) ++ Pix.Env.pix_docker_run_opts() ++ [image] ++ cmd_args

    debug_docker(opts, args)

    port_opts = [:nouse_stdio, :exit_status, args: args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, exit_status}} -> exit_status
    end
  end

  @spec run_opts_ssh_forward :: opts()
  defp run_opts_ssh_forward do
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

  @spec run_opts_docker_outside_of_docker :: opts()
  defp run_opts_docker_outside_of_docker do
    docker_socket = "/var/run/docker.sock"
    Pix.Log.internal(">>> Supporting docker outside-of docker via socket mount (#{docker_socket})\n")
    [volume: "#{docker_socket}:#{docker_socket}"]
  end

  @spec build(opts(), String.t()) :: exit_status :: non_neg_integer()
  def build(opts, ctx) do
    opts = [builder: buildx_builder(), ssh: "default"] ++ opts

    args =
      [System.find_executable("docker"), "buildx", "build"] ++
        opts_encode(opts) ++ Pix.Env.pix_docker_build_opts() ++ [ctx]

    debug_docker(opts, args)

    {_, exit_status} = System.cmd(Pix.System.cmd_wrapper_path(), args)

    exit_status
  end

  defp assert_docker_installed do
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
