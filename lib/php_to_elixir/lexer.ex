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

  # Catch-all: unexpected character
  defp do_tokenize(<<c::utf8, _rest::binary>>, line, col, _acc) do
    {:error, "Unexpected character '#{<<c::utf8>>}' at line #{line}, col #{col}"}
  end

  # --- Helpers ---

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
end
