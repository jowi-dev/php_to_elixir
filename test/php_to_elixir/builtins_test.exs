defmodule PhpToElixir.BuiltinsTest do
  use ExUnit.Case, async: true

  alias PhpToElixir.Builtins

  describe "translate/2" do
    test "isset with array access" do
      assert Builtins.translate("isset", [
               {:array_access, {:variable, "our"}, {:string, "key"}}
             ]) == {:ok, ~s|Map.has_key?(our, "key")|}
    end

    test "isset with plain variable" do
      assert Builtins.translate("isset", [{:variable, "x"}]) == {:ok, "x != nil"}
    end

    test "empty" do
      assert {:ok, result} = Builtins.translate("empty", [{:variable, "v"}])
      assert result =~ "v == nil"
      assert result =~ ~s|v == ""|
      assert result =~ "v == []"
    end

    test "in_array flips arg order" do
      assert Builtins.translate("in_array", [{:variable, "x"}, {:variable, "arr"}]) ==
               {:ok, "Enum.member?(arr, x)"}
    end

    test "strtolower" do
      assert Builtins.translate("strtolower", [{:variable, "s"}]) ==
               {:ok, "String.downcase(s)"}
    end

    test "strtoupper" do
      assert Builtins.translate("strtoupper", [{:variable, "s"}]) ==
               {:ok, "String.upcase(s)"}
    end

    test "explode" do
      assert Builtins.translate("explode", [{:string, ","}, {:variable, "s"}]) ==
               {:ok, ~s|String.split(s, ",")|}
    end

    test "implode" do
      assert Builtins.translate("implode", [{:string, ","}, {:variable, "p"}]) ==
               {:ok, ~s|Enum.join(p, ",")|}
    end

    test "str_replace" do
      assert Builtins.translate("str_replace", [
               {:string, "a"},
               {:string, "b"},
               {:variable, "s"}
             ]) == {:ok, ~s|String.replace(s, "a", "b")|}
    end

    test "str_contains" do
      assert Builtins.translate("str_contains", [{:variable, "s"}, {:string, "x"}]) ==
               {:ok, ~s|String.contains?(s, "x")|}
    end

    test "count" do
      assert Builtins.translate("count", [{:variable, "arr"}]) == {:ok, "length(arr)"}
    end

    test "trim" do
      assert Builtins.translate("trim", [{:variable, "s"}]) == {:ok, "String.trim(s)"}
    end

    test "array_key_exists" do
      assert Builtins.translate("array_key_exists", [
               {:string, "k"},
               {:variable, "m"}
             ]) == {:ok, ~s|Map.has_key?(m, "k")|}
    end

    test "json_decode" do
      assert Builtins.translate("json_decode", [{:variable, "s"}, {:boolean, true}]) ==
               {:ok, "Jason.decode!(s)"}
    end

    test "preg_match with simple pattern" do
      assert Builtins.translate("preg_match", [{:string, "/pat/"}, {:variable, "s"}]) ==
               {:ok, "Regex.match?(~r/pat/, s)"}
    end

    test "preg_match with flags" do
      assert Builtins.translate("preg_match", [{:string, "/GUTTERS/i"}, {:variable, "s"}]) ==
               {:ok, "Regex.match?(~r/GUTTERS/i, s)"}
    end

    test "preg_match with backtick delimiter" do
      assert Builtins.translate("preg_match", [{:string, "`windows`i"}, {:variable, "s"}]) ==
               {:ok, "Regex.match?(~r/windows/i, s)"}
    end

    test "preg_match with tilde delimiter" do
      assert Builtins.translate("preg_match", [{:string, "~email~i"}, {:variable, "s"}]) ==
               {:ok, "Regex.match?(~r/email/i, s)"}
    end

    test "strpos" do
      assert Builtins.translate("strpos", [{:variable, "h"}, {:string, "n"}]) ==
               {:ok, ~s|String.contains?(h, "n")|}
    end

    test "unknown returns :unknown" do
      assert Builtins.translate("custom_func", [{:variable, "x"}]) == :unknown
    end
  end
end
