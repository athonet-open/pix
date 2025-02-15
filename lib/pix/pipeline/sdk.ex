defmodule Pix.Pipeline.SDK do
  @moduledoc """
  Provides APIs for building Dockerfiles pipelines programmatically.

  The names of the functions map to the [Dockerfile](https://docs.docker.com/engine/reference/builder/) commands.
  Some of the functions have additional options to extend the functionality of the commands (eg. `private` and `cache` in `stage/2`)
  and some functions are extension to the commands (eg. `output/2`).

  For example:

  ```elixir
  import Pix.Pipeline.SDK

  pipeline =
    pipeline("gohello", description: "My pipeline description")
    |> stage("build", from: "golang:1.23", private: true)
    |> copy("hello.go", ".")
    |> run("go build -o hello hello.go")
    |> stage("app", from: "scratch")
    |> copy("hello", ".", from: "build")
    |> cmd(["/hello"])

  pipeline
  |> dump()
  |> IO.puts()
  ```

  ## Output

  ```Dockerfile
  FROM golang:1.23 AS build
  COPY hello.go .
  RUN go build -o hello hello.go

  FROM scratch AS app
  COPY --from="build" hello .
  CMD ["/hello"]
  ```
  """

  @type command :: String.t()
  @type options :: Keyword.t()
  @type iargs :: [String.t(), ...]
  @type args() :: %{(name :: String.t()) => default_value :: nil | String.t()}
  @type instruction :: {command(), options(), iargs()}

  defmodule Stage do
    @moduledoc """
    Pipeline stage.
    """

    @enforce_keys [
      :stage,
      :instructions,
      :args_,
      :outputs,
      :description,
      :private,
      :cache
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            stage: String.t(),
            instructions: [Pix.Pipeline.SDK.instruction()],
            args_: Pix.Pipeline.SDK.args(),
            outputs: [Path.t()],
            description: nil | String.t(),
            private: boolean(),
            cache: boolean()
          }
  end

  @enforce_keys [:name]
  defstruct @enforce_keys ++ [description: "", args: [], stages: [], args_: %{}, dockerignore: []]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          args: [instruction()],
          stages: [Stage.t()],
          args_: args(),
          dockerignore: [String.t()]
        }

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

  ```elixir
  stage("build", from: "golang:1.23")
  ```

  the optional `private` and `cache` options can be used to control the behavior of the stage:

  - `private: true` - the stage will not be accessible as a build target, only from other stages.
  - `cache: false` - the stage will not be cached, the stage will be built from scratch every time.
  """
  @spec stage(t(), stage_name :: String.t(), [
          {:from, String.t()} | {:description, String.t()} | {:private, boolean()} | {:cache, boolean()}
        ]) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, stage_name, options \\ []) do
    options = Keyword.validate!(options, from: "scratch", description: nil, private: false, cache: true)

    new_stage = %Stage{
      stage: stage_name,
      description: options[:description],
      private: options[:private],
      cache: options[:cache],
      args_: %{},
      outputs: [],
      instructions: []
    }

    %__MODULE__{pipeline | stages: [new_stage | stages]}
    |> append_instruction("FROM", ["#{options[:from]} AS #{stage_name}"])
  end

  @doc """
  Declare a stage output artifact.

  This function doesn't add any instruction to the Dockerfile.
  It's used to declare the output of the stage.
  """
  @spec output(t(), Path.t() | [Path.t(), ...]) :: t()
  def output(%__MODULE__{} = pipeline, path) do
    {_, pipeline} =
      get_and_update_in(
        pipeline,
        [Access.key!(:stages), Access.at!(0), Access.key!(:outputs)],
        &{&1, &1 ++ List.wrap(path)}
      )

    pipeline
  end

  @doc """
  Adds a [`RUN`](https://docs.docker.com/reference/dockerfile/#run) instruction.

  For [Here-documents](https://docs.docker.com/reference/dockerfile/#here-documents) string see `sigil_h/2`.
  """
  @spec run(t(), command :: String.t() | [String.t(), ...], options()) :: t()
  def run(%__MODULE__{} = pipeline, command, options \\ []) do
    append_instruction(pipeline, "RUN", options, shell_or_exec_form(command))
  end

  @doc """
  Adds a [`CMD`](https://docs.docker.com/reference/dockerfile/#cmd) instruction.
  """
  @spec cmd(t(), command :: String.t() | [String.t()]) :: t()
  def cmd(%__MODULE__{} = pipeline, command) do
    append_instruction(pipeline, "CMD", [], shell_or_exec_form(command))
  end

  @doc """
  Adds a [`LABEL`](https://docs.docker.com/reference/dockerfile/#label) instruction.
  """
  @spec label(t(), labels :: Enumerable.t({String.t(), String.t()})) :: t()
  def label(%__MODULE__{} = pipeline, labels) do
    labels = Enum.map(labels, fn {k, v} -> "#{inspect(k)}=#{inspect(v)}" end)
    append_instruction(pipeline, "LABEL", [], labels)
  end

  @doc """
  Adds a [`EXPOSE`](https://docs.docker.com/reference/dockerfile/#expose) instruction.
  """
  @spec expose(t(), port :: String.t()) :: t()
  def expose(%__MODULE__{} = pipeline, port) do
    append_instruction(pipeline, "EXPOSE", [], [port])
  end

  @doc """
  Adds a [`ENV`](https://docs.docker.com/reference/dockerfile/#env) instruction.
  """
  @spec env(t(), envs :: Enumerable.t({String.t() | atom(), String.t()})) :: t()
  def env(%__MODULE__{} = pipeline, envs) do
    envs = Enum.map(envs, fn {k, v} -> "#{k}=#{inspect(v)}" end)
    append_instruction(pipeline, "ENV", [], envs)
  end

  @doc """
  Adds a [`ADD`](https://docs.docker.com/reference/dockerfile/#add) instruction.
  """
  @spec add(t(), source :: String.t() | [String.t(), ...], destination :: String.t(), options()) ::
          t()
  def add(%__MODULE__{} = pipeline, source, destination, options \\ []) do
    append_instruction(pipeline, "ADD", options, List.wrap(source) ++ [destination])
  end

  @doc """
  Adds a [`COPY`](https://docs.docker.com/reference/dockerfile/#copy) instruction.
  """
  @spec copy(t(), source :: String.t() | [String.t(), ...], destination :: String.t(), options()) ::
          t()
  def copy(%__MODULE__{} = pipeline, source, destination, options \\ []) do
    append_instruction(pipeline, "COPY", options, List.wrap(source) ++ [destination])
  end

  @doc """
  Adds a [`ENTRYPOINT`](https://docs.docker.com/reference/dockerfile/#entrypoint) instruction.
  """
  @spec entrypoint(t(), command :: String.t() | [String.t()]) :: t()
  def entrypoint(%__MODULE__{} = pipeline, command) do
    append_instruction(pipeline, "ENTRYPOINT", [], shell_or_exec_form(command))
  end

  @doc """
  Adds a [`VOLUME`](https://docs.docker.com/reference/dockerfile/#volume) instruction.
  """
  @spec volume(t(), volume :: String.t() | [String.t(), ...]) :: t()
  def volume(%__MODULE__{} = pipeline, volume) do
    append_instruction(pipeline, "VOLUME", [], shell_or_exec_form(volume))
  end

  @doc """
  Adds a [`USER`](https://docs.docker.com/reference/dockerfile/#user) instruction.
  """
  @spec user(t(), user :: String.t()) :: t()
  def user(%__MODULE__{} = pipeline, user) do
    append_instruction(pipeline, "USER", [], [user])
  end

  @doc """
  Adds a [`WORKDIR`](https://docs.docker.com/reference/dockerfile/#workdir) instruction.
  """
  @spec workdir(t(), workdir :: String.t()) :: t()
  def workdir(%__MODULE__{} = pipeline, workdir) do
    append_instruction(pipeline, "WORKDIR", [], [workdir])
  end

  @doc """
  Adds a [`ARG`](https://docs.docker.com/reference/dockerfile/#arg) instruction in the global scope.
  """
  @spec global_arg(t(), name :: String.t() | atom(), default_value :: nil | String.t()) :: t()
  def global_arg(%__MODULE__{} = pipeline, name, default_value \\ nil) do
    iargs =
      if default_value == nil do
        [to_string(name)]
      else
        ["#{name}=#{inspect(default_value)}"]
      end

    args = [{"ARG", [], iargs} | pipeline.args]
    args_ = Map.put(pipeline.args_, name, default_value)

    %__MODULE__{pipeline | args: args, args_: args_}
  end

  @doc """
  Adds a [`ARG`](https://docs.docker.com/reference/dockerfile/#arg) instruction in a stage scope.
  """
  @spec arg(t(), name :: String.t() | atom(), default_value :: nil | String.t()) :: t()
  def arg(%__MODULE__{} = pipeline, name, default_value \\ nil) do
    iargs =
      if default_value == nil do
        [to_string(name)]
      else
        ["#{name}=#{inspect(default_value)}"]
      end

    pipeline = append_instruction(pipeline, "ARG", [], iargs)

    {_, pipeline} =
      get_and_update_in(
        pipeline,
        [Access.key!(:stages), Access.at!(0), Access.key!(:args_)],
        &{&1, Map.put(&1, name, default_value)}
      )

    pipeline
  end

  @doc """
  Adds a [`STOPSIGNAL`](https://docs.docker.com/reference/dockerfile/#stopsignal) instruction.
  """
  @spec stopsignal(t(), name :: String.t()) :: t()
  def stopsignal(%__MODULE__{} = pipeline, signal) do
    append_instruction(pipeline, "STOPSIGNAL", [], [signal])
  end

  @doc """
  Adds a [`SHELL`](https://docs.docker.com/reference/dockerfile/#shell) instruction.
  """
  @spec shell(t(), command :: [String.t(), ...]) :: t()
  def shell(%__MODULE__{} = pipeline, command) do
    append_instruction(pipeline, "SHELL", [], command)
  end

  @doc """
  Adds a [`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck) instruction.
  """
  @spec healthcheck(t(), command :: nil | String.t() | [String.t(), ...], options :: options()) ::
          t()
  def healthcheck(%__MODULE__{} = pipeline, command, options \\ []) do
    if command == nil do
      append_instruction(pipeline, "HEALTHCHECK", [], ["NONE"])
    else
      command = shell_or_exec_form(command)
      append_instruction(pipeline, "HEALTHCHECK", options, ["CMD" | command])
    end
  end

  @doc """
  A basic [Here-documents](https://docs.docker.com/reference/dockerfile/#here-documents) string sigil.

  It expands to:

  ```
  <<EOT
  ... your string here ...
  EOT
  ```

  Example:

  ```
  run(pipeline, ~h\"\"\"
    if [ "$X" == "x" ]; then
      echo "x!"
    fi
  \"\"\")
  ```

  For more heredoc advance feature simply encode the heredoc yourself.
  """
  @spec sigil_h(str :: String.t(), opts :: Keyword.t()) :: String.t()
  def sigil_h(str, _opts) do
    "<<EOT\n#{str}\nEOT"
  end

  @doc false
  @spec append_instruction(t(), command(), options(), iargs()) :: t()
  def append_instruction(pipeline, command, options \\ [], iargs)

  def append_instruction(%__MODULE__{stages: []}, _, _, _) do
    raise("No stage defined. Use `stage/3` to start a stage first.")
  end

  def append_instruction(
        %__MODULE__{stages: [stage | rest_stages]} = pipeline,
        command,
        options,
        iargs
      ) do
    stage = %{stage | instructions: [{command, options, iargs} | stage.instructions]}
    %__MODULE__{pipeline | stages: [stage | rest_stages]}
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

  @spec serialize_stage(Stage.t()) :: String.t()
  defp serialize_stage(%Stage{instructions: instructions}) do
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
