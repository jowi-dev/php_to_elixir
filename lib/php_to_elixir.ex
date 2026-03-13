defmodule PhpToElixir do
  @moduledoc """
  PHP-to-Elixir transpiler.

  Converts PHP source code to Elixir source code through a pipeline of
  Lexer → Parser → Emitter.
  """

  alias PhpToElixir.{Emitter, Lexer, Parser}

  @doc """
  Transpiles PHP source code to Elixir source code.

  Takes a PHP source string and returns formatted Elixir code.

  ## Examples

      iex> PhpToElixir.transpile("<?php $x = 42;")
      {:ok, "x = 42\\n"}
  """
  @spec transpile(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def transpile(php_source) do
    with {:ok, tokens} <- Lexer.tokenize(php_source),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, code} <- Emitter.emit(ast) do
      {:ok, Code.format_string!(code) |> IO.iodata_to_binary() |> Kernel.<>("\n")}
    end
  end
end
