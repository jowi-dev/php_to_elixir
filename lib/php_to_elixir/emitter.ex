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

  defp emit_statement({:expr_statement, {:property_access, {:variable, "this"}, prop}}) do
    "# TODO: $this->#{prop}"
  end

  defp emit_statement({:expr_statement, {:method_call, {:variable, "this"}, method, _}}) do
    "# TODO: $this->#{method}()"
  end

  defp emit_statement({:expr_statement, {:function_call, name, args}}) do
    case PhpToElixir.Builtins.translate(name, args) do
      {:ok, code} -> code
      :unknown -> "# TODO: #{name}(#{Enum.map_join(args, ", ", &emit_expr/1)})"
    end
  end

  defp emit_statement({:expr_statement, expr}), do: emit_expr(expr)
  defp emit_statement({:break}), do: nil

  defp emit_statement({:assign, {:variable, name}, value}) do
    "#{name} = #{emit_expr(value)}"
  end

  defp emit_statement({:assign, {:property_access, {:variable, "this"}, prop}, _value}) do
    "# TODO: $this->#{prop} = ..."
  end

  defp emit_statement({:assign, {:function_call, "list", targets}, value}) do
    vars = Enum.map_join(targets, ", ", &emit_lvalue/1)
    "[#{vars}] = #{emit_expr(value)}"
  end

  defp emit_statement({:assign, {:array_access, target, key}, value}) do
    {root, keys} = collect_access_chain(target, [key])
    root_name = emit_expr(root)

    case keys do
      [single_key] ->
        "#{root_name} = Map.put(#{root_name}, #{emit_expr(single_key)}, #{emit_expr(value)})"

      keys ->
        keys_str = Enum.map_join(keys, ", ", &emit_expr/1)
        "#{root_name} = put_in(#{root_name}, [#{keys_str}], #{emit_expr(value)})"
    end
  end

  defp emit_statement({:if, condition, then_body, [], nil}) do
    body = emit_body(then_body)
    "our = if #{emit_expr(condition)} do\n#{body}\nour\nelse\nour\nend"
  end

  defp emit_statement({:if, condition, then_body, [], else_body}) do
    then_str = emit_body(then_body)
    else_str = emit_body(else_body)
    "our = if #{emit_expr(condition)} do\n#{then_str}\nour\nelse\n#{else_str}\nour\nend"
  end

  defp emit_statement({:if, condition, then_body, elseif_clauses, else_body}) do
    first_branch = "#{emit_expr(condition)} ->\n#{emit_body(then_body)}\nour"

    elseif_branches =
      Enum.map(elseif_clauses, fn {cond_expr, body} ->
        "#{emit_expr(cond_expr)} ->\n#{emit_body(body)}\nour"
      end)

    default_branch =
      case else_body do
        nil -> "true ->\nour"
        body -> "true ->\n#{emit_body(body)}\nour"
      end

    all_branches = Enum.join([first_branch | elseif_branches] ++ [default_branch], "\n")
    "our = cond do\n#{all_branches}\nend"
  end

  defp emit_statement({:foreach, collection, key_var, value_var, body}) do
    pattern =
      case key_var do
        nil -> "#{emit_expr(value_var)}, our"
        _ -> "{#{emit_expr(key_var)}, #{emit_expr(value_var)}}, our"
      end

    body_str = emit_body(body)
    "our = Enum.reduce(#{emit_expr(collection)}, our, fn #{pattern} ->\n#{body_str}\nour\nend)"
  end

  defp emit_statement({:switch, expr, clauses}) do
    branches =
      Enum.map_join(clauses, "\n", fn
        {:case_clause, :default, body} ->
          body_stmts = emit_body(strip_breaks(body))
          "true ->\n#{body_stmts}\nour"

        {:case_clause, case_expr, body} ->
          body_stmts = emit_body(strip_breaks(body))
          "#{emit_expr(expr)} == #{emit_expr(case_expr)} ->\n#{body_stmts}\nour"
      end)

    "our = cond do\n#{branches}\nend"
  end

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
  def emit_expr({:array_literal, []}), do: "%{}"

  def emit_expr({:array_literal, entries}) do
    case hd(entries) do
      {:array_entry, _, _} -> emit_map(entries)
      _ -> emit_list(entries)
    end
  end

  def emit_expr({:array_access, target, key}) do
    "#{emit_expr(target)}[#{emit_expr(key)}]"
  end

  def emit_expr({:binary_op, :., left, right}) do
    "#{emit_concat_operand(left)} <> #{emit_concat_operand(right)}"
  end

  def emit_expr({:binary_op, op, left, right}) do
    "#{emit_expr(left)} #{op} #{emit_expr(right)}"
  end

  def emit_expr({:unary_op, :!, operand}), do: "!#{emit_expr(operand)}"

  def emit_expr({:ternary, condition, then_expr, else_expr}) do
    "if(#{emit_expr(condition)}, do: #{emit_expr(then_expr)}, else: #{emit_expr(else_expr)})"
  end

  def emit_expr({:null_coalesce, left, right}), do: "#{emit_expr(left)} || #{emit_expr(right)}"
  def emit_expr({:elvis, left, right}), do: "#{emit_expr(left)} || #{emit_expr(right)}"
  def emit_expr({:type_cast, :int, expr}), do: "to_integer(#{emit_expr(expr)})"
  def emit_expr({:type_cast, :float, expr}), do: "to_float(#{emit_expr(expr)})"
  def emit_expr({:type_cast, :string, expr}), do: "to_string(#{emit_expr(expr)})"

  def emit_expr({:property_access, target, prop}), do: "#{emit_expr(target)}[:#{prop}]"
  def emit_expr({:method_call, _target, _method, _args}), do: "nil"

  def emit_expr({:function_call, name, args}) do
    case PhpToElixir.Builtins.translate(name, args) do
      {:ok, code} -> code
      :unknown -> emit_unknown_function_call(name, args)
    end
  end

  # --- Private helpers ---

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

  defp emit_concat_operand({:string, _} = expr), do: emit_expr(expr)
  defp emit_concat_operand({:interpolated_string, _} = expr), do: emit_expr(expr)
  defp emit_concat_operand(expr), do: "to_string(#{emit_expr(expr)})"

  defp emit_unknown_function_call(_name, _args), do: "nil"

  defp emit_lvalue({:variable, name}), do: name
  defp emit_lvalue({:array_access, target, key}), do: "#{emit_expr(target)}[#{emit_expr(key)}]"
  defp emit_lvalue(expr), do: emit_expr(expr)

  defp collect_access_chain({:array_access, inner_target, inner_key}, keys) do
    collect_access_chain(inner_target, [inner_key | keys])
  end

  defp collect_access_chain(root, keys), do: {root, keys}

  defp emit_body(statements) do
    statements
    |> Enum.map(&emit_statement/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp strip_breaks(statements) do
    Enum.reject(statements, &match?({:break}, &1))
  end
end
