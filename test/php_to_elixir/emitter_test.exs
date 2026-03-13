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
        {:program, [{:expr_statement, {:array_access, {:variable, "our"}, {:string, "key"}}}]}

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
        {:program, [{:expr_statement, {:binary_op, :==, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x == "y")}
    end

    test "emits inequality" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :!=, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x != "y")}
    end

    test "emits strict equality" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :===, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x === "y")}
    end

    test "emits strict inequality" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :!==, {:variable, "x"}, {:string, "y"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x !== "y")}
    end

    test "emits logical and" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :&&, {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "a && b"}
    end

    test "emits logical or" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :||, {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "a || b"}
    end
  end

  describe "concatenation" do
    test "emits concatenation with to_string wrapping" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :., {:variable, "a"}, {:variable, "b"}}}]}

      assert Emitter.emit(ast) == {:ok, "to_string(a) <> to_string(b)"}
    end

    test "skips to_string wrapping for string literals" do
      ast =
        {:program, [{:expr_statement, {:binary_op, :., {:string, "hi "}, {:variable, "name"}}}]}

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
        {:program, [{:expr_statement, {:null_coalesce, {:variable, "x"}, {:string, "default"}}}]}

      assert Emitter.emit(ast) == {:ok, ~s(x || "default")}
    end

    test "emits elvis as ||" do
      ast =
        {:program, [{:expr_statement, {:elvis, {:variable, "x"}, {:string, "default"}}}]}

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

  # --- Layer 3: Access + Builtins ---

  describe "property access and method calls" do
    test "emits property access as TODO comment at statement level" do
      ast =
        {:program, [{:expr_statement, {:property_access, {:variable, "this"}, "response"}}]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "# TODO: $this->response"
    end

    test "emits method call as TODO comment at statement level" do
      ast =
        {:program, [{:expr_statement, {:method_call, {:variable, "this"}, "sendCurl", []}}]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "# TODO: $this->sendCurl()"
    end
  end

  describe "function calls" do
    test "emits unknown function call as TODO comment at statement level" do
      ast =
        {:program,
         [
           {:expr_statement, {:function_call, "someFunc", [{:variable, "x"}, {:string, "y"}]}}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "# TODO: someFunc"
    end

    test "emits isset as Map.has_key?" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "isset", [{:array_access, {:variable, "our"}, {:string, "key"}}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|Map.has_key?(our, "key")|}
    end

    test "emits empty as triple-or check" do
      ast =
        {:program, [{:expr_statement, {:function_call, "empty", [{:variable, "var"}]}}]}

      assert Emitter.emit(ast) == {:ok, ~s|(var == nil or var == "" or var == [])|}
    end

    test "emits in_array with flipped args" do
      ast =
        {:program,
         [
           {:expr_statement, {:function_call, "in_array", [{:variable, "x"}, {:variable, "arr"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, "Enum.member?(arr, x)"}
    end

    test "emits strtolower" do
      ast =
        {:program, [{:expr_statement, {:function_call, "strtolower", [{:variable, "s"}]}}]}

      assert Emitter.emit(ast) == {:ok, "String.downcase(s)"}
    end

    test "emits strtoupper" do
      ast =
        {:program, [{:expr_statement, {:function_call, "strtoupper", [{:variable, "s"}]}}]}

      assert Emitter.emit(ast) == {:ok, "String.upcase(s)"}
    end

    test "emits explode" do
      ast =
        {:program,
         [
           {:expr_statement, {:function_call, "explode", [{:string, ","}, {:variable, "s"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|String.split(s, ",")|}
    end

    test "emits implode" do
      ast =
        {:program,
         [
           {:expr_statement, {:function_call, "implode", [{:string, ","}, {:variable, "parts"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|Enum.join(parts, ",")|}
    end

    test "emits str_replace" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "str_replace", [{:string, "a"}, {:string, "b"}, {:variable, "s"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|String.replace(s, "a", "b")|}
    end

    test "emits str_contains" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "str_contains", [{:variable, "s"}, {:string, "needle"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|String.contains?(s, "needle")|}
    end

    test "emits count" do
      ast =
        {:program, [{:expr_statement, {:function_call, "count", [{:variable, "arr"}]}}]}

      assert Emitter.emit(ast) == {:ok, "length(arr)"}
    end

    test "emits trim" do
      ast =
        {:program, [{:expr_statement, {:function_call, "trim", [{:variable, "s"}]}}]}

      assert Emitter.emit(ast) == {:ok, "String.trim(s)"}
    end

    test "emits array_key_exists" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "array_key_exists", [{:string, "key"}, {:variable, "map"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|Map.has_key?(map, "key")|}
    end

    test "emits json_decode" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "json_decode", [{:variable, "str"}, {:boolean, true}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, "Jason.decode!(str)"}
    end

    test "emits preg_match" do
      ast =
        {:program,
         [
           {:expr_statement,
            {:function_call, "preg_match", [{:string, "/pattern/"}, {:variable, "str"}]}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|Regex.match?(~r/pattern/, str)|}
    end
  end

  # --- Layer 4: Statements ---

  describe "simple assignment" do
    test "emits variable assignment" do
      ast = {:program, [{:assign, {:variable, "x"}, {:string, "val"}}]}
      assert Emitter.emit(ast) == {:ok, ~s|x = "val"|}
    end
  end

  describe "array key assignment" do
    test "emits Map.put for single key" do
      ast =
        {:program,
         [
           {:assign, {:array_access, {:variable, "our"}, {:string, "key"}}, {:string, "val"}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|our = Map.put(our, "key", "val")|}
    end

    test "emits put_in for nested key" do
      ast =
        {:program,
         [
           {:assign,
            {:array_access, {:array_access, {:variable, "data"}, {:string, "a"}}, {:string, "b"}},
            {:integer, 42}}
         ]}

      assert Emitter.emit(ast) == {:ok, ~s|data = put_in(data, ["a", "b"], 42)|}
    end
  end

  describe "if statement" do
    test "emits if with no else, touching our" do
      ast =
        {:program,
         [
           {:if, {:binary_op, :==, {:variable, "x"}, {:string, "y"}},
            [{:assign, {:array_access, {:variable, "our"}, {:string, "k"}}, {:string, "v"}}], [],
            nil}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = if"
      assert code =~ ~s|x == "y"|
      assert code =~ "Map.put"
      assert code =~ "else"
      assert code =~ "our\nend"
    end

    test "emits if/else" do
      ast =
        {:program,
         [
           {:if, {:variable, "x"},
            [{:assign, {:array_access, {:variable, "our"}, {:string, "a"}}, {:string, "1"}}], [],
            [{:assign, {:array_access, {:variable, "our"}, {:string, "a"}}, {:string, "2"}}]}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = if"
      assert code =~ "else"
    end
  end

  describe "if/elseif/else as cond" do
    test "emits cond with multiple branches" do
      ast =
        {:program,
         [
           {:if, {:binary_op, :==, {:variable, "x"}, {:integer, 1}},
            [{:assign, {:array_access, {:variable, "our"}, {:string, "r"}}, {:string, "a"}}],
            [
              {{:binary_op, :==, {:variable, "x"}, {:integer, 2}},
               [
                 {:assign, {:array_access, {:variable, "our"}, {:string, "r"}}, {:string, "b"}}
               ]}
            ], [{:assign, {:array_access, {:variable, "our"}, {:string, "r"}}, {:string, "c"}}]}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = cond do"
      assert code =~ "x == 1 ->"
      assert code =~ "x == 2 ->"
      assert code =~ "true ->"
    end
  end

  describe "foreach" do
    test "emits Enum.reduce with key-value" do
      ast =
        {:program,
         [
           {:foreach, {:variable, "items"}, {:variable, "k"}, {:variable, "v"},
            [{:assign, {:array_access, {:variable, "our"}, {:variable, "k"}}, {:variable, "v"}}]}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = Enum.reduce"
      assert code =~ "items"
      assert code =~ "{k, v}, our ->"
      assert code =~ "Map.put"
    end

    test "emits Enum.reduce with value only" do
      ast =
        {:program,
         [
           {:foreach, {:variable, "items"}, nil, {:variable, "item"},
            [
              {:assign, {:array_access, {:variable, "our"}, {:string, "count"}},
               {:binary_op, :., {:variable, "item"}, {:string, " done"}}}
            ]}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = Enum.reduce"
      assert code =~ "item, our ->"
    end
  end

  describe "switch/case as cond" do
    test "emits cond with cases and default" do
      ast =
        {:program,
         [
           {:switch, {:variable, "x"},
            [
              {:case_clause, {:string, "a"},
               [
                 {:assign, {:array_access, {:variable, "our"}, {:string, "r"}}, {:string, "1"}},
                 {:break}
               ]},
              {:case_clause, :default,
               [{:assign, {:array_access, {:variable, "our"}, {:string, "r"}}, {:string, "0"}}]}
            ]}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "our = cond do"
      assert code =~ ~s|x == "a" ->|
      assert code =~ "true ->"
    end
  end

  # --- Layer 5: Integration ---

  describe "multi-statement program" do
    test "emits sequential our mutations" do
      ast =
        {:program,
         [
           {:assign, {:array_access, {:variable, "our"}, {:string, "a"}}, {:string, "1"}},
           {:assign, {:array_access, {:variable, "our"}, {:string, "b"}}, {:string, "2"}},
           {:assign, {:array_access, {:variable, "our"}, {:string, "c"}}, {:string, "3"}}
         ]}

      {:ok, code} = Emitter.emit(ast)
      lines = String.split(code, "\n")
      assert length(lines) == 3
      assert Enum.at(lines, 0) =~ ~s|Map.put(our, "a", "1")|
      assert Enum.at(lines, 1) =~ ~s|Map.put(our, "b", "2")|
      assert Enum.at(lines, 2) =~ ~s|Map.put(our, "c", "3")|
    end
  end

  # --- Phase 6: Real-world compatibility fixes ---

  describe "list() destructuring assignment" do
    test "emits list assignment as pattern match" do
      ast =
        {:program,
         [
           {:assign,
            {:function_call, "list",
             [
               {:array_access, {:variable, "our"}, {:string, "a"}},
               {:array_access, {:variable, "our"}, {:string, "b"}}
             ]},
            {:function_call, "explode",
             [{:string, ","}, {:array_access, {:variable, "our"}, {:string, "x"}}]}}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "["
      assert code =~ "String.split"
    end
  end

  describe "this-access safety" do
    test "property access as expression emits nil (safe for nesting)" do
      ast =
        {:program,
         [
           {:assign, {:array_access, {:variable, "our"}, {:string, "val"}},
            {:property_access, {:variable, "this"}, "response"}}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "Map.put(our"
      assert code =~ "nil"
      assert match?({:ok, _}, Code.string_to_quoted(code))
    end

    test "method call as expression emits nil (safe for nesting)" do
      ast =
        {:program,
         [
           {:assign, {:array_access, {:variable, "our"}, {:string, "price"}},
            {:method_call, {:variable, "this"}, "getPingValue", []}}
         ]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "Map.put"
      assert match?({:ok, _}, Code.string_to_quoted(code))
    end

    test "assignment to this-property emits comment on own line" do
      ast =
        {:program,
         [{:assign, {:property_access, {:variable, "this"}, "headers"}, {:string, "val"}}]}

      {:ok, code} = Emitter.emit(ast)
      assert code =~ "# TODO"
    end
  end
end
