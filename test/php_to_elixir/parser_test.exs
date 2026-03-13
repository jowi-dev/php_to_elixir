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
               {:array_access, {:array_access, {:variable, "our"}, {:string, "a"}},
                {:string, "b"}}
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
               {:property_access, {:property_access, {:variable, "obj"}, "foo"}, "bar"}
    end

    test "property access then array access" do
      assert parse_expr!("<?php $this->data['key'];") ==
               {:array_access, {:property_access, {:variable, "this"}, "data"}, {:string, "key"}}
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
               {:method_call, {:method_call, {:variable, "obj"}, "first", []}, "second", []}
    end

    test "method call on array access" do
      assert parse_expr!("<?php $arr['key']->method();") ==
               {:method_call, {:array_access, {:variable, "arr"}, {:string, "key"}}, "method", []}
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

  describe "Step 7: comparison operators" do
    test "equals" do
      assert parse_expr!("<?php $x == 'y';") ==
               {:binary_op, :==, {:variable, "x"}, {:string, "y"}}
    end

    test "not equals" do
      assert parse_expr!("<?php $x != 'y';") ==
               {:binary_op, :!=, {:variable, "x"}, {:string, "y"}}
    end

    test "strict equals" do
      assert parse_expr!("<?php $x === 'y';") ==
               {:binary_op, :===, {:variable, "x"}, {:string, "y"}}
    end

    test "strict not equals" do
      assert parse_expr!("<?php $x !== 'y';") ==
               {:binary_op, :!==, {:variable, "x"}, {:string, "y"}}
    end
  end

  describe "Step 8: logical operators" do
    test "logical and" do
      assert parse_expr!("<?php $a && $b;") ==
               {:binary_op, :&&, {:variable, "a"}, {:variable, "b"}}
    end

    test "logical or" do
      assert parse_expr!("<?php $a || $b;") ==
               {:binary_op, :||, {:variable, "a"}, {:variable, "b"}}
    end

    test "logical not" do
      assert parse_expr!("<?php !$a;") ==
               {:unary_op, :!, {:variable, "a"}}
    end

    test "&& binds tighter than ||" do
      # $a || $b && $c should parse as $a || ($b && $c)
      assert parse_expr!("<?php $a || $b && $c;") ==
               {:binary_op, :||, {:variable, "a"},
                {:binary_op, :&&, {:variable, "b"}, {:variable, "c"}}}
    end

    test "double negation" do
      assert parse_expr!("<?php !!$a;") ==
               {:unary_op, :!, {:unary_op, :!, {:variable, "a"}}}
    end
  end

  describe "Step 9: string concatenation" do
    test "simple concatenation" do
      assert parse_expr!("<?php $a . $b;") ==
               {:binary_op, :., {:variable, "a"}, {:variable, "b"}}
    end

    test "chained concatenation is left-associative" do
      assert parse_expr!("<?php $a . $b . $c;") ==
               {:binary_op, :., {:binary_op, :., {:variable, "a"}, {:variable, "b"}},
                {:variable, "c"}}
    end

    test "concatenation with string literals" do
      assert parse_expr!("<?php 'hello' . ' ' . 'world';") ==
               {:binary_op, :., {:binary_op, :., {:string, "hello"}, {:string, " "}},
                {:string, "world"}}
    end
  end

  describe "Step 10: ternary, null coalescing, elvis" do
    test "ternary operator" do
      assert parse_expr!("<?php $x ? 'a' : 'b';") ==
               {:ternary, {:variable, "x"}, {:string, "a"}, {:string, "b"}}
    end

    test "null coalescing" do
      assert parse_expr!("<?php $x ?? 'default';") ==
               {:null_coalesce, {:variable, "x"}, {:string, "default"}}
    end

    test "elvis operator" do
      assert parse_expr!("<?php $x ?: 'default';") ==
               {:elvis, {:variable, "x"}, {:string, "default"}}
    end

    test "null coalesce is right-associative" do
      assert parse_expr!("<?php $a ?? $b ?? $c;") ==
               {:null_coalesce, {:variable, "a"},
                {:null_coalesce, {:variable, "b"}, {:variable, "c"}}}
    end

    test "ternary with complex condition" do
      assert parse_expr!("<?php $x == 'y' ? 'yes' : 'no';") ==
               {:ternary, {:binary_op, :==, {:variable, "x"}, {:string, "y"}}, {:string, "yes"},
                {:string, "no"}}
    end
  end

  describe "Step 11: type casts" do
    test "(int) cast" do
      assert parse_expr!("<?php (int)$x;") ==
               {:type_cast, :int, {:variable, "x"}}
    end

    test "(float) cast" do
      assert parse_expr!("<?php (float)$x;") ==
               {:type_cast, :float, {:variable, "x"}}
    end

    test "(string) cast" do
      assert parse_expr!("<?php (string)$x;") ==
               {:type_cast, :string, {:variable, "x"}}
    end

    test "cast with spaces" do
      assert parse_expr!("<?php ( int )$x;") ==
               {:type_cast, :int, {:variable, "x"}}
    end
  end

  describe "Step 12: assignment statements" do
    test "simple variable assignment" do
      assert parse_stmt!("<?php $x = 'val';") ==
               {:assign, {:variable, "x"}, {:string, "val"}}
    end

    test "array key assignment" do
      assert parse_stmt!("<?php $our['key'] = 'val';") ==
               {:assign, {:array_access, {:variable, "our"}, {:string, "key"}}, {:string, "val"}}
    end

    test "assignment with expression value" do
      assert parse_stmt!("<?php $x = $a . $b;") ==
               {:assign, {:variable, "x"}, {:binary_op, :., {:variable, "a"}, {:variable, "b"}}}
    end

    test "nested array assignment" do
      assert parse_stmt!("<?php $data['a']['b'] = 42;") ==
               {:assign,
                {:array_access, {:array_access, {:variable, "data"}, {:string, "a"}},
                 {:string, "b"}}, {:integer, 42}}
    end
  end

  describe "Step 13: if/elseif/else (braced)" do
    test "simple if" do
      assert parse_stmt!("<?php if ($x == 'y') { $a = 1; }") ==
               {:if, {:binary_op, :==, {:variable, "x"}, {:string, "y"}},
                [{:assign, {:variable, "a"}, {:integer, 1}}], [], nil}
    end

    test "if/else" do
      assert parse_stmt!("<?php if ($x) { $a = 1; } else { $b = 2; }") ==
               {:if, {:variable, "x"}, [{:assign, {:variable, "a"}, {:integer, 1}}], [],
                [{:assign, {:variable, "b"}, {:integer, 2}}]}
    end

    test "if/elseif/else" do
      input = "<?php if ($x) { $a = 1; } elseif ($y) { $b = 2; } else { $c = 3; }"

      assert parse_stmt!(input) ==
               {:if, {:variable, "x"}, [{:assign, {:variable, "a"}, {:integer, 1}}],
                [{{:variable, "y"}, [{:assign, {:variable, "b"}, {:integer, 2}}]}],
                [{:assign, {:variable, "c"}, {:integer, 3}}]}
    end

    test "multiple elseif clauses" do
      input =
        "<?php if ($a) { $x = 1; } elseif ($b) { $x = 2; } elseif ($c) { $x = 3; } else { $x = 4; }"

      {:if, _, _, elseifs, else_body} = parse_stmt!(input)
      assert length(elseifs) == 2
      assert else_body != nil
    end
  end

  describe "Step 14: if/elseif/else (braceless)" do
    test "braceless if with single statement" do
      assert parse_stmt!("<?php if ($x) $a = 1;") ==
               {:if, {:variable, "x"}, [{:assign, {:variable, "a"}, {:integer, 1}}], [], nil}
    end

    test "braceless if/else" do
      assert parse_stmt!("<?php if ($x) $a = 1; else $b = 2;") ==
               {:if, {:variable, "x"}, [{:assign, {:variable, "a"}, {:integer, 1}}], [],
                [{:assign, {:variable, "b"}, {:integer, 2}}]}
    end
  end

  describe "Step 15: foreach" do
    test "foreach with key and value" do
      assert parse_stmt!("<?php foreach ($arr as $k => $v) { $x = $v; }") ==
               {:foreach, {:variable, "arr"}, {:variable, "k"}, {:variable, "v"},
                [{:assign, {:variable, "x"}, {:variable, "v"}}]}
    end

    test "foreach without key" do
      assert parse_stmt!("<?php foreach ($arr as $v) { $x = $v; }") ==
               {:foreach, {:variable, "arr"}, nil, {:variable, "v"},
                [{:assign, {:variable, "x"}, {:variable, "v"}}]}
    end

    test "foreach over array access" do
      assert parse_stmt!("<?php foreach ($data['items'] as $item) { $x = $item; }") ==
               {:foreach, {:array_access, {:variable, "data"}, {:string, "items"}}, nil,
                {:variable, "item"}, [{:assign, {:variable, "x"}, {:variable, "item"}}]}
    end
  end

  describe "Step 16: switch/case" do
    test "switch with cases and default" do
      input = """
      <?php switch ($x) {
        case 'a':
          $y = 1;
          break;
        case 'b':
          $y = 2;
          break;
        default:
          $y = 3;
      }
      """

      assert parse_stmt!(input) ==
               {:switch, {:variable, "x"},
                [
                  {:case_clause, {:string, "a"},
                   [{:assign, {:variable, "y"}, {:integer, 1}}, {:break}]},
                  {:case_clause, {:string, "b"},
                   [{:assign, {:variable, "y"}, {:integer, 2}}, {:break}]},
                  {:case_clause, :default, [{:assign, {:variable, "y"}, {:integer, 3}}]}
                ]}
    end

    test "switch with single case" do
      input = "<?php switch ($x) { case 'a': $y = 1; break; }"

      assert parse_stmt!(input) ==
               {:switch, {:variable, "x"},
                [
                  {:case_clause, {:string, "a"},
                   [{:assign, {:variable, "y"}, {:integer, 1}}, {:break}]}
                ]}
    end
  end

  describe "Step 17: break" do
    test "break statement" do
      assert parse_stmt!("<?php break;") == {:break}
    end
  end

  describe "Step 18: program wrapper" do
    test "full program with open and close tags" do
      assert parse!("<?php $x = 1; ?>") ==
               {:program, [{:assign, {:variable, "x"}, {:integer, 1}}]}
    end

    test "multiple statements" do
      ast = parse!("<?php $x = 1; $y = 2;")

      assert {:program,
              [
                {:assign, {:variable, "x"}, {:integer, 1}},
                {:assign, {:variable, "y"}, {:integer, 2}}
              ]} = ast
    end

    test "program without close tag" do
      assert {:program, [{:assign, {:variable, "x"}, {:integer, 1}}]} =
               parse!("<?php $x = 1;")
    end

    test "error on invalid syntax" do
      {:ok, tokens} = Lexer.tokenize("<?php )")
      assert {:error, _reason} = Parser.parse(tokens)
    end
  end
end
