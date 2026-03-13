defmodule PhpToElixirTest do
  use ExUnit.Case
  doctest PhpToElixir

  describe "parse/1" do
    test "returns AST for valid PHP" do
      assert {:ok, {:program, stmts}} = PhpToElixir.parse("<?php $x = 42;")
      assert [{:assign, {:variable, "x"}, {:integer, 42}}] = stmts
    end

    test "returns error for invalid PHP" do
      assert {:error, _reason} = PhpToElixir.parse("<?php $x = ;")
    end

    test "returns multi-statement AST" do
      php = "<?php $a = 1; $b = 2;"
      assert {:ok, {:program, stmts}} = PhpToElixir.parse(php)
      assert length(stmts) == 2
    end
  end

  describe "$our['$field'] syntax" do
    test "single-quoted dollar sign is literal in AST" do
      php = ~s|<?php $our['$field'] = 'val';|

      {:ok, {:program, [{:assign, {:array_access, {:variable, "our"}, {:string, "$field"}}, _}]}} =
        PhpToElixir.parse(php)
    end

    test "single-quoted dollar sign transpiles correctly" do
      php = ~s|<?php $our['$field'] = 'val';|
      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ ~s|"$field"|
      assert code =~ "Map.put"
    end
  end

  describe "transpile/1" do
    test "simple assignment" do
      assert PhpToElixir.transpile("<?php $x = 42;") == {:ok, "x = 42\n"}
    end

    test "returns error for invalid PHP" do
      assert {:error, _reason} = PhpToElixir.transpile("<?php $x = ;")
    end

    test "end-to-end with if and function calls" do
      php = """
      <?php
      $our['status'] = 'pending';
      if ($our['type'] == 'rush') {
        $our['status'] = 'urgent';
      }
      """

      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "Map.put"
      assert code =~ "our"
      assert code =~ "if"
    end

    test "end-to-end with foreach" do
      php = """
      <?php
      foreach ($items as $k => $v) {
        $our[$k] = $v;
      }
      """

      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "Enum.reduce"
      assert code =~ "items"
    end

    test "end-to-end with built-in function" do
      php = ~s|<?php $x = strtolower($name);|

      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "String.downcase"
    end

    test "end-to-end with elseif chain" do
      php = """
      <?php
      if ($x == 1) {
        $our['r'] = 'a';
      } elseif ($x == 2) {
        $our['r'] = 'b';
      } else {
        $our['r'] = 'c';
      }
      """

      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "cond do"
      assert code =~ "x == 1"
      assert code =~ "x == 2"
      assert code =~ "true ->"
    end

    test "end-to-end with !empty() guard" do
      php = ~s|<?php if (!empty($our['email'])) { $our['valid'] = 'yes'; }|
      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "!"
      assert code =~ ~s|"email"|
      assert code =~ "Map.put"
    end

    test "end-to-end in_array with array() constructor" do
      php = ~s|<?php if (in_array($x, array('a', 'b', 'c'))) { $our['found'] = 'yes'; }|
      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "Enum.member?"
      assert code =~ ~s|["a", "b", "c"]|
    end

    test "end-to-end array() with key-value pairs" do
      php = ~s|<?php $x = array('key' => 'val', 'k2' => 'v2');|
      {:ok, code} = PhpToElixir.transpile(php)
      assert code =~ "%{"
      assert code =~ ~s|"key" => "val"|
    end
  end
end
