defmodule Pix.Pipeline.SDK do
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
  @spec pipeline_ctx :: String.t()
  def pipeline_ctx, do: "pipeline_ctx"

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
