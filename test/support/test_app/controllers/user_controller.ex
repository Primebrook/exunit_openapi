defmodule ExUnitOpenAPI.TestApp.UserController do
  @moduledoc """
  Test controller for user resources.
  """
  use Phoenix.Controller, formats: [:json]

  def index(conn, params) do
    page = Map.get(params, "page", "1")
    per_page = Map.get(params, "per_page", "10")

    users = [
      %{id: 1, name: "Alice", email: "alice@example.com"},
      %{id: 2, name: "Bob", email: "bob@example.com"}
    ]

    conn
    |> put_status(200)
    |> json(%{
      data: users,
      meta: %{page: String.to_integer(page), per_page: String.to_integer(per_page)}
    })
  end

  def show(conn, %{"id" => id}) do
    case id do
      "999" ->
        conn
        |> put_status(404)
        |> json(%{error: "User not found"})

      _ ->
        conn
        |> put_status(200)
        |> json(%{
          id: String.to_integer(id),
          name: "Test User",
          email: "test@example.com",
          created_at: "2024-01-15T10:30:00Z"
        })
    end
  end

  def create(conn, %{"user" => user_params}) do
    conn
    |> put_status(201)
    |> json(%{
      id: 123,
      name: user_params["name"],
      email: user_params["email"],
      created_at: "2024-01-15T10:30:00Z"
    })
  end

  def create(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{error: "Missing user params", details: %{user: ["can't be blank"]}})
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    conn
    |> put_status(200)
    |> json(%{
      id: String.to_integer(id),
      name: user_params["name"],
      email: user_params["email"],
      updated_at: "2024-01-15T11:00:00Z"
    })
  end

  def delete(conn, %{"id" => _id}) do
    conn
    |> put_status(204)
    |> send_resp(204, "")
  end
end
