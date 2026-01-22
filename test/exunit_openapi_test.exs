defmodule ExUnitOpenAPITest do
  use ExUnit.Case

  describe "enabled?/0" do
    test "returns false when OPENAPI env var is not set" do
      System.delete_env("OPENAPI")
      refute ExUnitOpenAPI.enabled?()
    end

    test "returns true when OPENAPI env var is set" do
      System.put_env("OPENAPI", "1")
      assert ExUnitOpenAPI.enabled?()
      System.delete_env("OPENAPI")
    end
  end
end
