# PhpTranspiler: PHP-to-Elixir Recursive Descent Transpiler

## Context

The axiom lead delivery system uses Elixir transform modules (stored as code strings) to map lead data into partner-specific HTTP request bodies. These transforms are currently hand-written or generated from structured JSON metadata that was itself extracted from legacy Boberdoo PHP code via brittle regex parsing.

The goal is to build a reliable PHP-to-Elixir transpiler that can parse the PHP pre-processing/response-parsing code from scraped partner integration files and emit valid Elixir `defmodule Transformer` code strings compatible with axiom's `TransformRunner` / `MiniElixir` sandbox.

This is a **standalone Mix project** that will be added as a dependency to axiom.

---

## Architecture

```
php_transpiler/
├── lib/
│   ├── php_transpiler.ex              # Public API: transpile/1, transpile!/1
│   ├── php_transpiler/
│   │   ├── lexer.ex                   # Tokenizer: PHP string → token list
│   │   ├── token.ex                   # Token struct definition
│   │   ├── parser.ex                  # Recursive descent: tokens → PHP AST
│   │   ├── ast.ex                     # AST node type definitions
│   │   ├── emitter.ex                 # PHP AST → Elixir code string
│   │   └── builtins.ex               # PHP built-in function → Elixir mapping
├── test/
│   ├── php_transpiler_test.exs        # Integration tests (PHP string → Elixir string)
│   ├── php_transpiler/
│   │   ├── lexer_test.exs
│   │   ├── parser_test.exs
│   │   ├── emitter_test.exs
│   │   └── builtins_test.exs
│   └── fixtures/                      # Real PHP snippets from scraped partners
│       ├── rba_pre_processing.php
│       ├── basement_systems.php
│       ├── empire_today.php
│       └── ...
```

---

## Implementation Phases

### Phase 1: Token Types and Lexer

**Goal:** Tokenize a PHP string into a flat list of tokens.

#### Token types needed:

**Keywords:** `if`, `elseif`, `else`, `foreach`, `as`, `switch`, `case`, `default`, `break`, `true`, `false`, `null`, `isset`, `empty`, `array`

**Operators:** `==`, `===`, `!=`, `!==`, `=`, `||`, `&&`, `!`, `.`, `??`, `?`, `:`, `=>`, `->`, `(int)`, `(float)`, `(string)`

**Delimiters:** `(`, `)`, `{`, `}`, `[`, `]`, `;`, `,`

**Literals:** single-quoted strings, double-quoted strings, integers, floats

**Identifiers:** `$variable_name`, bare identifiers (function names)

**Special:** `<?php`, `?>`, `//` line comments, `/* */` block comments, EOF

#### Tokenizer traps to handle:
- `else$our` — no whitespace between keyword and `$`; tokenizer must recognize `else` as keyword boundary before `$`
- `$our['$filterSetID']` — the `$` inside single-quoted strings is literal, not a variable
- Double-quoted strings with `{$var}` interpolation (emit as a special token; rare but exists)
- Type casts `(int)`, `(float)`, `(string)` — look like parenthesized identifiers

**TDD cycle:** Write test for each token type → implement lexer rule → green → next.

### Phase 2: AST Node Types

**Goal:** Define the AST node structs/types.

```
# Statements
{:program, [statement]}
{:if, condition, then_body, elseif_clauses, else_body}
{:foreach, collection, key_var, value_var, body}
{:switch, expr, [case_clause]}
{:case_clause, expr | :default, body}
{:break}
{:assign, target, value}
{:expr_statement, expr}

# Expressions
{:binary_op, op, left, right}         # ==, !=, ===, !==, ||, &&, .
{:unary_op, op, operand}              # !
{:ternary, condition, then_expr, else_expr}
{:null_coalesce, left, right}         # ??
{:elvis, left, right}                 # ?:
{:type_cast, type, expr}              # (int), (float), (string)

# Access
{:variable, name}                     # $var
{:array_access, target, key}          # $our['key'], chainable
{:property_access, target, property}  # $this->response
{:method_call, target, method, args}  # $this->sendCurl(...)
{:function_call, name, args}          # in_array(...), preg_match(...)
{:array_append, target}               # $var[]

# Literals
{:string, value}
{:interpolated_string, parts}         # "text {$var} text"
{:integer, value}
{:float, value}
{:boolean, value}
{:nil}
{:array_literal, entries}             # array(...) or [...]
{:array_entry, key, value}            # 'key' => 'value'
```

Use plain tagged tuples — no need for full structs. Keep it simple.

### Phase 3: Recursive Descent Parser

**Goal:** Parse token list into AST.

#### Grammar (informal):

```
program         → '<?php' statement* '?>'?
statement       → if_stmt | foreach_stmt | switch_stmt | assign_stmt | break_stmt | expr_stmt
if_stmt         → 'if' '(' expr ')' block elseif* else?
elseif          → 'elseif' '(' expr ')' block
else            → 'else' block
block           → '{' statement* '}' | statement    # braced or braceless single-stmt
foreach_stmt    → 'foreach' '(' expr 'as' variable '=>' variable ')' block
                | 'foreach' '(' expr 'as' variable ')' block
switch_stmt     → 'switch' '(' expr ')' '{' case_clause* '}'
case_clause     → ('case' expr ':' | 'default' ':') statement*
break_stmt      → 'break' ';'
assign_stmt     → lvalue '=' expr ';'
expr_stmt       → expr ';'

# Expression precedence (lowest to highest):
expr            → ternary_expr
ternary_expr    → null_coalesce ('?' expr ':' expr)?
null_coalesce   → elvis_expr ('??' elvis_expr)*
elvis_expr      → or_expr ('?:' or_expr)?
or_expr         → and_expr ('||' and_expr)*
and_expr        → not_expr ('&&' not_expr)*
not_expr        → '!' not_expr | comparison
comparison      → concat_expr (('==' | '!=' | '===' | '!==') concat_expr)?
concat_expr     → primary ('.' primary)*
primary         → type_cast | function_call | access_expr | literal | '(' expr ')'
type_cast       → '(int)' primary | '(float)' primary | '(string)' primary
access_expr     → atom ('[' expr ']')* ('->' identifier ('[' expr ']')*)*
atom            → variable | 'array' '(' array_entries ')' | '[' array_entries ']'
                | string | number | boolean | null | identifier
```

**Implementation order (TDD):**
1. Literals and variables
2. Array literals (`array()` and `[]`)
3. Array access (`$our['key']`, chained)
4. Property access (`$this->prop`)
5. Function calls (`in_array(...)`)
6. Method calls (`$this->method(...)`)
7. Comparison operators
8. Logical operators (`&&`, `||`, `!`)
9. String concatenation (`.`)
10. Ternary, null coalescing, elvis
11. Type casts
12. Assignment statements
13. If/elseif/else (braced)
14. If/elseif/else (braceless)
15. Foreach
16. Switch/case
17. Break

### Phase 4: Elixir Emitter

**Goal:** Walk PHP AST, emit Elixir code string.

#### Key translation rules:

| PHP | Elixir |
|---|---|
| `$our['key'] = 'value';` | `our = Map.put(our, "key", "value")` |
| `if ($x == 'y') { ... }` | `{our, this} = if x == "y" do ... else {our, this} end` |
| `$our['key']` (read) | `our["key"]` or `Map.get(our, "key")` |
| `$this->response` | **Out of scope** — value comes from JSON metadata, not PHP |
| `$this->leadRow['key']` | **Out of scope** — emit warning/placeholder |
| `in_array($x, $arr)` | `x in arr` or `Enum.member?(arr, x)` |
| `isset($our['key'])` | `Map.has_key?(our, "key")` |
| `empty($our['key'])` | `empty?(our["key"])` (emit helper or inline) |
| `preg_match('/pattern/i', $str)` | `Regex.match?(~r/pattern/i, str)` |
| `json_decode($str, true)` | `Jason.decode!(str)` |
| `str_contains($h, $n)` | `String.contains?(h, n)` |
| `strtolower($s)` | `String.downcase(s)` |
| `explode(",", $s)` | `String.split(s, ",")` |
| `implode(",", $a)` | `Enum.join(a, ",")` |
| `str_replace($s, $r, $subj)` | `String.replace(subj, s, r)` |
| `date("Y-m-d")` | `:os.timestamp()` or `Date.utc_today() \|> to_string()` |
| `(int)$x` | `String.to_integer(x)` or emit helper |
| `(float)$x` | `String.to_float(x)` or emit helper |
| `array('k' => 'v')` | `%{"k" => "v"}` |
| `$a . $b` | `a <> b` (or interpolation) |
| `$x ?? 'default'` | `x \|\| "default"` or `Map.get(...)` with default |
| `foreach ($arr as $k => $v)` | `Enum.reduce(arr, {our, this}, fn {k, v}, {our, this} -> ... end)` |
| `switch/case` | `cond do ... end` |

#### The mutation problem — "collect into output map" approach

PHP mutates `$our` throughout. Rather than threading an accumulator, the emitter should:

1. **Analyze** all `$our['key'] = expr` assignments to identify which keys are computed
2. **Emit computed variables** — each assigned key becomes a local variable (e.g., `rba_source`, `rba_breakdown`)
3. **Conditional assignments** become `cond` / `if` expressions that return values
4. **Sequential dependencies** (where one assignment reads a previously-assigned key) require topological ordering or intermediate variables
5. **Final output** is a single `%{}` map collecting all computed variables

**Judgment call: lookups vs code.** Some `$our` assignments are static/semi-static values that should become lookup table entries in axiom rather than hardcoded in the transform. The transpiler should **tag** each assignment so the consumer (or a human) can decide:
- Static string assignment → candidate for lookup table
- Conditional/computed assignment → must be in transform code

**`$this->` patterns are out of scope.** The `$this->response`, `$this->leadRow`, etc. represent Boberdoo page inputs that are already captured in the JSON metadata. The transpiler does NOT need to parse `$this->` access — those values are available as inputs to the transform via `lookup` or `lead` parameters. If the parser encounters `$this->`, it should emit a placeholder or warning, not try to translate it.

Example output:

```elixir
defmodule Transformer do
  def transform(lookup, lead) do
    src = lead.src || ""

    rba_source =
      cond do
        src == "RBANA" -> "Digital Media"
        src in ["SOCLP", "SOCRBA", "SOCNXD", "DISSM", "DISBDU", "DISTAB"] -> "Social Media"
        true -> "Digital Media"
      end

    rba_breakdown =
      cond do
        src == "RBANA" ->
          "National House Method"
        src in ["SOCLP", "SOCRBA", "SOCNXD", "DISSM", "DISBDU", "DISTAB"] ->
          "National House Method Social"
        lookup["filterSetID"] in ["27993", "31357", "32813", ...] ->
          "National House Method Exterior Doors"
        lookup["filterSetID"] in ["46769", "46805", "54281", ...] ->
          "National House Method Single Window"
        true ->
          "National House Method"
      end

    %{
      "RbASource" => rba_source,
      "RbABreakdown" => rba_breakdown,
      "rbaemail_1" => if(src == "RBANA", do: "neighborhood alerts", else: nil),
      "Project" => map_project(src, lead.project)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp map_project("PWPHS", project)
       when project in ["Windows - New Window - Single", "Windows - New Windows - 1-2"],
    do: "Windows - 3-5"

  defp map_project(_src, "Doors (Exterior) - Install or Replace"), do: "Doors"
  # ... etc
end
```

### Phase 5: Built-in Function Registry

**Goal:** Map PHP functions to Elixir equivalents.

Create a registry module with:
```elixir
def translate("in_array", [needle, haystack]), do: ...
def translate("isset", [expr]), do: ...
def translate("empty", [expr]), do: ...
def translate("preg_match", [pattern, subject | rest]), do: ...
def translate("json_decode", [string | _opts]), do: ...
# ... ~20 functions total
```

Each returns an Elixir AST fragment or code string. Unknown functions raise a clear error with the function name and file context.

**`$this->method()` calls** (e.g., `$this->sendCurl()`, `$this->getPingValue()`, `$this->updateLeadField()`): These are Boberdoo platform methods whose inputs/outputs are captured in the JSON metadata. The parser should recognize them syntactically but the emitter should emit a `# TODO: $this->methodName() — see JSON metadata` comment or a tagged warning, not attempt translation.

### Phase 6: Integration Tests with Real Scraped PHP

**Goal:** Validate against actual partner PHP snippets.

For each scraped partner:
1. Extract the `php.pre_processing` string from the JSON
2. Run it through `PhpTranspiler.transpile/1`
3. Feed the output Elixir string + test lead data into `Code.eval_string/1` (or MiniElixir in axiom)
4. Assert the output map matches the `expected_request.params` from the test data JSON

Start with simpler partners (few conditions) and work up to complex ones (33mile_radius at 1097 lines, modernize at 2400 lines).

**Priority order by complexity:**
1. empire_today (30 lines) — simple if/elseif
2. contractor_kings (42 lines) — ternary, date()
3. basement_systems (56 lines) — basic routing
4. orkin (58 lines) — parse_url, ltrim
5. ridge_top (64 lines) — in_array, array literals
6. remodel_well (114 lines) — medium complexity
7. birddog (155 lines) — ||, nested arrays
8. pointer_leads (175 lines) — foreach, preg_match with captures, str_contains
9. inquirly (358 lines) — heavy preg_match
10. homeyou (1000+ lines) — braceless if/else, `else$our` trap
11. 33mile_radius (1097 lines) — nested arrays, complex routing
12. modernize (2400 lines) — largest file, ultimate stress test

---

## Verification

1. **Unit tests per module** — lexer, parser, emitter each tested independently
2. **Round-trip tests** — PHP string → transpile → eval Elixir → assert output map
3. **Fixture tests** — real scraped PHP from partner files, assertions against known expected output from test data JSONs
4. **Error reporting** — unrecognized PHP constructs produce clear error messages with line numbers, not silent failures (this is the whole point over regex)

---

## Dependencies

- None required for the core transpiler (pure Elixir, no external deps)
- `jason` only if you want to parse the scraped JSON fixtures in tests
- No PHP runtime needed

---

## Estimated Scope

| Module | LOC | Test LOC |
|---|---|---|
| Token types | 30 | — |
| Lexer | 200-250 | 150-200 |
| AST types | 30 | — |
| Parser | 300-400 | 200-300 |
| Emitter | 250-350 | 200-250 |
| Builtins | 100-150 | 100-150 |
| Public API | 20 | 50 |
| Integration fixtures | — | 200-300 |
| **Total** | **~950-1200** | **~900-1200** |
