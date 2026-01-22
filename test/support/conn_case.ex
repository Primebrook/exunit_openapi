defmodule ExUnitOpenAPI.ConnCase do
  @moduledoc """
  Test case for integration tests that need a Phoenix connection.

  Uses the TestApp endpoint for making real HTTP requests through
  the Phoenix stack, which triggers telemetry events.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      # The default endpoint for testing
      @endpoint ExUnitOpenAPI.TestApp.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
