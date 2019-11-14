defmodule ChronologyTest do
  use ExUnit.Case
  doctest Chronology

  test "greets the world" do
    assert Chronology.hello() == :world
  end
end
