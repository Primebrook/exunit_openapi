defmodule ExUnitOpenAPI.TestApp.TestController do
  @moduledoc """
  Test controller for edge cases.
  """
  use Phoenix.Controller, formats: [:json]

  def empty_response(conn, _params) do
    conn
    |> put_status(204)
    |> send_resp(204, "")
  end

  def null_response(conn, _params) do
    conn
    |> put_status(200)
    |> json(nil)
  end

  def error_response(conn, _params) do
    conn
    |> put_status(500)
    |> json(%{
      error: "Internal server error",
      request_id: "550e8400-e29b-41d4-a716-446655440000"
    })
  end

  def deep_nested(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{
      level1: %{
        level2: %{
          level3: %{
            level4: %{
              level5: %{
                value: "deeply nested"
              }
            }
          }
        }
      }
    })
  end

  def echo(conn, params) do
    conn
    |> put_status(200)
    |> json(%{
      received: params,
      timestamp: "2024-01-15T10:30:00Z"
    })
  end
end
