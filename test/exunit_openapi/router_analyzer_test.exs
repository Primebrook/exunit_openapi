defmodule ExUnitOpenAPI.RouterAnalyzerTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.RouterAnalyzer

  describe "to_openapi_path/1" do
    test "converts Phoenix path params to OpenAPI format" do
      assert RouterAnalyzer.to_openapi_path("/users/:id") == "/users/{id}"
    end

    test "converts multiple path params" do
      assert RouterAnalyzer.to_openapi_path("/users/:user_id/posts/:post_id") ==
               "/users/{user_id}/posts/{post_id}"
    end

    test "handles catch-all params" do
      assert RouterAnalyzer.to_openapi_path("/files/*path") == "/files/{path}"
    end

    test "preserves paths without params" do
      assert RouterAnalyzer.to_openapi_path("/users") == "/users"
    end
  end

  describe "extract_path_params/1" do
    test "extracts single param" do
      assert RouterAnalyzer.extract_path_params("/users/:id") == ["id"]
    end

    test "extracts multiple params" do
      assert RouterAnalyzer.extract_path_params("/users/:user_id/posts/:post_id") ==
               ["user_id", "post_id"]
    end

    test "returns empty list for paths without params" do
      assert RouterAnalyzer.extract_path_params("/users") == []
    end
  end

  describe "match_route/3" do
    setup do
      routes = [
        %{path: "/users", method: "GET", controller: UserController, action: :index, pipe_through: []},
        %{path: "/users/:id", method: "GET", controller: UserController, action: :show, pipe_through: []},
        %{path: "/users/:id", method: "PUT", controller: UserController, action: :update, pipe_through: []},
        %{path: "/users/:user_id/posts/:id", method: "GET", controller: PostController, action: :show, pipe_through: []}
      ]
      {:ok, routes: routes}
    end

    test "matches exact path", %{routes: routes} do
      {:ok, route, params} = RouterAnalyzer.match_route("/users", "GET", routes)
      assert route.path == "/users"
      assert route.action == :index
      assert params == %{}
    end

    test "matches path with single param", %{routes: routes} do
      {:ok, route, params} = RouterAnalyzer.match_route("/users/123", "GET", routes)
      assert route.path == "/users/:id"
      assert route.action == :show
      assert params == %{"id" => "123"}
    end

    test "matches path with multiple params", %{routes: routes} do
      {:ok, route, params} = RouterAnalyzer.match_route("/users/1/posts/42", "GET", routes)
      assert route.path == "/users/:user_id/posts/:id"
      assert params == %{"user_id" => "1", "id" => "42"}
    end

    test "distinguishes by HTTP method", %{routes: routes} do
      {:ok, get_route, _} = RouterAnalyzer.match_route("/users/123", "GET", routes)
      {:ok, put_route, _} = RouterAnalyzer.match_route("/users/123", "PUT", routes)

      assert get_route.action == :show
      assert put_route.action == :update
    end

    test "returns :no_match for unknown paths", %{routes: routes} do
      assert RouterAnalyzer.match_route("/unknown", "GET", routes) == :no_match
    end

    test "returns :no_match for unknown methods", %{routes: routes} do
      assert RouterAnalyzer.match_route("/users", "DELETE", routes) == :no_match
    end
  end
end
