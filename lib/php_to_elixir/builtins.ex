defmodule PhpToElixir.Builtins do
  @moduledoc """
  PHP function → Elixir translation registry.

  Translates PHP built-in function calls to equivalent Elixir code.
  Receives AST arguments (not strings) so it can destructure patterns
  like `isset($our['key'])` → `Map.has_key?(our, "key")`.
  """

  alias PhpToElixir.Emitter

  @doc """
  Translates a PHP function call to Elixir code.

  Returns `{:ok, code}` for known functions or `:unknown` for unrecognized ones.
  """
  @spec translate(String.t(), [PhpToElixir.Ast.expr()]) :: {:ok, String.t()} | :unknown
  def translate("isset", [{:array_access, target, key}]) do
    {:ok, "Map.has_key?(#{Emitter.emit_expr(target)}, #{Emitter.emit_expr(key)})"}
  end

  def translate("isset", [arg]) do
    {:ok, "#{Emitter.emit_expr(arg)} != nil"}
  end

  def translate("empty", [arg]) do
    v = Emitter.emit_expr(arg)
    {:ok, ~s|(#{v} == nil or #{v} == "" or #{v} == [])|}
  end

  def translate("in_array", [needle, haystack]) do
    {:ok, "Enum.member?(#{Emitter.emit_expr(haystack)}, #{Emitter.emit_expr(needle)})"}
  end

  def translate("strtolower", [arg]) do
    {:ok, "String.downcase(#{Emitter.emit_expr(arg)})"}
  end

  def translate("strtoupper", [arg]) do
    {:ok, "String.upcase(#{Emitter.emit_expr(arg)})"}
  end

  def translate("explode", [delimiter, string]) do
    {:ok, "String.split(#{Emitter.emit_expr(string)}, #{Emitter.emit_expr(delimiter)})"}
  end

  def translate("implode", [glue, pieces]) do
    {:ok, "Enum.join(#{Emitter.emit_expr(pieces)}, #{Emitter.emit_expr(glue)})"}
  end

  def translate("str_replace", [search, replace, subject]) do
    {:ok,
     "String.replace(#{Emitter.emit_expr(subject)}, #{Emitter.emit_expr(search)}, #{Emitter.emit_expr(replace)})"}
  end

  def translate("str_contains", [haystack, needle]) do
    {:ok, "String.contains?(#{Emitter.emit_expr(haystack)}, #{Emitter.emit_expr(needle)})"}
  end

  def translate("count", [arg]) do
    {:ok, "length(#{Emitter.emit_expr(arg)})"}
  end

  def translate("trim", [arg]) do
    {:ok, "String.trim(#{Emitter.emit_expr(arg)})"}
  end

  def translate("array_key_exists", [key, map]) do
    {:ok, "Map.has_key?(#{Emitter.emit_expr(map)}, #{Emitter.emit_expr(key)})"}
  end

  def translate("json_decode", [arg | _]) do
    {:ok, "Jason.decode!(#{Emitter.emit_expr(arg)})"}
  end

  def translate("gmdate", [_format]) do
    {:ok, "DateTime.utc_now() |> DateTime.to_iso8601()"}
  end

  def translate("date", [_format]) do
    {:ok, "DateTime.utc_now() |> DateTime.to_iso8601()"}
  end

  def translate("date", [_format, timestamp]) do
    {:ok, "DateTime.from_unix!(#{Emitter.emit_expr(timestamp)}) |> DateTime.to_iso8601()"}
  end

  def translate("strtotime", [arg]) do
    {:ok, "# TODO: strtotime(#{Emitter.emit_expr(arg)})"}
  end

  def translate("time", []) do
    {:ok, "System.os_time(:second)"}
  end

  def translate("strpos", [haystack, needle]) do
    {:ok, "String.contains?(#{Emitter.emit_expr(haystack)}, #{Emitter.emit_expr(needle)})"}
  end

  def translate("preg_match", [{:string, pattern}, subject, {:variable, captures_var}]) do
    {regex, flags} = parse_php_regex(pattern)
    {:ok, "#{captures_var} = Regex.run(~r/#{regex}/#{flags}, #{Emitter.emit_expr(subject)})"}
  end

  def translate("preg_match", [{:string, pattern}, subject]) do
    {regex, flags} = parse_php_regex(pattern)
    {:ok, "Regex.match?(~r/#{regex}/#{flags}, #{Emitter.emit_expr(subject)})"}
  end

  def translate(_name, _args), do: :unknown

  # Parses PHP regex like /pattern/flags, `pattern`flags, ~pattern~flags
  defp parse_php_regex(raw) do
    delimiter = String.first(raw)
    rest = String.slice(raw, 1..-1//1)

    case String.split(rest, delimiter, parts: 2) do
      [pattern, flags] -> {pattern, flags}
      [pattern] -> {pattern, ""}
    end
  end
end
