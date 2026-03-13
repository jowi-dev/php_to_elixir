defmodule PhpToElixir.EmitterTest do
  use ExUnit.Case, async: true

  alias PhpToElixir.Emitter

  describe "leaf expressions - integers and floats" do
    test "emits integer literal" do
      ast = {:program, [{:expr_statement, {:integer, 42}}]}
      assert Emitter.emit(ast) == {:ok, "42"}
    end

    test "emits float literal" do
      ast = {:program, [{:expr_statement, {:float, 3.14}}]}
      assert Emitter.emit(ast) == {:ok, "3.14"}
    end
  end

  describe "leaf expressions - booleans and nil" do
    test "emits true" do
      ast = {:program, [{:expr_statement, {:boolean, true}}]}
      assert Emitter.emit(ast) == {:ok, "true"}
    end

    test "emits false" do
      ast = {:program, [{:expr_statement, {:boolean, false}}]}
      assert Emitter.emit(ast) == {:ok, "false"}
    end

    test "emits nil" do
      ast = {:program, [{:expr_statement, {nil}}]}
      assert Emitter.emit(ast) == {:ok, "nil"}
    end
  end

  describe "leaf expressions - variables" do
    test "emits variable" do
      ast = {:program, [{:expr_statement, {:variable, "foo"}}]}
      assert Emitter.emit(ast) == {:ok, "foo"}
    end
  end

  describe "leaf expressions - arrays" do
    test "emits associative array as map" do
      ast =
        {:program,
         [
           {:expr_statement, {:array_literal, [{:array_entry, {:string, "a"}, {:string, "b"}}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s(%{"a" => "b"})}
    end

    test "emits indexed array as list" do
      ast =
        {:program, [{:expr_statement, {:array_literal, [{:string, "a"}, {:string, "b"}]}}]}

      assert Emitter.emit(ast) == {:ok, ~s(["a", "b"])}
    end

    test "emits empty array as empty map" do
      ast = {:program, [{:expr_statement, {:array_literal, []}}]}
      assert Emitter.emit(ast) == {:ok, "%{}"}
    end
  end

  describe "leaf expressions - strings" do
    test "emits simple string" do
      ast = {:program, [{:expr_statement, {:string, "hello"}}]}
      assert Emitter.emit(ast) == {:ok, ~s("hello")}
    end

    test "emits interpolated string" do
      ast = {:program, [{:expr_statement, {:interpolated_string, ["hi ", {:variable, "name"}]}}]}
      assert Emitter.emit(ast) == {:ok, ~s("hi \#{name}")}
    end
  end

  # --- Layer 2: Compound Expressions ---

  describe "array access" do
    test "emits simple array access" do
      ast =
        {:program,
         [{:expr_statement, {:array_access, {:variable, "our"}, {:string, "key"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(our["key"])}
    end

    test "emits chained array access" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:array_access, {:array_access, {:variable, "our"}, {:string, "a"}}, {:string, "b"}}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s(our["a"]["b"])}
    end
  end

  describe "binary operators" do
    test "emits equality" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :==, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x == "y")}
    end

    test "emits inequality" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :!=, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x != "y")}
    end

    test "emits strict equality" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :===, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x === "y")}
    end

    test "emits strict inequality" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :!==, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x !== "y")}
    end

    test "emits logical and" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :&&, {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "a && b"}
    end

    test "emits logical or" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :||, {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "a || b"}
    end
  end

  describe "concatenation" do
    test "emits concatenation with to_string wrapping" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :., {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "to_string(a) <> to_string(b)"}
    end

    test "skips to_string wrapping for string literals" do
      ast =
        {:program,
         [{:expr_statement, {:binary_op, :., {:string, "hi "}, {:variable, "name"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s["hi " <> to_string(name)]}
    end
  end

  describe "unary not" do
    test "emits unary not" do
      ast = {:program, [{:expr_statement, {:unary_op, :!, {:variable, "a"}}}]}
      assert Emitter.emit(ast) == {:ok, "!a"}
    end
  end

  describe "ternary, null coalesce, elvis" do
    test "emits ternary as inline if" do
      ast =
        {:program,
         [{:expr_statement, {:ternary, {:variable, "x"}, {:string, "a"}, {:string, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s[if(x, do: "a", else: "b")]}
    end

    test "emits null coalesce as ||" do
      ast =
        {:program,
         [{:expr_statement, {:null_coalesce, {:variable, "x"}, {:string, "default"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x || "default")}
    end

    test "emits elvis as ||" do
      ast =
        {:program,
         [{:expr_statement, {:elvis, {:variable, "x"}, {:string, "default"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x || "default")}
    end
  end

  describe "type casts" do
    test "emits int cast" do
      ast = {:program, [{:expr_statement, {:type_cast, :int, {:variable, "x"}}}]}
      assert Emitter.emit(ast) == {:ok, "to_integer(x)"}
    end

    test "emits float cast" do
      ast = {:program, [{:expr_statement, {:type_cast, :float, {:variable, "x"}}}]}
      assert Emitter.emit(ast) == {:ok, "to_float(x)"}
    end

    test "emits string cast" do
      ast = {:program, [{:expr_statement, {:type_cast, :string, {:variable, "x"}}}]}
      assert Emitter.emit(ast) == {:ok, "to_string(x)"}
    end
  end
end
