defmodule Pix.IO do
  @moduledoc false

  @doc """
  Ask a yes/no question. Returns `true` for yes, `false` for no.
  Default is used when user presses Enter without input.
  """
  @spec ask_yes_no(String.t(), boolean()) :: boolean()
  def ask_yes_no(question, default \\ true) do
    hint = if default, do: "[Y/n]", else: "[y/N]"
    prompt = "#{question} #{hint} "

    case get_input(prompt) do
      :eof -> default
      "" -> default
      input -> parse_yes_no(input, question, default)
    end
  end

  defp parse_yes_no(input, question, default) do
    case String.downcase(String.trim(input)) do
      v when v in ["y", "yes"] -> true
      v when v in ["n", "no"] -> false
      _ -> ask_yes_no(question, default)
    end
  end

  @doc """
  Ask the user to choose from a list of options.

  Options is a list of `{label, value}` tuples. To mark an option as the default,
  wrap it with `:default`: `{:default, {label, value}}`.

  Returns the value of the selected option.
  """
  @type option :: {String.t(), term()}
  @type option_with_default :: {:default, option()} | option()

  @spec ask_choice(String.t(), [option_with_default()]) :: term()
  def ask_choice(question, options) do
    IO.write("#{question}\n")

    options
    |> Enum.with_index(1)
    |> Enum.each(fn
      {{:default, {label, _value}}, idx} ->
        IO.write("  * #{idx}) #{label}\n")

      {{label, _value}, idx} ->
        IO.write("    #{idx}) #{label}\n")
    end)

    default_idx = resolve_default_index(options)
    default_hint = if default_idx != nil, do: " [#{default_idx}]", else: ""
    prompt = "\nChoose [1-#{length(options)}]#{default_hint}: "

    case get_input(prompt) do
      :eof -> resolve_default(options)
      "" -> resolve_default(options)
      input -> parse_choice(input, question, options)
    end
  end

  defp parse_choice(input, question, options) do
    case Integer.parse(String.trim(input)) do
      {n, ""} when n >= 1 and n <= length(options) ->
        options |> Enum.at(n - 1) |> extract_value()

      _ ->
        IO.write("  Invalid choice, please try again.\n")
        ask_choice(question, options)
    end
  end

  defp extract_value({:default, {_label, value}}), do: value
  defp extract_value({_label, value}), do: value

  defp resolve_default(options) do
    options
    |> Enum.find(&match?({:default, _}, &1))
    |> case do
      {:default, {_label, value}} -> value
      nil -> nil
    end
  end

  defp resolve_default_index(options) do
    options
    |> Enum.find_index(&match?({:default, _}, &1))
    |> case do
      nil -> nil
      idx -> idx + 1
    end
  end

  @doc """
  Ask for a string input with an optional default value.
  If a validator function is provided, it is called with the input.
  The validator should return `:ok` or `{:error, message}`.
  """
  @spec ask_string(String.t(), keyword()) :: String.t()
  def ask_string(question, opts \\ []) do
    default = Keyword.get(opts, :default, "")
    validator = Keyword.get(opts, :validator, fn _ -> :ok end)

    hint = if default != "", do: " (default: #{inspect(default)})", else: ""
    prompt = "#{question}#{hint}: "

    case get_input(prompt) do
      :eof -> default
      "" -> default
      input -> validate_string_input(String.trim(input), validator, question, opts)
    end
  end

  defp validate_string_input(value, validator, question, opts) do
    case validator.(value) do
      :ok ->
        value

      {:error, msg} ->
        IO.write("  #{msg}\n")
        ask_string(question, opts)
    end
  end

  @doc """
  Display a confirmation prompt with the given text. Returns true/false.
  """
  @spec confirm(String.t()) :: boolean()
  def confirm(question) do
    ask_yes_no(question, true)
  end

  @doc """
  Print a banner box with a title and ANSI-formatted body.
  Body is an iodata list that may include ANSI attributes.
  """
  @spec banner(String.t(), IO.ANSI.ansidata()) :: :ok
  def banner(title, body) do
    padding = 9
    width = String.length(title) + padding * 2
    border = String.duplicate("─", width)
    pad = String.duplicate(" ", padding)

    IO.write(
      IO.ANSI.format([
        :cyan,
        :bright,
        "\n╭#{border}╮\n",
        "│#{pad}#{title}#{pad}│\n",
        "╰#{border}╯\n",
        :reset
      ])
    )

    IO.write(IO.ANSI.format(["\n" | body]))
  end

  @doc """
  Print a green success message.
  """
  @spec success(String.t()) :: :ok
  def success(text) do
    IO.write(IO.ANSI.format([:green, "\n✓ #{text}\n", :reset]))
  end

  @doc """
  Print a section header.
  """
  @spec section(String.t()) :: :ok
  def section(title) do
    IO.write(
      IO.ANSI.format([
        :cyan,
        :bright,
        "\n── #{title} ",
        String.duplicate("─", max(50 - String.length(title), 2)),
        :reset,
        "\n\n"
      ])
    )
  end

  @doc """
  Print an informational note.
  """
  @spec note(String.t()) :: :ok
  def note(text) do
    IO.write(IO.ANSI.format([:faint, "  #{text}\n", :reset]))
  end

  @doc """
  Print plain indented text.
  """
  @spec text(String.t()) :: :ok
  def text(text) do
    IO.write("  #{text}\n")
  end

  @doc """
  Print content in a fenced block with an optional title.
  Content is indented and surrounded by faint separator lines.
  """
  @spec code_block(String.t(), String.t() | nil) :: :ok
  def code_block(content, title \\ nil) do
    header = if title, do: "─── #{title} ───", else: String.duplicate("─", 20)
    footer = String.duplicate("─", String.length(header))

    note(header)
    content |> String.split("\n") |> Enum.each(&IO.write("  #{&1}\n"))
    note(footer <> "\n")
  end

  @doc """
  Print a yellow notification box with a title and content lines.
  Lines are displayed inside a bordered box. Use empty strings for blank separator lines.
  """
  @spec notify_box(String.t(), [String.t()]) :: :ok
  def notify_box(title, lines) do
    box_width = 57

    header_rule = box_pad("─ #{title} ", "─", box_width)
    rule = String.duplicate("─", box_width)
    empty_line = String.duplicate(" ", box_width)

    content =
      Enum.map(lines, fn line ->
        ["│", box_pad(line, " ", box_width), "│", "\n"]
      end)

    IO.write(
      IO.ANSI.format([
        ["\n", :yellow],
        ["╭", header_rule, "╮", "\n"],
        ["│", empty_line, "│", "\n"],
        content,
        ["╰", rule, "╯", "\n"]
      ])
    )
  end

  defp box_pad(text, pad_char, width) do
    padding = max(width - String.length(text), 0)
    text <> String.duplicate(pad_char, padding)
  end

  @doc """
  Returns true if stdin is a TTY (interactive terminal).
  """
  @spec tty?() :: boolean()
  def tty? do
    case :io.columns() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Instead of IO.gets/1 we read from fd 0 via a Port because the escript runs
  # with -noinput (the BEAM's IO system never opens stdin). This is intentional:
  # `pix shell` spawns Docker via Port with :nouse_stdio, so Docker inherits
  # fd 0 for interactive shell access. Using {:fd, 0, 1} lets the wizard read
  # user input without going through the BEAM's IO server.

  @doc """
  Run `fun` with an open input port on fd 0.
  The port is closed automatically when `fun` returns (or raises).
  All `ask_*` calls must happen inside this scope.
  Re-entrant: nested calls reuse the existing port.
  """
  @spec with_input((-> result)) :: result when result: var
  def with_input(fun) do
    if Process.get(:pix_input_port) do
      fun.()
    else
      port = Port.open({:fd, 0, 1}, [:binary, {:line, 1024}])
      Process.put(:pix_input_port, port)

      try do
        fun.()
      after
        Port.close(port)
        Process.delete(:pix_input_port)
      end
    end
  end

  @spec get_input(String.t()) :: String.t() | :eof
  defp get_input(prompt) do
    IO.write(prompt)
    port = Process.get(:pix_input_port)

    receive do
      {^port, {:data, {:eol, line}}} -> line
      {^port, {:data, {:noeol, line}}} -> line
    end
  end
end
