defmodule PhpToElixir.Token do
  @moduledoc """
  Represents a single token produced by the lexer.

  ## Fields

    * `:type` - atom identifying the token type (e.g. `:open_tag`, `:variable`)
    * `:value` - the semantic value of the token
    * `:line` - 1-based line number where the token starts
    * `:col` - 1-based column number where the token starts
  """

  @type t :: %__MODULE__{
          type: atom(),
          value: any(),
          line: pos_integer(),
          col: pos_integer()
        }

  @enforce_keys [:type, :value, :line, :col]
  defstruct [:type, :value, :line, :col]
end
