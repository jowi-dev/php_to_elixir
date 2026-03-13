defmodule PhpToElixir.Parser do
  @moduledoc """
  Parses a list of tokens into an AST.

  Recursive descent parser. Takes the token list from `PhpToElixir.Lexer.tokenize/1`
  and returns `{:ok, ast}` or `{:error, reason}`.

  ## Usage

      {:ok, tokens} = PhpToElixir.Lexer.tokenize("<?php $x = 42;")
      {:ok, ast} = PhpToElixir.Parser.parse(tokens)
  """

  alias PhpToElixir.Token

  @doc """
  Parses a token list into an AST.

  Returns `{:ok, {:program, statements}}` or `{:error, reason}`.
  """
  @spec parse([Token.t()]) :: {:ok, PhpToElixir.Ast.program()} | {:error, String.t()}
  def parse(tokens) do
    {_open_tag, tokens} = expect(tokens, :open_tag)
    {statements, tokens} = parse_statements(tokens)
    {_eof, _tokens} = expect(tokens, :eof)
    {:ok, {:program, statements}}
  rescue
    e in RuntimeError -> {:error, e.message}
  end

  # --- Statement parsing ---

  defp parse_statements(tokens, acc \\ [])

  defp parse_statements([%Token{type: :eof} | _] = tokens, acc) do
    {Enum.reverse(acc), tokens}
  end

  defp parse_statements([%Token{type: :close_tag} | rest], acc) do
    {Enum.reverse(acc), rest ++ [%Token{type: :eof, value: nil, line: 0, col: 0}]}
  end

  defp parse_statements(tokens, acc) do
    {stmt, tokens} = parse_statement(tokens)
    parse_statements(tokens, [stmt | acc])
  end

  defp parse_statement(tokens) do
    case peek(tokens) do
      %Token{type: :if} -> parse_if(tokens)
      %Token{type: :foreach} -> parse_foreach(tokens)
      %Token{type: :switch} -> parse_switch(tokens)
      %Token{type: :break} -> parse_break(tokens)
      _ -> parse_expression_statement(tokens)
    end
  end

  defp parse_expression_statement(tokens) do
    {expr, tokens} = parse_expression(tokens)

    case peek(tokens) do
      %Token{type: :assign} ->
        {_assign, tokens} = expect(tokens, :assign)
        {value, tokens} = parse_expression(tokens)
        {_semi, tokens} = expect(tokens, :semicolon)
        {{:assign, expr, value}, tokens}

      %Token{type: :semicolon} ->
        {_semi, tokens} = expect(tokens, :semicolon)
        {{:expr_statement, expr}, tokens}

      _ ->
        {{:expr_statement, expr}, tokens}
    end
  end

  # --- If/elseif/else ---

  defp parse_if(tokens) do
    {_if, tokens} = expect(tokens, :if)
    {_lparen, tokens} = expect(tokens, :lparen)
    {condition, tokens} = parse_expression(tokens)
    {_rparen, tokens} = expect(tokens, :rparen)
    {then_body, tokens} = parse_body(tokens)
    {elseif_clauses, else_body, tokens} = parse_elseif_chain(tokens)
    {{:if, condition, then_body, elseif_clauses, else_body}, tokens}
  end

  defp parse_elseif_chain(tokens) do
    case peek(tokens) do
      %Token{type: :elseif} ->
        {_elseif, tokens} = expect(tokens, :elseif)
        {_lparen, tokens} = expect(tokens, :lparen)
        {condition, tokens} = parse_expression(tokens)
        {_rparen, tokens} = expect(tokens, :rparen)
        {body, tokens} = parse_body(tokens)
        {rest_elseifs, else_body, tokens} = parse_elseif_chain(tokens)
        {[{condition, body} | rest_elseifs], else_body, tokens}

      %Token{type: :else} ->
        {_else, tokens} = expect(tokens, :else)
        {body, tokens} = parse_body(tokens)
        {[], body, tokens}

      _ ->
        {[], nil, tokens}
    end
  end

  # --- Foreach ---

  defp parse_foreach(tokens) do
    {_foreach, tokens} = expect(tokens, :foreach)
    {_lparen, tokens} = expect(tokens, :lparen)
    {collection, tokens} = parse_expression(tokens)
    {_as, tokens} = expect(tokens, :as)
    {first_var, tokens} = parse_expression(tokens)

    {key_var, value_var, tokens} =
      case peek(tokens) do
        %Token{type: :double_arrow} ->
          {_arrow, tokens} = expect(tokens, :double_arrow)
          {val, tokens} = parse_expression(tokens)
          {first_var, val, tokens}

        _ ->
          {nil, first_var, tokens}
      end

    {_rparen, tokens} = expect(tokens, :rparen)
    {body, tokens} = parse_block(tokens)
    {{:foreach, collection, key_var, value_var, body}, tokens}
  end

  # --- Switch/case ---

  defp parse_switch(tokens) do
    {_switch, tokens} = expect(tokens, :switch)
    {_lparen, tokens} = expect(tokens, :lparen)
    {expr, tokens} = parse_expression(tokens)
    {_rparen, tokens} = expect(tokens, :rparen)
    {_lbrace, tokens} = expect(tokens, :lbrace)
    {clauses, tokens} = parse_case_clauses(tokens)
    {_rbrace, tokens} = expect(tokens, :rbrace)
    {{:switch, expr, clauses}, tokens}
  end

  defp parse_case_clauses(tokens, acc \\ [])

  defp parse_case_clauses([%Token{type: :rbrace} | _] = tokens, acc) do
    {Enum.reverse(acc), tokens}
  end

  defp parse_case_clauses(tokens, acc) do
    {clause, tokens} = parse_case_clause(tokens)
    parse_case_clauses(tokens, [clause | acc])
  end

  defp parse_case_clause(tokens) do
    case peek(tokens) do
      %Token{type: :case} ->
        {_case, tokens} = expect(tokens, :case)
        {expr, tokens} = parse_expression(tokens)
        {_colon, tokens} = expect(tokens, :colon)
        {body, tokens} = parse_case_body(tokens)
        {{:case_clause, expr, body}, tokens}

      %Token{type: :default} ->
        {_default, tokens} = expect(tokens, :default)
        {_colon, tokens} = expect(tokens, :colon)
        {body, tokens} = parse_case_body(tokens)
        {{:case_clause, :default, body}, tokens}
    end
  end

  defp parse_case_body(tokens, acc \\ [])

  defp parse_case_body([%Token{type: type} | _] = tokens, acc)
       when type in [:case, :default, :rbrace] do
    {Enum.reverse(acc), tokens}
  end

  defp parse_case_body(tokens, acc) do
    {stmt, tokens} = parse_statement(tokens)
    parse_case_body(tokens, [stmt | acc])
  end

  # --- Break ---

  defp parse_break(tokens) do
    {_break, tokens} = expect(tokens, :break)
    {_semi, tokens} = expect(tokens, :semicolon)
    {{:break}, tokens}
  end

  # --- Body parsing (braced or single statement) ---

  defp parse_body(tokens) do
    case peek(tokens) do
      %Token{type: :lbrace} -> parse_block(tokens)
      _ -> parse_single_statement_body(tokens)
    end
  end

  defp parse_single_statement_body(tokens) do
    {stmt, tokens} = parse_statement(tokens)
    {[stmt], tokens}
  end

  defp parse_block(tokens) do
    {_lbrace, tokens} = expect(tokens, :lbrace)
    {stmts, tokens} = parse_block_statements(tokens)
    {_rbrace, tokens} = expect(tokens, :rbrace)
    {stmts, tokens}
  end

  defp parse_block_statements(tokens, acc \\ [])

  defp parse_block_statements([%Token{type: :rbrace} | _] = tokens, acc) do
    {Enum.reverse(acc), tokens}
  end

  defp parse_block_statements(tokens, acc) do
    {stmt, tokens} = parse_statement(tokens)
    parse_block_statements(tokens, [stmt | acc])
  end

  # --- Expression parsing (precedence climbing) ---

  defp parse_expression(tokens) do
    parse_ternary(tokens)
  end

  # Ternary: expr ? expr : expr | expr ?: expr
  defp parse_ternary(tokens) do
    {left, tokens} = parse_null_coalesce(tokens)

    case peek(tokens) do
      %Token{type: :question} ->
        {_q, tokens} = expect(tokens, :question)

        case peek(tokens) do
          %Token{type: :colon} ->
            # Elvis operator: $x ?: 'default'
            {_colon, tokens} = expect(tokens, :colon)
            {right, tokens} = parse_ternary(tokens)
            {{:elvis, left, right}, tokens}

          _ ->
            {then_expr, tokens} = parse_expression(tokens)
            {_colon, tokens} = expect(tokens, :colon)
            {else_expr, tokens} = parse_ternary(tokens)
            {{:ternary, left, then_expr, else_expr}, tokens}
        end

      _ ->
        {left, tokens}
    end
  end

  # Null coalesce: left ?? right (right-associative)
  defp parse_null_coalesce(tokens) do
    {left, tokens} = parse_or(tokens)

    case peek(tokens) do
      %Token{type: :null_coalesce} ->
        {_op, tokens} = expect(tokens, :null_coalesce)
        {right, tokens} = parse_null_coalesce(tokens)
        {{:null_coalesce, left, right}, tokens}

      _ ->
        {left, tokens}
    end
  end

  # Logical OR: left || right
  defp parse_or(tokens) do
    {left, tokens} = parse_and(tokens)
    parse_or_rest(left, tokens)
  end

  defp parse_or_rest(left, tokens) do
    case peek(tokens) do
      %Token{type: :or} ->
        {_op, tokens} = expect(tokens, :or)
        {right, tokens} = parse_and(tokens)
        parse_or_rest({:binary_op, :||, left, right}, tokens)

      _ ->
        {left, tokens}
    end
  end

  # Logical AND: left && right
  defp parse_and(tokens) do
    {left, tokens} = parse_comparison(tokens)
    parse_and_rest(left, tokens)
  end

  defp parse_and_rest(left, tokens) do
    case peek(tokens) do
      %Token{type: :and} ->
        {_op, tokens} = expect(tokens, :and)
        {right, tokens} = parse_comparison(tokens)
        parse_and_rest({:binary_op, :&&, left, right}, tokens)

      _ ->
        {left, tokens}
    end
  end

  # Comparison: ==, !=, ===, !==
  defp parse_comparison(tokens) do
    {left, tokens} = parse_concatenation(tokens)

    case peek(tokens) do
      %Token{type: type} when type in [:eq, :neq, :strict_eq, :strict_neq] ->
        op = comparison_op(type)
        {_op, tokens} = expect(tokens, type)
        {right, tokens} = parse_concatenation(tokens)
        {{:binary_op, op, left, right}, tokens}

      _ ->
        {left, tokens}
    end
  end

  defp comparison_op(:eq), do: :==
  defp comparison_op(:neq), do: :!=
  defp comparison_op(:strict_eq), do: :===
  defp comparison_op(:strict_neq), do: :!==

  # String concatenation: left . right
  defp parse_concatenation(tokens) do
    {left, tokens} = parse_unary(tokens)
    parse_concatenation_rest(left, tokens)
  end

  defp parse_concatenation_rest(left, tokens) do
    case peek(tokens) do
      %Token{type: :dot} ->
        {_op, tokens} = expect(tokens, :dot)
        {right, tokens} = parse_unary(tokens)
        parse_concatenation_rest({:binary_op, :., left, right}, tokens)

      _ ->
        {left, tokens}
    end
  end

  # Unary: !expr, (int)expr, (float)expr, (string)expr
  defp parse_unary(tokens) do
    case peek(tokens) do
      %Token{type: :not} ->
        {_op, tokens} = expect(tokens, :not)
        {operand, tokens} = parse_unary(tokens)
        {{:unary_op, :!, operand}, tokens}

      %Token{type: cast_type} when cast_type in [:cast_int, :cast_float, :cast_string] ->
        {_cast, tokens} = expect(tokens, cast_type)
        {operand, tokens} = parse_unary(tokens)
        cast_atom = cast_type_atom(cast_type)
        {{:type_cast, cast_atom, operand}, tokens}

      _ ->
        parse_postfix(tokens)
    end
  end

  defp cast_type_atom(:cast_int), do: :int
  defp cast_type_atom(:cast_float), do: :float
  defp cast_type_atom(:cast_string), do: :string

  # Postfix: array access, property access, method call
  defp parse_postfix(tokens) do
    {expr, tokens} = parse_primary(tokens)
    parse_postfix_rest(expr, tokens)
  end

  defp parse_postfix_rest(expr, tokens) do
    case peek(tokens) do
      %Token{type: :lbracket} ->
        {_lb, tokens} = expect(tokens, :lbracket)

        case peek(tokens) do
          %Token{type: :rbracket} ->
            {_rb, tokens} = expect(tokens, :rbracket)
            parse_postfix_rest({:array_append, expr}, tokens)

          _ ->
            {key, tokens} = parse_expression(tokens)
            {_rb, tokens} = expect(tokens, :rbracket)
            parse_postfix_rest({:array_access, expr, key}, tokens)
        end

      %Token{type: :arrow} ->
        {_arrow, tokens} = expect(tokens, :arrow)
        %Token{type: :identifier, value: name} = peek(tokens)
        {_ident, tokens} = expect(tokens, :identifier)

        case peek(tokens) do
          %Token{type: :lparen} ->
            {args, tokens} = parse_argument_list(tokens)
            parse_postfix_rest({:method_call, expr, name, args}, tokens)

          _ ->
            parse_postfix_rest({:property_access, expr, name}, tokens)
        end

      _ ->
        {expr, tokens}
    end
  end

  # Primary expressions: literals, variables, function calls, grouped
  defp parse_primary(tokens) do
    case peek(tokens) do
      %Token{type: type} when type in [:integer, :float, :string, :interpolated_string] ->
        parse_literal(tokens)

      %Token{type: type} when type in [true, false, :null] ->
        parse_keyword_literal(tokens)

      %Token{type: :variable} ->
        parse_variable(tokens)

      %Token{type: type} when type in [:identifier, :isset, :empty] ->
        parse_callable(tokens)

      %Token{type: :array} ->
        parse_array_constructor(tokens)

      %Token{type: :lbracket} ->
        parse_bracket_array(tokens)

      %Token{type: :lparen} ->
        parse_grouped(tokens)

      %Token{type: type, line: line, col: col} ->
        raise "Unexpected token #{inspect(type)} at line #{line}, col #{col}"
    end
  end

  defp parse_literal(tokens) do
    %Token{type: type, value: val} = peek(tokens)
    {_tok, tokens} = expect(tokens, type)
    {{type, val}, tokens}
  end

  defp parse_keyword_literal(tokens) do
    case peek(tokens) do
      %Token{type: true} ->
        [_ | rest] = tokens
        {{:boolean, true}, rest}

      %Token{type: false} ->
        [_ | rest] = tokens
        {{:boolean, false}, rest}

      %Token{type: :null} ->
        {_tok, tokens} = expect(tokens, :null)
        {{nil}, tokens}
    end
  end

  defp parse_variable(tokens) do
    %Token{value: name} = peek(tokens)
    {_tok, tokens} = expect(tokens, :variable)
    {{:variable, name}, tokens}
  end

  defp parse_callable(tokens) do
    case peek(tokens) do
      %Token{type: :identifier, value: name} ->
        {_tok, tokens} = expect(tokens, :identifier)

        case peek(tokens) do
          %Token{type: :lparen} ->
            {args, tokens} = parse_argument_list(tokens)
            {{:function_call, name, args}, tokens}

          _ ->
            {{:function_call, name, []}, tokens}
        end

      %Token{type: type, value: name} when type in [:isset, :empty] ->
        [_ | tokens] = tokens
        {args, tokens} = parse_argument_list(tokens)
        {{:function_call, name, args}, tokens}
    end
  end

  defp parse_array_constructor(tokens) do
    [_ | tokens] = tokens
    {_lparen, tokens} = expect(tokens, :lparen)
    {entries, tokens} = parse_array_entries(tokens, :rparen)
    {_rparen, tokens} = expect(tokens, :rparen)
    {{:array_literal, entries}, tokens}
  end

  defp parse_bracket_array(tokens) do
    {_lb, tokens} = expect(tokens, :lbracket)
    {entries, tokens} = parse_array_entries(tokens, :rbracket)
    {_rb, tokens} = expect(tokens, :rbracket)
    {{:array_literal, entries}, tokens}
  end

  defp parse_grouped(tokens) do
    {_lp, tokens} = expect(tokens, :lparen)
    {expr, tokens} = parse_expression(tokens)
    {_rp, tokens} = expect(tokens, :rparen)
    {expr, tokens}
  end

  # --- Argument list: (expr, expr, ...) ---

  defp parse_argument_list(tokens) do
    {_lparen, tokens} = expect(tokens, :lparen)

    case peek(tokens) do
      %Token{type: :rparen} ->
        {_rparen, tokens} = expect(tokens, :rparen)
        {[], tokens}

      _ ->
        {args, tokens} = parse_comma_separated_expressions(tokens, :rparen)
        {_rparen, tokens} = expect(tokens, :rparen)
        {args, tokens}
    end
  end

  defp parse_comma_separated_expressions(tokens, terminator) do
    {expr, tokens} = parse_expression(tokens)
    parse_more_expressions(tokens, terminator, [expr])
  end

  defp parse_more_expressions(tokens, terminator, acc) do
    case peek(tokens) do
      %Token{type: ^terminator} ->
        {Enum.reverse(acc), tokens}

      %Token{type: :comma} ->
        {_comma, tokens} = expect(tokens, :comma)
        {expr, tokens} = parse_expression(tokens)
        parse_more_expressions(tokens, terminator, [expr | acc])
    end
  end

  # --- Array entries: key => value or bare value ---

  defp parse_array_entries(tokens, terminator) do
    case peek(tokens) do
      %Token{type: ^terminator} ->
        {[], tokens}

      _ ->
        parse_array_entry_list(tokens, terminator, [])
    end
  end

  defp parse_array_entry_list(tokens, terminator, acc) do
    {expr, tokens} = parse_expression(tokens)

    {entry, tokens} =
      case peek(tokens) do
        %Token{type: :double_arrow} ->
          {_arrow, tokens} = expect(tokens, :double_arrow)
          {value, tokens} = parse_expression(tokens)
          {{:array_entry, expr, value}, tokens}

        _ ->
          {expr, tokens}
      end

    case peek(tokens) do
      %Token{type: ^terminator} ->
        {Enum.reverse([entry | acc]), tokens}

      %Token{type: :comma} ->
        {_comma, tokens} = expect(tokens, :comma)

        case peek(tokens) do
          %Token{type: ^terminator} ->
            # trailing comma
            {Enum.reverse([entry | acc]), tokens}

          _ ->
            parse_array_entry_list(tokens, terminator, [entry | acc])
        end
    end
  end

  # --- Helpers ---

  defp peek([token | _]), do: token
  defp peek([]), do: raise("Unexpected end of token stream")

  defp expect([%Token{type: type} = token | rest], type), do: {token, rest}

  defp expect([%Token{type: actual, line: line, col: col} | _], expected) do
    raise "Expected #{inspect(expected)} but got #{inspect(actual)} at line #{line}, col #{col}"
  end

  defp expect([], expected) do
    raise "Expected #{inspect(expected)} but reached end of tokens"
  end
end
