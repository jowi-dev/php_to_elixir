defmodule PhpToElixirTest do
  use ExUnit.Case
  doctest PhpToElixir

  test "greets the world" do
    assert PhpToElixir.hello() == :world
  end
end
