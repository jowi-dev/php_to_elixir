defmodule PhpToElixir.LexerTest do
  use ExUnit.Case, async: true

  alias PhpToElixir.Lexer
  alias PhpToElixir.Token

  # Helper to extract {type, value} pairs, dropping :eof
  defp token_types(input) do
    {:ok, tokens} = Lexer.tokenize(input)

    tokens
    |> Enum.reject(&(&1.type == :eof))
    |> Enum.map(&{&1.type, &1.value})
  end

  describe "special markers" do
    test "tokenizes <?php open tag" do
      {:ok, tokens} = Lexer.tokenize("<?php")
      assert [%Token{type: :open_tag, value: "<?php"}, %Token{type: :eof}] = tokens
    end

    test "tokenizes ?> close tag" do
      {:ok, tokens} = Lexer.tokenize("<?php ?>")

      assert [
               %Token{type: :open_tag, value: "<?php"},
               %Token{type: :close_tag, value: "?>"},
               %Token{type: :eof}
             ] = tokens
    end

    test "always ends with :eof token" do
      {:ok, tokens} = Lexer.tokenize("<?php")
      assert List.last(tokens).type == :eof
    end

    test "tracks line and column numbers" do
      {:ok, [open_tag | _]} = Lexer.tokenize("<?php")
      assert open_tag.line == 1
      assert open_tag.col == 1
    end
  end

  describe "whitespace" do
    test "skips spaces between tokens" do
      assert token_types("<?php   ?>") == [{:open_tag, "<?php"}, {:close_tag, "?>"}]
    end

    test "skips newlines and tracks line numbers" do
      {:ok, tokens} = Lexer.tokenize("<?php\n?>")
      close_tag = Enum.find(tokens, &(&1.type == :close_tag))
      assert close_tag.line == 2
      assert close_tag.col == 1
    end

    test "skips tabs" do
      assert token_types("<?php\t?>") == [{:open_tag, "<?php"}, {:close_tag, "?>"}]
    end
  end

  describe "comments" do
    test "skips single-line // comments" do
      input = "<?php // this is a comment\n?>"

      assert token_types(input) == [{:open_tag, "<?php"}, {:close_tag, "?>"}]
    end

    test "skips block /* */ comments" do
      input = "<?php /* block comment */ ?>"

      assert token_types(input) == [{:open_tag, "<?php"}, {:close_tag, "?>"}]
    end

    test "skips multi-line block comments" do
      input = "<?php /* line1\nline2\nline3 */ ?>"

      {:ok, tokens} = Lexer.tokenize(input)
      close_tag = Enum.find(tokens, &(&1.type == :close_tag))
      assert close_tag.line == 3
    end

    test "skips # comments" do
      input = "<?php # hash comment\n?>"

      assert token_types(input) == [{:open_tag, "<?php"}, {:close_tag, "?>"}]
    end
  end

  describe "integer literals" do
    test "tokenizes simple integer" do
      assert token_types("<?php 42") == [{:open_tag, "<?php"}, {:integer, 42}]
    end

    test "tokenizes zero" do
      assert token_types("<?php 0") == [{:open_tag, "<?php"}, {:integer, 0}]
    end

    test "tokenizes multi-digit integer" do
      assert token_types("<?php 12345") == [{:open_tag, "<?php"}, {:integer, 12_345}]
    end
  end

  describe "float literals" do
    test "tokenizes simple float" do
      assert token_types("<?php 3.14") == [{:open_tag, "<?php"}, {:float, 3.14}]
    end

    test "tokenizes float with leading zero" do
      assert token_types("<?php 0.5") == [{:open_tag, "<?php"}, {:float, 0.5}]
    end
  end

  describe "single-quoted strings" do
    test "tokenizes simple single-quoted string" do
      assert token_types("<?php 'hello'") == [{:open_tag, "<?php"}, {:string, "hello"}]
    end

    test "tokenizes empty single-quoted string" do
      assert token_types("<?php ''") == [{:open_tag, "<?php"}, {:string, ""}]
    end

    test "handles escaped single quote" do
      assert token_types("<?php 'it\\'s'") == [{:open_tag, "<?php"}, {:string, "it's"}]
    end

    test "handles escaped backslash" do
      assert token_types("<?php 'path\\\\'") == [{:open_tag, "<?php"}, {:string, "path\\"}]
    end

    test "treats $ as literal in single-quoted strings" do
      assert token_types("<?php '$notavar'") == [{:open_tag, "<?php"}, {:string, "$notavar"}]
    end
  end

  describe "double-quoted strings" do
    test "tokenizes simple double-quoted string" do
      assert token_types(~s(<?php "hello")) == [{:open_tag, "<?php"}, {:string, "hello"}]
    end

    test "tokenizes empty double-quoted string" do
      assert token_types(~s(<?php "")) == [{:open_tag, "<?php"}, {:string, ""}]
    end

    test "handles \\n escape sequence" do
      assert token_types(~s(<?php "line\\n")) == [{:open_tag, "<?php"}, {:string, "line\n"}]
    end

    test "handles \\t escape sequence" do
      assert token_types(~s(<?php "col\\t")) == [{:open_tag, "<?php"}, {:string, "col\t"}]
    end

    test "handles \\\\ escape sequence" do
      assert token_types(~s(<?php "path\\\\")) == [{:open_tag, "<?php"}, {:string, "path\\"}]
    end

    test "handles escaped double quote" do
      assert token_types(~s(<?php "say \\"hi\\"")) ==
               [{:open_tag, "<?php"}, {:string, ~s(say "hi")}]
    end

    test "handles \\$ escape (literal dollar)" do
      assert token_types(~s(<?php "cost \\$5")) ==
               [{:open_tag, "<?php"}, {:string, "cost $5"}]
    end

    test "tokenizes interpolated string with {$var}" do
      assert token_types(~s(<?php "hello {$name}")) ==
               [{:open_tag, "<?php"}, {:interpolated_string, ["hello ", {:variable, "name"}]}]
    end

    test "tokenizes interpolated string with multiple variables" do
      assert token_types(~s(<?php "{$first} {$last}")) ==
               [
                 {:open_tag, "<?php"},
                 {:interpolated_string, [{:variable, "first"}, " ", {:variable, "last"}]}
               ]
    end

    test "tokenizes interpolated string with text before and after" do
      assert token_types(~s(<?php "Hello {$name}!")) ==
               [
                 {:open_tag, "<?php"},
                 {:interpolated_string, ["Hello ", {:variable, "name"}, "!"]}
               ]
    end
  end

  describe "variables" do
    test "tokenizes simple variable" do
      assert token_types("<?php $foo") == [{:open_tag, "<?php"}, {:variable, "foo"}]
    end

    test "tokenizes variable starting with underscore" do
      assert token_types("<?php $_underscore") ==
               [{:open_tag, "<?php"}, {:variable, "_underscore"}]
    end

    test "tokenizes variable with digits" do
      assert token_types("<?php $var2") == [{:open_tag, "<?php"}, {:variable, "var2"}]
    end

    test "tokenizes $our (regression — not a keyword)" do
      assert token_types("<?php $our") == [{:open_tag, "<?php"}, {:variable, "our"}]
    end
  end

  describe "keywords" do
    test "tokenizes control flow keywords" do
      for {input, expected} <- [
            {"if", :if},
            {"elseif", :elseif},
            {"else", :else},
            {"foreach", :foreach},
            {"as", :as},
            {"switch", :switch},
            {"case", :case},
            {"default", :default},
            {"break", :break}
          ] do
        assert token_types("<?php #{input}") == [{:open_tag, "<?php"}, {expected, input}],
               "Expected #{input} to produce #{inspect(expected)}"
      end
    end

    test "tokenizes boolean and null keywords" do
      assert token_types("<?php true") == [{:open_tag, "<?php"}, {true, "true"}]
      assert token_types("<?php false") == [{:open_tag, "<?php"}, {false, "false"}]
      assert token_types("<?php null") == [{:open_tag, "<?php"}, {:null, "null"}]
    end

    test "tokenizes builtin function keywords" do
      assert token_types("<?php isset") == [{:open_tag, "<?php"}, {:isset, "isset"}]
      assert token_types("<?php empty") == [{:open_tag, "<?php"}, {:empty, "empty"}]
      assert token_types("<?php array") == [{:open_tag, "<?php"}, {:array, "array"}]
    end

    test "keyword boundary before $ — else$our" do
      assert token_types("<?php else$our") ==
               [{:open_tag, "<?php"}, {:else, "else"}, {:variable, "our"}]
    end
  end

  describe "bare identifiers" do
    test "tokenizes function name with underscore" do
      assert token_types("<?php in_array") == [{:open_tag, "<?php"}, {:identifier, "in_array"}]
    end

    test "tokenizes function name with underscore prefix" do
      assert token_types("<?php preg_match") ==
               [{:open_tag, "<?php"}, {:identifier, "preg_match"}]
    end

    test "tokenizes CamelCase identifier" do
      assert token_types("<?php MyClass") == [{:open_tag, "<?php"}, {:identifier, "MyClass"}]
    end
  end

  describe "operators" do
    test "tokenizes triple-char operators (longest match)" do
      assert token_types("<?php ===") == [{:open_tag, "<?php"}, {:strict_eq, "==="}]
      assert token_types("<?php !==") == [{:open_tag, "<?php"}, {:strict_neq, "!=="}]
    end

    test "tokenizes double-char operators" do
      assert token_types("<?php ==") == [{:open_tag, "<?php"}, {:eq, "=="}]
      assert token_types("<?php !=") == [{:open_tag, "<?php"}, {:neq, "!="}]
      assert token_types("<?php ||") == [{:open_tag, "<?php"}, {:or, "||"}]
      assert token_types("<?php &&") == [{:open_tag, "<?php"}, {:and, "&&"}]
      assert token_types("<?php ??") == [{:open_tag, "<?php"}, {:null_coalesce, "??"}]
      assert token_types("<?php =>") == [{:open_tag, "<?php"}, {:double_arrow, "=>"}]
      assert token_types("<?php ->") == [{:open_tag, "<?php"}, {:arrow, "->"}]
    end

    test "tokenizes single-char operators" do
      assert token_types("<?php =") == [{:open_tag, "<?php"}, {:assign, "="}]
      assert token_types("<?php !") == [{:open_tag, "<?php"}, {:not, "!"}]
      assert token_types("<?php .") == [{:open_tag, "<?php"}, {:dot, "."}]
      assert token_types("<?php ?") == [{:open_tag, "<?php"}, {:question, "?"}]
      assert token_types("<?php :") == [{:open_tag, "<?php"}, {:colon, ":"}]
    end

    test "longest match: === beats ==" do
      types =
        token_types("<?php ===")
        |> Enum.map(&elem(&1, 0))

      assert types == [:open_tag, :strict_eq]
    end
  end

  describe "type cast operators" do
    test "tokenizes (int) cast" do
      assert token_types("<?php (int)") == [{:open_tag, "<?php"}, {:cast_int, "(int)"}]
    end

    test "tokenizes (float) cast" do
      assert token_types("<?php (float)") == [{:open_tag, "<?php"}, {:cast_float, "(float)"}]
    end

    test "tokenizes (string) cast" do
      assert token_types("<?php (string)") ==
               [{:open_tag, "<?php"}, {:cast_string, "(string)"}]
    end

    test "(int) followed by variable tokenizes correctly" do
      assert token_types("<?php (int)$x") ==
               [{:open_tag, "<?php"}, {:cast_int, "(int)"}, {:variable, "x"}]
    end

    test "(int) with spaces inside" do
      assert token_types("<?php ( int )") ==
               [{:open_tag, "<?php"}, {:cast_int, "( int )"}]
    end
  end

  describe "delimiters" do
    test "tokenizes parentheses" do
      assert token_types("<?php ()") ==
               [{:open_tag, "<?php"}, {:lparen, "("}, {:rparen, ")"}]
    end

    test "tokenizes curly braces" do
      assert token_types("<?php {}") ==
               [{:open_tag, "<?php"}, {:lbrace, "{"}, {:rbrace, "}"}]
    end

    test "tokenizes square brackets" do
      assert token_types("<?php []") ==
               [{:open_tag, "<?php"}, {:lbracket, "["}, {:rbracket, "]"}]
    end

    test "tokenizes semicolon" do
      assert token_types("<?php ;") == [{:open_tag, "<?php"}, {:semicolon, ";"}]
    end

    test "tokenizes comma" do
      assert token_types("<?php ,") == [{:open_tag, "<?php"}, {:comma, ","}]
    end
  end

  describe "edge cases and integration" do
    test "multi-token: array access assignment" do
      input = "<?php $our['key'] = 'value';"

      assert token_types(input) == [
               {:open_tag, "<?php"},
               {:variable, "our"},
               {:lbracket, "["},
               {:string, "key"},
               {:rbracket, "]"},
               {:assign, "="},
               {:string, "value"},
               {:semicolon, ";"}
             ]
    end

    test "multi-token: if statement" do
      input = "<?php if ($x == 'y') { $our['key'] = 'value'; }"

      assert token_types(input) == [
               {:open_tag, "<?php"},
               {:if, "if"},
               {:lparen, "("},
               {:variable, "x"},
               {:eq, "=="},
               {:string, "y"},
               {:rparen, ")"},
               {:lbrace, "{"},
               {:variable, "our"},
               {:lbracket, "["},
               {:string, "key"},
               {:rbracket, "]"},
               {:assign, "="},
               {:string, "value"},
               {:semicolon, ";"},
               {:rbrace, "}"}
             ]
    end

    test "error on unexpected character" do
      assert {:error, "Unexpected character '@' at line 1, col 7"} =
               Lexer.tokenize("<?php @")
    end

    test "$ inside single-quoted string in array access is literal" do
      input = "<?php $our['$filterSetID']"

      assert token_types(input) == [
               {:open_tag, "<?php"},
               {:variable, "our"},
               {:lbracket, "["},
               {:string, "$filterSetID"},
               {:rbracket, "]"}
             ]
    end

    test "foreach statement with double arrow" do
      input = "<?php foreach ($items as $key => $value) {}"

      assert token_types(input) == [
               {:open_tag, "<?php"},
               {:foreach, "foreach"},
               {:lparen, "("},
               {:variable, "items"},
               {:as, "as"},
               {:variable, "key"},
               {:double_arrow, "=>"},
               {:variable, "value"},
               {:rparen, ")"},
               {:lbrace, "{"},
               {:rbrace, "}"}
             ]
    end

    test "null coalescing with method call" do
      input = "<?php $obj->method() ?? 'default'"

      assert token_types(input) == [
               {:open_tag, "<?php"},
               {:variable, "obj"},
               {:arrow, "->"},
               {:identifier, "method"},
               {:lparen, "("},
               {:rparen, ")"},
               {:null_coalesce, "??"},
               {:string, "default"}
             ]
    end

    test "tracks line and column through complex input" do
      input = "<?php\n$x = 42;\n$y = 'hello';"
      {:ok, tokens} = Lexer.tokenize(input)

      y_var = Enum.find(tokens, &(&1.type == :variable && &1.value == "y"))
      assert y_var.line == 3
      assert y_var.col == 1
    end
  end
end
