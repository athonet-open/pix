defmodule Pix.Helper do
  @moduledoc false

  @spec uuid :: String.t()
  def uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end

  @spec compile_file(Path.t()) :: module()
  def compile_file(path) do
    res =
      try do
        Code.compile_file(path)
      rescue
        e ->
          Exception.message(e) |> IO.puts()
          System.halt(1)
      end

    case res do
      # accept exactly one module per file
      [{module, _}] ->
        module

      _ ->
        raise "Expected #{path} to define exactly one module per file"
    end
  end

  @spec eval_file(Path.t()) :: term()
  def eval_file(path) do
    Code.eval_file(path)
  rescue
    e ->
      Exception.message(e) |> IO.puts()
      System.halt(1)
  end
end
