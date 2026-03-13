# PhpToElixir — Project Conventions

## Architecture

Pipeline: **Lexer → Parser → Emitter**

- `PhpToElixir.Lexer` — PHP source string → `[Token.t()]`
- `PhpToElixir.Parser` — tokens → AST (future)
- `PhpToElixir.Emitter` — AST → Elixir source string (future)

## Code Conventions

- Follow standard Elixir idioms and OTP patterns
- `mix format` before every commit
- `mix compile --warnings-as-errors`
- `mix test` must pass before every commit
- TDD: write failing test first, then implement

## Module Organization

| Module | Purpose |
|---|---|
| `PhpToElixir.Token` | Token struct: `%Token{type, value, line, col}` |
| `PhpToElixir.Lexer` | Tokenizer: `tokenize/1` returns `{:ok, [Token.t()]}` or `{:error, reason}` |

## Token Types

```
# Special:       :open_tag, :close_tag, :eof
# Keywords:      :if, :elseif, :else, :foreach, :as, :switch, :case, :default, :break
#                :true, :false, :null, :isset, :empty, :array
# Literals:      :integer, :float, :string, :interpolated_string
# Identifiers:   :variable, :identifier
# Operators:     :eq, :strict_eq, :neq, :strict_neq, :assign, :not, :dot, :question, :colon
#                :or, :and, :null_coalesce, :arrow, :double_arrow
#                :cast_int, :cast_float, :cast_string
# Delimiters:    :lparen, :rparen, :lbrace, :rbrace, :lbracket, :rbracket, :semicolon, :comma
```
