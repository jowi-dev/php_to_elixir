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
end
