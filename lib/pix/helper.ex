defmodule Pix.Helper do
  @moduledoc false

  @spec uuid :: String.t()
  def uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end

  @spec compile_file(Path.t()) :: module()
  def compile_file(path) do
    case Code.with_diagnostics(fn -> Code.compile_file(path) end) do
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
  rescue
    err ->
      Pix.Log.error("Failed to compile #{path} due to errors:\n\n")
      Pix.Log.error(Exception.format(:error, err, __STACKTRACE__))
      Pix.Log.error("\n")
      System.halt(1)
  end
end
