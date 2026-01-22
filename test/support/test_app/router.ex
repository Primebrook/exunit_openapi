defmodule ExUnitOpenAPI.TestApp.Router do
  @moduledoc """
  Minimal Phoenix router for integration testing.
  """
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ExUnitOpenAPI.TestApp do
    pipe_through :api

    get "/users", UserController, :index
    get "/users/:id", UserController, :show
    post "/users", UserController, :create
    put "/users/:id", UserController, :update
    delete "/users/:id", UserController, :delete

    # Nested resources
    get "/users/:user_id/posts", PostController, :index
    get "/users/:user_id/posts/:id", PostController, :show

    # Edge cases
    get "/empty", TestController, :empty_response
    get "/null", TestController, :null_response
    get "/error", TestController, :error_response
    get "/deep", TestController, :deep_nested
    post "/echo", TestController, :echo
  end
end
