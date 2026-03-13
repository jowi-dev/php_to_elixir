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
end
