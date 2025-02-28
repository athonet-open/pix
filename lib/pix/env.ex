defmodule Pix.Env do
  @moduledoc """
  Environment information.
  """

  @doc """
  Returns whether the code is running in a CI environment by checking the `CI` environment variable.
  Returns `true` if `CI` env var is set, `false` otherwise.
  """
  @spec ci? :: boolean()
  def ci?, do: System.get_env("CI", "") != ""

  @doc """
  Returns the current system architecture.
  Detects amd64/x86_64 or arm64/aarch64 architectures.
  Can be overridden by setting PIX_FORCE_PLATFORM_ARCH environment variable.
  """
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

  @doc """
  Returns the current git commit SHA as a string.
  Executes `git rev-parse HEAD` command.
  Defaults to the given default value if git is not initialized or the command fails.
  """
  @spec git_commit_sha(default :: String.t()) :: String.t()
  def git_commit_sha(default \\ "") do
    case System.cmd("git", ~w[rev-parse HEAD]) do
      {res, 0} -> String.trim(res)
      _ -> default
    end
  end

  @doc """
  Returns the git project name (repository name) as a string.
  Gets the basename of the git root directory.
  Defaults to the given default value if git is not initialized or the command fails.
  """
  @spec git_project_name(default :: String.t()) :: String.t()
  def git_project_name(default \\ File.cwd!()) do
    res =
      case System.cmd("git", ~w[rev-parse --show-toplevel]) do
        {res, 0} -> String.trim(res)
        _ -> default
      end

    Path.basename(res)
  end

  @doc """
  Returns additional Docker run options from `PIX_DOCKER_RUN_OPTS` environment variable.
  Parses the options string into command line arguments.
  """
  @spec pix_docker_run_opts() :: OptionParser.argv()
  def pix_docker_run_opts do
    "PIX_DOCKER_RUN_OPTS"
    |> System.get_env("")
    |> OptionParser.split()
  end

  @doc """
  Returns additional Docker build options from `PIX_DOCKER_BUILD_OPTS` environment variable.
  Parses the options string into command line arguments.
  """
  @spec pix_docker_build_opts() :: OptionParser.argv()
  def pix_docker_build_opts do
    "PIX_DOCKER_BUILD_OPTS"
    |> System.get_env("")
    |> OptionParser.split()
  end

  @doc """
  Returns the operating system name by executing `uname -s`.
  """
  @spec os :: String.t()
  def os do
    {res, 0} = System.cmd("uname", ~w[-s])
    String.trim(res)
  end

  @doc """
  Returns the current user ID by executing `id -u`.
  """
  @spec userid :: String.t()
  def userid do
    {res, 0} = System.cmd("id", ~w[-u])
    String.trim(res)
  end

  @doc """
  Returns the current group ID by executing `id -g`.
  """
  @spec groupid :: String.t()
  def groupid do
    {res, 0} = System.cmd("id", ~w[-g])
    String.trim(res)
  end
end
