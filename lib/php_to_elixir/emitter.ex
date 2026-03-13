defmodule PhpToElixir.Emitter do
  @moduledoc """
  Emits Elixir source code from a PHP AST.

  Walks the AST produced by `PhpToElixir.Parser` and generates
  equivalent Elixir code as a string.

  ## Usage

      {:ok, ast} = PhpToElixir.Parser.parse(tokens)
      {:ok, code} = PhpToElixir.Emitter.emit(ast)
  """

  @doc """
  Emits Elixir source code from a program AST.

  Returns `{:ok, code}` or `{:error, reason}`.
  """
  @spec emit(PhpToElixir.Ast.program()) :: {:ok, String.t()} | {:error, String.t()}
  def emit({:program, statements}) do
    code =
      statements
      |> Enum.map(&emit_statement/1)
      |> Enum.join("\n")

    {:ok, code}
  rescue
    e in RuntimeError -> {:error, e.message}
  end

  # --- Statements ---

  defp emit_statement({:expr_statement, expr}), do: emit_expr(expr)

  # --- Expressions ---

  @doc false
  def emit_expr({:integer, val}), do: Integer.to_string(val)
  def emit_expr({:float, val}), do: Float.to_string(val)
  def emit_expr({:string, val}), do: inspect(val)

  def emit_expr({:interpolated_string, parts}) do
    inner =
      Enum.map_join(parts, fn
        str when is_binary(str) -> str
        {:variable, name} -> "\#{#{name}}"
      end)

    "\"#{inner}\""
  end

  def emit_expr({:boolean, true}), do: "true"
  def emit_expr({:boolean, false}), do: "false"
  def emit_expr({nil}), do: "nil"

  def emit_expr({:variable, name}), do: name

  def emit_expr({:array_literal, []}) do
    "%{}"
  end

  def emit_expr({:array_literal, entries}) do
    case hd(entries) do
      {:array_entry, _, _} -> emit_map(entries)
      _ -> emit_list(entries)
    end
  end

  defp emit_map(entries) do
    inner =
      Enum.map_join(entries, ", ", fn {:array_entry, key, val} ->
        "#{emit_expr(key)} => #{emit_expr(val)}"
      end)

    "%{#{inner}}"
  end

  defp emit_list(entries) do
    inner = Enum.map_join(entries, ", ", &emit_expr/1)
    "[#{inner}]"
  end
end
