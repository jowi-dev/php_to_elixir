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
end
