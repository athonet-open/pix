defmodule Pix.Helper do
  @moduledoc false

  @spec uuid :: String.t()
  def uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end

  @spec compile_file(Path.t()) :: module()
  def compile_file(path) do
    Code.with_diagnostics([log: true], fn ->
      try do
        Code.compile_file(path)
      rescue
        err ->
          Pix.Log.error("Failed to compile #{path} due to errors #{inspect(err)}\n\n")
          System.halt(1)
      end
    end)
    |> case do
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
  end

  @spec eval_file(Path.t()) :: term()
  def eval_file(path) do
    Code.with_diagnostics([log: true], fn ->
      try do
        Code.eval_file(path)
      rescue
        err ->
          Pix.Log.error("Failed to evaluate #{path} due to errors #{inspect(err)}\n\n")
          System.halt(1)
      end
    end)
    |> case do
      # accept exactly one module per file
      {data, []} ->
        data

      {_, warnings} when warnings != [] ->
        Pix.Log.error("Failed to compile #{path} due to warnings:\n\n")

        for %{message: msg, position: {line, col}, severity: :warning} <- warnings,
            do: Pix.Log.error("warning: #{msg}\n  at line #{line}, column #{col}\n\n")

        System.halt(1)
    end
  end
end
