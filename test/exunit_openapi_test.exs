defmodule ExunitOpenapiTest do
  use ExUnit.Case
  doctest ExunitOpenapi

  test "greets the world" do
    assert ExunitOpenapi.hello() == :world
  end
end
