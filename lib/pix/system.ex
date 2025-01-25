defmodule Pix.System do
  @moduledoc false

  # Ref: https://hexdocs.pm/elixir/Port.html#module-zombie-operating-system-processes
  @cmd_wrapper """
  #!/usr/bin/env bash

  # Start the program in the background
  exec "$@" &
  pid1=$!

  # Silence warnings from here on
  exec >/dev/null 2>&1

  # Read from stdin in the background and
  # kill running program when stdin closes
  exec 0<&0 $(
    while read; do :; done
    kill -KILL $pid1
  ) &
  pid2=$!

  # Clean up
  wait $pid1
  ret=$?
  kill -KILL $pid2
  exit $ret
  """

  @spec setup :: :ok
  def setup do
    install_cmd_wrapper_script()
  end

  @spec install_cmd_wrapper_script :: :ok
  defp install_cmd_wrapper_script do
    path = Path.join(System.tmp_dir!(), "cmd_wrapper.sh")

    File.write!(path, @cmd_wrapper)
    File.chmod!(path, 0o700)

    :persistent_term.put({:pix, :cmd_wrapper_path}, path)

    :ok
  end

  @spec cmd_wrapper_path :: Path.t()
  def cmd_wrapper_path do
    :persistent_term.get({:pix, :cmd_wrapper_path})
  end
end
