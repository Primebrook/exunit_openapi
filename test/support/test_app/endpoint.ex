defmodule ExUnitOpenAPI.TestApp.Endpoint do
  @moduledoc """
  Minimal Phoenix endpoint for integration testing.
  """
  use Phoenix.Endpoint, otp_app: :exunit_openapi

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug ExUnitOpenAPI.TestApp.Router
end
