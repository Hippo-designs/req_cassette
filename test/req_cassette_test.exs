defmodule ReqCassetteTest do
  use ExUnit.Case
  doctest ReqCassette

  test "greets the world" do
    assert ReqCassette.hello() == :world
  end
end
