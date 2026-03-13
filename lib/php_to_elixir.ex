defmodule PhpToElixir do
  @moduledoc """
  PHP-to-Elixir transpiler.

  Converts PHP source code to Elixir source code through a pipeline of
  Lexer → Parser → Emitter.
  """

  alias PhpToElixir.{Emitter, Lexer, Parser}

  @doc """
  Parses PHP source code into an AST without emitting Elixir code.

  Returns the raw AST for inspection or custom processing.

  ## Examples

      iex> PhpToElixir.parse("<?php $x = 42;")
      {:ok, {:program, [{:assign, {:variable, "x"}, {:integer, 42}}]}}
  """
  @spec parse(String.t()) :: {:ok, PhpToElixir.Ast.program()} | {:error, String.t()}
  def parse(php_source) do
    with {:ok, tokens} <- Lexer.tokenize(php_source) do
      Parser.parse(tokens)
    end
  end

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
