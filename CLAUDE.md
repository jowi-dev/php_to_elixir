# PhpToElixir — Project Conventions

## Architecture

Pipeline: **Lexer → Parser → Emitter**

- `PhpToElixir.Lexer` — PHP source string → `[Token.t()]`
- `PhpToElixir.Ast` — AST node type definitions (typespecs, no functions)
- `PhpToElixir.Parser` — tokens → AST via recursive descent
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
| `PhpToElixir.Ast` | AST node types as tagged tuple typespecs |
| `PhpToElixir.Parser` | Parser: `parse/1` returns `{:ok, ast}` or `{:error, reason}` |

## AST Node Types

```
# Statements:    {:program, [stmt]}, {:if, cond, body, elseifs, else}, {:foreach, coll, key, val, body}
#                {:switch, expr, [case_clause]}, {:case_clause, expr | :default, body}
#                {:break}, {:assign, target, value}, {:expr_statement, expr}
# Expressions:   {:binary_op, op, left, right}, {:unary_op, :!, operand}
#                {:ternary, cond, then, else}, {:null_coalesce, left, right}
#                {:elvis, left, right}, {:type_cast, type, expr}
# Access:        {:variable, name}, {:array_access, target, key}, {:property_access, target, prop}
#                {:method_call, target, method, args}, {:function_call, name, args}
#                {:array_append, target}
# Literals:      {:string, val}, {:interpolated_string, parts}, {:integer, val}, {:float, val}
#                {:boolean, bool}, {:nil}, {:array_literal, entries}, {:array_entry, key, val}
```

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
