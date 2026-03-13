defmodule PhpToElixir.Lexer do
  @moduledoc """
  Tokenizes PHP source strings into a list of tokens.

  ## Usage

      iex> PhpToElixir.Lexer.tokenize("<?php ?>")
      {:ok, [%PhpToElixir.Token{type: :open_tag, value: "<?php", line: 1, col: 1},
             %PhpToElixir.Token{type: :close_tag, value: "?>", line: 1, col: 7},
             %PhpToElixir.Token{type: :eof, value: nil, line: 1, col: 9}]}
  """

  alias PhpToElixir.Token

  @doc """
  Tokenizes a PHP source string into a list of tokens.

  Returns `{:ok, tokens}` on success or `{:error, reason}` on failure.
  The token list always ends with an `:eof` token.
  """
  @spec tokenize(String.t()) :: {:ok, [Token.t()]} | {:error, String.t()}
  def tokenize(input) do
    do_tokenize(input, 1, 1, [])
  end

  # End of input
  defp do_tokenize("", line, col, acc) do
    eof = %Token{type: :eof, value: nil, line: line, col: col}
    {:ok, Enum.reverse([eof | acc])}
  end

  # Whitespace — space, tab, carriage return
  defp do_tokenize(<<c, rest::binary>>, line, col, acc) when c in [?\s, ?\t, ?\r] do
    do_tokenize(rest, line, col + 1, acc)
  end

  # Newline
  defp do_tokenize(<<?\n, rest::binary>>, line, _col, acc) do
    do_tokenize(rest, line + 1, 1, acc)
  end

  # Single-line comment: //
  defp do_tokenize(<<?/, ?/, rest::binary>>, line, _col, acc) do
    rest = skip_until_newline(rest)
    do_tokenize(rest, line + 1, 1, acc)
  end

  # Hash comment: #
  defp do_tokenize(<<?#, rest::binary>>, line, _col, acc) do
    rest = skip_until_newline(rest)
    do_tokenize(rest, line + 1, 1, acc)
  end

  # Block comment: /* ... */
  defp do_tokenize(<<?/, ?*, rest::binary>>, line, col, acc) do
    case skip_block_comment(rest, line, col + 2) do
      {:ok, rest, new_line, new_col} ->
        do_tokenize(rest, new_line, new_col, acc)

      {:error, _reason} = error ->
        error
    end
  end

  # Open tag: <?php
  defp do_tokenize(<<?<, ??, ?p, ?h, ?p, rest::binary>>, line, col, acc) do
    token = %Token{type: :open_tag, value: "<?php", line: line, col: col}
    do_tokenize(rest, line, col + 5, [token | acc])
  end

  # Close tag: ?>
  defp do_tokenize(<<??, ?>, rest::binary>>, line, col, acc) do
    token = %Token{type: :close_tag, value: "?>", line: line, col: col}
    do_tokenize(rest, line, col + 2, [token | acc])
  end

  # Numbers: integers and floats
  defp do_tokenize(<<c, _rest::binary>> = input, line, col, acc) when c in ?0..?9 do
    {digits, rest} = scan_digits(input, "")

    case rest do
      <<?., next, rest2::binary>> when next in ?0..?9 ->
        {decimals, rest3} = scan_digits(<<next, rest2::binary>>, "")
        raw = digits <> "." <> decimals
        token = %Token{type: :float, value: String.to_float(raw), line: line, col: col}
        do_tokenize(rest3, line, col + String.length(raw), [token | acc])

      _ ->
        token = %Token{type: :integer, value: String.to_integer(digits), line: line, col: col}
        do_tokenize(rest, line, col + String.length(digits), [token | acc])
    end
  end

  # Single-quoted string
  defp do_tokenize(<<?\', rest::binary>>, line, col, acc) do
    case scan_single_quoted_string(rest, line, col + 1, "") do
      {:ok, value, rest, new_line, new_col} ->
        token = %Token{type: :string, value: value, line: line, col: col}
        do_tokenize(rest, new_line, new_col, [token | acc])

      {:error, _reason} = error ->
        error
    end
  end

  # Double-quoted string
  defp do_tokenize(<<?\", rest::binary>>, line, col, acc) do
    case scan_double_quoted_string(rest, line, col + 1, []) do
      {:ok, parts, rest, new_line, new_col} ->
        token = build_string_token(parts, line, col)
        do_tokenize(rest, new_line, new_col, [token | acc])

      {:error, _reason} = error ->
        error
    end
  end

  # Variable: $identifier
  defp do_tokenize(<<?$, c, rest::binary>>, line, col, acc)
       when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {name, rest2} = scan_identifier_chars(rest, <<c>>)
    token = %Token{type: :variable, value: name, line: line, col: col}
    do_tokenize(rest2, line, col + 1 + String.length(name), [token | acc])
  end

  # Identifiers and keywords
  defp do_tokenize(<<c, _rest::binary>> = input, line, col, acc)
       when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {name, rest} = scan_identifier_chars(input, "")
    type = keyword_type(name)
    token = %Token{type: type, value: name, line: line, col: col}
    do_tokenize(rest, line, col + String.length(name), [token | acc])
  end

  # Catch-all: unexpected character
  defp do_tokenize(<<c::utf8, _rest::binary>>, line, col, _acc) do
    {:error, "Unexpected character '#{<<c::utf8>>}' at line #{line}, col #{col}"}
  end

  # --- Helpers ---

  @keywords %{
    "if" => :if,
    "elseif" => :elseif,
    "else" => :else,
    "foreach" => :foreach,
    "as" => :as,
    "switch" => :switch,
    "case" => :case,
    "default" => :default,
    "break" => :break,
    "true" => true,
    "false" => false,
    "null" => :null,
    "isset" => :isset,
    "empty" => :empty,
    "array" => :array
  }

  defp keyword_type(name), do: Map.get(@keywords, name, :identifier)

  defp skip_until_newline(<<?\n, rest::binary>>), do: rest
  defp skip_until_newline(<<_, rest::binary>>), do: skip_until_newline(rest)
  defp skip_until_newline(<<>>), do: <<>>

  defp skip_block_comment(<<?*, ?/, rest::binary>>, line, col) do
    {:ok, rest, line, col + 2}
  end

  defp skip_block_comment(<<?\n, rest::binary>>, line, _col) do
    skip_block_comment(rest, line + 1, 1)
  end

  defp skip_block_comment(<<_, rest::binary>>, line, col) do
    skip_block_comment(rest, line, col + 1)
  end

  defp skip_block_comment(<<>>, line, col) do
    {:error, "Unterminated block comment at line #{line}, col #{col}"}
  end

  defp scan_digits(<<c, rest::binary>>, acc) when c in ?0..?9 do
    scan_digits(rest, acc <> <<c>>)
  end

  defp scan_digits(rest, acc), do: {acc, rest}

  # Single-quoted string: only \' and \\ are escape sequences
  defp scan_single_quoted_string(<<?\\, ?\', rest::binary>>, line, col, acc) do
    scan_single_quoted_string(rest, line, col + 2, acc <> "'")
  end

  defp scan_single_quoted_string(<<?\\, ?\\, rest::binary>>, line, col, acc) do
    scan_single_quoted_string(rest, line, col + 2, acc <> "\\")
  end

  defp scan_single_quoted_string(<<?\', rest::binary>>, line, col, acc) do
    {:ok, acc, rest, line, col + 1}
  end

  defp scan_single_quoted_string(<<?\n, rest::binary>>, line, _col, acc) do
    scan_single_quoted_string(rest, line + 1, 1, acc <> "\n")
  end

  defp scan_single_quoted_string(<<c::utf8, rest::binary>>, line, col, acc) do
    scan_single_quoted_string(rest, line, col + 1, acc <> <<c::utf8>>)
  end

  defp scan_single_quoted_string(<<>>, line, col, _acc) do
    {:error, "Unterminated single-quoted string at line #{line}, col #{col}"}
  end

  # Double-quoted string scanning
  # Accumulates a list of parts: strings and {:variable, name} tuples

  # Closing quote
  defp scan_double_quoted_string(<<?\", rest::binary>>, line, col, parts) do
    {:ok, finalize_string_parts(parts), rest, line, col + 1}
  end

  # Escape sequences
  defp scan_double_quoted_string(<<?\\, ?n, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "\n"))
  end

  defp scan_double_quoted_string(<<?\\, ?t, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "\t"))
  end

  defp scan_double_quoted_string(<<?\\, ?r, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "\r"))
  end

  defp scan_double_quoted_string(<<?\\, ?\\, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "\\"))
  end

  defp scan_double_quoted_string(<<?\\, ?\", rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "\""))
  end

  defp scan_double_quoted_string(<<?\\, ?$, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 2, add_char_to_parts(parts, "$"))
  end

  # Interpolation: {$variable}
  defp scan_double_quoted_string(<<?{, ?$, rest::binary>>, line, col, parts) do
    {name, rest2} = scan_identifier_chars(rest, "")
    <<?\}, rest3::binary>> = rest2
    new_parts = [{:variable, name} | parts]
    # { + $ + name + }
    scan_double_quoted_string(rest3, line, col + 2 + String.length(name) + 1, new_parts)
  end

  # Newline inside double-quoted string
  defp scan_double_quoted_string(<<?\n, rest::binary>>, line, _col, parts) do
    scan_double_quoted_string(rest, line + 1, 1, add_char_to_parts(parts, "\n"))
  end

  # Regular character
  defp scan_double_quoted_string(<<c::utf8, rest::binary>>, line, col, parts) do
    scan_double_quoted_string(rest, line, col + 1, add_char_to_parts(parts, <<c::utf8>>))
  end

  defp scan_double_quoted_string(<<>>, line, col, _parts) do
    {:error, "Unterminated double-quoted string at line #{line}, col #{col}"}
  end

  # Add a character to the current string segment in parts accumulator
  defp add_char_to_parts([str | rest], char) when is_binary(str), do: [str <> char | rest]
  defp add_char_to_parts(parts, char), do: [char | parts]

  # Finalize parts: reverse and merge adjacent strings
  defp finalize_string_parts(parts) do
    parts
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  # Build appropriate token based on parts
  defp build_string_token([], line, col) do
    %Token{type: :string, value: "", line: line, col: col}
  end

  defp build_string_token([single_string], line, col) when is_binary(single_string) do
    %Token{type: :string, value: single_string, line: line, col: col}
  end

  defp build_string_token(parts, line, col) do
    %Token{type: :interpolated_string, value: parts, line: line, col: col}
  end

  defp scan_identifier_chars(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    scan_identifier_chars(rest, acc <> <<c>>)
  end

  defp scan_identifier_chars(rest, acc), do: {acc, rest}
end
