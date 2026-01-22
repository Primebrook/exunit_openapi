defmodule ExUnitOpenAPI.TestApp.PostController do
  @moduledoc """
  Test controller for nested post resources.
  """
  use Phoenix.Controller, formats: [:json]

  def index(conn, %{"user_id" => user_id}) do
    posts = [
      %{id: 1, title: "First Post", user_id: String.to_integer(user_id)},
      %{id: 2, title: "Second Post", user_id: String.to_integer(user_id)}
    ]

    conn
    |> put_status(200)
    |> json(%{data: posts})
  end

  def show(conn, %{"user_id" => user_id, "id" => id}) do
    conn
    |> put_status(200)
    |> json(%{
      id: String.to_integer(id),
      user_id: String.to_integer(user_id),
      title: "Test Post",
      body: "This is the post content.",
      tags: ["elixir", "phoenix", "testing"]
    })
  end
end
