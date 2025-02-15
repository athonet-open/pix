defmodule Pix.Report do
  @moduledoc false

  @spec info(IO.chardata()) :: :ok
  def info(msg), do: IO.write(msg)

  @spec error(IO.chardata()) :: :ok
  def error(msg), do: IO.write(IO.ANSI.format([:red, msg]))

  @spec internal(IO.chardata()) :: :ok
  def internal(msg), do: IO.write(IO.ANSI.format([:faint, msg]))

  @spec debug(IO.chardata()) :: :ok
  def debug(msg) do
    if System.get_env("PIX_DEBUG") == "true" do
      IO.write(IO.ANSI.format([:faint, msg]))
    end
  end
end
