defmodule Pix.Report do
  @moduledoc false

  @pers_term {__MODULE__, :enabled}

  @spec enable :: :ok
  def enable, do: :persistent_term.put(@pers_term, true)

  @spec disable :: :ok
  def disable, do: :persistent_term.put(@pers_term, false)

  @spec enabled? :: boolean()
  defp enabled?, do: :persistent_term.get(@pers_term, true)

  @spec info(IO.chardata()) :: :ok
  def info(msg) do
    if enabled?() do
      IO.write(msg)
    end
  end

  @spec error(IO.chardata()) :: :ok
  def error(msg) do
    if enabled?() do
      IO.write(IO.ANSI.format([:red, msg]))
    end
  end

  @spec internal(IO.chardata()) :: :ok
  def internal(msg) do
    if enabled?() do
      IO.write(IO.ANSI.format([:faint, msg]))
    end
  end

  @spec debug(IO.chardata()) :: :ok
  def debug(msg) do
    if System.get_env("PIX_DEBUG") == "true" and enabled?() do
      IO.write(IO.ANSI.format([:faint, msg]))
    end
  end
end
