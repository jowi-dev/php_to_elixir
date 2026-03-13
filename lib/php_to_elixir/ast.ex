defmodule PhpToElixir.Ast do
  @moduledoc """
  AST node type definitions for the PHP-to-Elixir transpiler.

  All nodes are plain tagged tuples — no structs. This module defines the
  contract between the parser and emitter.

  ## Statements

      {:program, [statement]}
      {:if, condition, then_body, [elseif_clause], else_body | nil}
      {:foreach, collection, key_var | nil, value_var, body}
      {:switch, expr, [case_clause]}
      {:case_clause, expr | :default, body}
      {:break}
      {:assign, target, value}
      {:expr_statement, expr}

  ## Expressions

      {:binary_op, op, left, right}     — op: :==, :!=, :===, :!==, :||, :&&, :.
      {:unary_op, :!, operand}
      {:ternary, condition, then_expr, else_expr}
      {:null_coalesce, left, right}
      {:elvis, left, right}
      {:type_cast, :int | :float | :string, expr}

  ## Access

      {:variable, name}
      {:array_access, target, key}
      {:property_access, target, property}
      {:method_call, target, method, args}
      {:function_call, name, args}
      {:array_append, target}

  ## Literals

      {:string, value}
      {:interpolated_string, parts}
      {:integer, value}
      {:float, value}
      {:boolean, true | false}
      {:nil}
      {:array_literal, entries}
      {:array_entry, key, value}
  """

  @type program :: {:program, [statement]}

  @type statement ::
          if_stmt
          | foreach_stmt
          | switch_stmt
          | break_stmt
          | assign_stmt
          | expr_statement

  @type if_stmt :: {:if, expr, [statement], [elseif_clause], [statement] | nil}
  @type elseif_clause :: {expr, [statement]}
  @type foreach_stmt :: {:foreach, expr, expr | nil, expr, [statement]}
  @type switch_stmt :: {:switch, expr, [case_clause]}
  @type case_clause :: {:case_clause, expr | :default, [statement]}
  @type break_stmt :: {:break}
  @type assign_stmt :: {:assign, expr, expr}
  @type expr_statement :: {:expr_statement, expr}

  @type expr ::
          binary_op
          | unary_op
          | ternary
          | null_coalesce
          | elvis
          | type_cast
          | variable
          | array_access
          | property_access
          | method_call
          | function_call
          | array_append
          | literal

  @type binary_op :: {:binary_op, atom, expr, expr}
  @type unary_op :: {:unary_op, :!, expr}
  @type ternary :: {:ternary, expr, expr, expr}
  @type null_coalesce :: {:null_coalesce, expr, expr}
  @type elvis :: {:elvis, expr, expr}
  @type type_cast :: {:type_cast, :int | :float | :string, expr}

  @type variable :: {:variable, String.t()}
  @type array_access :: {:array_access, expr, expr}
  @type property_access :: {:property_access, expr, String.t()}
  @type method_call :: {:method_call, expr, String.t(), [expr]}
  @type function_call :: {:function_call, String.t(), [expr]}
  @type array_append :: {:array_append, expr}

  @type literal ::
          {:string, String.t()}
          | {:interpolated_string, [String.t() | {:variable, String.t()}]}
          | {:integer, integer}
          | {:float, float}
          | {:boolean, boolean}
          | {nil}
          | array_literal

  @type array_literal :: {:array_literal, [array_entry | expr]}
  @type array_entry :: {:array_entry, expr, expr}
end
