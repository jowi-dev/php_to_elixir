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

  describe "Step 3: array access" do
    test "single key access" do
      assert parse_expr!("<?php $our['key'];") ==
               {:array_access, {:variable, "our"}, {:string, "key"}}
    end

    test "chained array access" do
      assert parse_expr!("<?php $our['a']['b'];") ==
               {:array_access,
                {:array_access, {:variable, "our"}, {:string, "a"}}, {:string, "b"}}
    end

    test "integer key access" do
      assert parse_expr!("<?php $arr[0];") ==
               {:array_access, {:variable, "arr"}, {:integer, 0}}
    end

    test "variable key access" do
      assert parse_expr!("<?php $arr[$key];") ==
               {:array_access, {:variable, "arr"}, {:variable, "key"}}
    end

    test "array append" do
      assert parse_expr!("<?php $arr[];") ==
               {:array_append, {:variable, "arr"}}
    end
  end

  describe "Step 4: property access" do
    test "simple property access" do
      assert parse_expr!("<?php $this->response;") ==
               {:property_access, {:variable, "this"}, "response"}
    end

    test "chained property access" do
      assert parse_expr!("<?php $obj->foo->bar;") ==
               {:property_access,
                {:property_access, {:variable, "obj"}, "foo"}, "bar"}
    end

    test "property access then array access" do
      assert parse_expr!("<?php $this->data['key'];") ==
               {:array_access,
                {:property_access, {:variable, "this"}, "data"}, {:string, "key"}}
    end
  end

  describe "Step 5: function calls" do
    test "function call with arguments" do
      assert parse_expr!("<?php in_array($x, $arr);") ==
               {:function_call, "in_array", [{:variable, "x"}, {:variable, "arr"}]}
    end

    test "isset as function call" do
      assert parse_expr!("<?php isset($our['key']);") ==
               {:function_call, "isset", [{:array_access, {:variable, "our"}, {:string, "key"}}]}
    end

    test "empty as function call" do
      assert parse_expr!("<?php empty($var);") ==
               {:function_call, "empty", [{:variable, "var"}]}
    end

    test "function call with no arguments" do
      assert parse_expr!("<?php time();") ==
               {:function_call, "time", []}
    end
  end

  describe "Step 6: method calls" do
    test "simple method call" do
      assert parse_expr!("<?php $this->method($arg);") ==
               {:method_call, {:variable, "this"}, "method", [{:variable, "arg"}]}
    end

    test "method call with no args" do
      assert parse_expr!("<?php $obj->getAll();") ==
               {:method_call, {:variable, "obj"}, "getAll", []}
    end

    test "chained method calls" do
      assert parse_expr!("<?php $obj->first()->second();") ==
               {:method_call,
                {:method_call, {:variable, "obj"}, "first", []}, "second", []}
    end

    test "method call on array access" do
      assert parse_expr!("<?php $arr['key']->method();") ==
               {:method_call,
                {:array_access, {:variable, "arr"}, {:string, "key"}}, "method", []}
    end

    test "property vs method distinguished by lparen" do
      # Without parens -> property access
      assert parse_expr!("<?php $obj->name;") ==
               {:property_access, {:variable, "obj"}, "name"}

      # With parens -> method call
      assert parse_expr!("<?php $obj->name();") ==
               {:method_call, {:variable, "obj"}, "name", []}
    end
  end
end
