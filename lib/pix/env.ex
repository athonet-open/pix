defmodule Pix.Env do
  @moduledoc """
  Environment information.
  """

  @spec ci? :: boolean()
  def ci?, do: System.get_env("CI", "") != ""

  @spec arch :: Pix.Config.supported_arch() | (forced_arch :: atom())
  def arch do
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

  @spec git_commit_sha :: String.t()
  def git_commit_sha do
    {res, 0} = System.cmd("git", ~w[rev-parse HEAD])
    String.trim(res)
  end

  @spec git_project_name :: String.t()
  def git_project_name do
    {res, 0} = System.cmd("git", ~w[rev-parse --show-toplevel])
    res = String.trim(res)

    Path.basename(res)
  end

  @spec pix_docker_run_opts() :: OptionParser.argv()
  def pix_docker_run_opts do
    "PIX_DOCKER_RUN_OPTS"
    |> System.get_env("")
    |> OptionParser.split()
  end

  @spec pix_docker_build_opts() :: OptionParser.argv()
  def pix_docker_build_opts do
    "PIX_DOCKER_BUILD_OPTS"
    |> System.get_env("")
    |> OptionParser.split()
  end
end
