defmodule PhpToElixir.ParserTest do
  use ExUnit.Case, async: true

  alias PhpToElixir.Lexer
  alias PhpToElixir.Parser

  # Helper: tokenize + parse, return the AST
  defp parse!(input) do
    {:ok, tokens} = Lexer.tokenize(input)
    {:ok, ast} = Parser.parse(tokens)
    ast
  end

  # Helper: parse and extract the single statement from the program
  defp parse_stmt!(input) do
    {:program, [stmt]} = parse!(input)
    stmt
  end

  # Helper: parse and extract the expression from a single expr_statement
  defp parse_expr!(input) do
    {:expr_statement, expr} = parse_stmt!(input)
    expr
  end

  describe "Step 1: literals and variables" do
    test "integer literal" do
      assert parse_expr!("<?php 42;") == {:integer, 42}
    end

    test "float literal" do
      assert parse_expr!("<?php 3.14;") == {:float, 3.14}
    end

    test "single-quoted string literal" do
      assert parse_expr!("<?php 'hello';") == {:string, "hello"}
    end

    test "double-quoted string literal" do
      assert parse_expr!(~s(<?php "world";)) == {:string, "world"}
    end

    test "boolean true" do
      assert parse_expr!("<?php true;") == {:boolean, true}
    end

    test "boolean false" do
      assert parse_expr!("<?php false;") == {:boolean, false}
    end

    test "null" do
      assert parse_expr!("<?php null;") == {nil}
    end

    test "variable" do
      assert parse_expr!("<?php $foo;") == {:variable, "foo"}
    end

    test "program wraps statements" do
      assert {:program, [{:expr_statement, {:integer, 42}}]} = parse!("<?php 42;")
    end
  end

  describe "Step 2: array literals" do
    test "array() with key-value pairs" do
      assert parse_expr!("<?php array('a' => 'b');") ==
               {:array_literal, [{:array_entry, {:string, "a"}, {:string, "b"}}]}
    end

    test "short array syntax with bare values" do
      assert parse_expr!("<?php ['a', 'b'];") ==
               {:array_literal, [{:string, "a"}, {:string, "b"}]}
    end

    test "mixed key-value and bare entries" do
      assert parse_expr!("<?php array('key' => 'val', 'bare');") ==
               {:array_literal,
                [{:array_entry, {:string, "key"}, {:string, "val"}}, {:string, "bare"}]}
    end

    test "empty array" do
      assert parse_expr!("<?php array();") == {:array_literal, []}
    end

    test "empty short array" do
      assert parse_expr!("<?php [];") == {:array_literal, []}
    end

    test "nested array" do
      assert parse_expr!("<?php ['a' => ['b']];") ==
               {:array_literal,
                [
                  {:array_entry, {:string, "a"}, {:array_literal, [{:string, "b"}]}}
                ]}
    end
  end
end
