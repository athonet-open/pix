defmodule Pix.Command.Completion do
  @moduledoc false

  @fish_script_path Path.join(__DIR__, "../../../shell_completions/pix.fish")
  @external_resource @fish_script_path
  @fish_script File.read!(@fish_script_path)

  @spec script(OptionParser.argv()) :: :ok
  def script(argv) do
    case argv do
      ["fish"] ->
        IO.puts(@fish_script)

      _ ->
        IO.puts("Unsupported shell type")
        System.halt(1)
    end

    :ok
  end

  @spec complete(shell_type :: String.t(), OptionParser.argv(), Pix.Config.t()) :: :ok
  def complete("fish", argv, config) do
    case argv do
      ["pipeline"] ->
        config.pipelines
        |> Enum.map_join("\n", fn {pipeline_alias, %{pipeline_mod: mod}} ->
          [description | _] = mod.pipeline().description |> String.split("\n")
          "#{pipeline_alias}\t#{description}"
        end)
        |> IO.puts()

      ["target", pipeline] ->
        pipeline_mod = config.pipelines[pipeline].pipeline_mod

        pipeline_mod.pipeline().stages
        |> Enum.reject(& &1.private)
        |> Enum.map_join("\n", &"#{&1.stage}\t#{&1.description}")
        |> IO.puts()

      ["arg", pipeline, target] ->
        pipeline_mod = config.pipelines[pipeline].pipeline_mod

        pipeline_mod.pipeline().stages
        |> Enum.reject(& &1.private)
        |> Enum.find(&(&1.stage == target))
        |> then(& &1.args_)
        |> Map.keys()
        |> Enum.join("\n")
        |> IO.puts()

      _ ->
        :ok
    end
  end
end
