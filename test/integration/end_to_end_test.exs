defmodule ExUnitOpenAPI.Integration.EndToEndTest do
  @moduledoc """
  End-to-end integration tests that verify the complete flow:
  1. Start collector
  2. Attach telemetry
  3. Make HTTP requests through Phoenix
  4. Generate OpenAPI spec
  5. Verify spec contents
  """
  use ExUnitOpenAPI.ConnCase, async: false

  alias ExUnitOpenAPI.{Collector, Generator, Config}

  @handler_id "test-openapi-collector"

  # Helper to resolve $ref in a schema - returns the actual schema from components
  defp resolve_schema(schema, spec) do
    case schema do
      %{"$ref" => "#/components/schemas/" <> name} ->
        spec["components"]["schemas"][name]

      _ ->
        schema
    end
  end

  setup do
    # Start a fresh collector for each test
    # Stop existing collector if running
    if Process.whereis(Collector) do
      GenServer.stop(Collector)
    end

    {:ok, _pid} = Collector.start_link([])

    # Detach existing handler if any
    :telemetry.detach(@handler_id)

    # Attach telemetry handler
    :telemetry.attach(
      @handler_id,
      [:phoenix, :router_dispatch, :stop],
      &__MODULE__.handle_telemetry/4,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(@handler_id)
      if Process.whereis(Collector) do
        Collector.clear()
      end
    end)

    :ok
  end

  def handle_telemetry(_event, _measurements, metadata, _config) do
    case metadata do
      %{conn: conn} -> Collector.capture(conn)
      _ -> :ok
    end
  end

  describe "complete flow" do
    test "generates spec from GET request", %{conn: conn} do
      # Make request
      conn = get(conn, "/api/users/1")
      assert conn.status == 200

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Verify spec structure
      assert spec["openapi"] == "3.0.3"
      assert Map.has_key?(spec["paths"], "/api/users/{id}")

      # Verify operation
      operation = spec["paths"]["/api/users/{id}"]["get"]
      assert operation["operationId"] == "User.show"
      assert operation["tags"] == ["User"]

      # Verify parameters
      [param] = operation["parameters"]
      assert param["name"] == "id"
      assert param["in"] == "path"
      assert param["required"] == true
      assert param["schema"]["type"] == "integer"

      # Verify response
      response = operation["responses"]["200"]
      assert response["description"] == "Successful response"

      schema_ref = response["content"]["application/json"]["schema"]
      schema = resolve_schema(schema_ref, spec)
      assert schema["type"] == "object"
      assert schema["properties"]["id"]["type"] == "integer"
      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["email"]["type"] == "string"
      assert schema["properties"]["created_at"]["format"] == "date-time"
    end

    test "generates spec from POST request with body", %{conn: conn} do
      # Make request
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/users", %{user: %{name: "Alice", email: "alice@test.com"}})

      assert conn.status == 201

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Verify request body
      operation = spec["paths"]["/api/users"]["post"]
      request_body = operation["requestBody"]

      assert request_body["required"] == true
      schema_ref = request_body["content"]["application/json"]["schema"]
      schema = resolve_schema(schema_ref, spec)
      assert schema["type"] == "object"
      assert schema["properties"]["user"]["type"] == "object"
      assert schema["properties"]["user"]["properties"]["name"]["type"] == "string"
      assert schema["properties"]["user"]["properties"]["email"]["type"] == "string"

      # Verify response
      response_schema_ref = operation["responses"]["201"]["content"]["application/json"]["schema"]
      response_schema = resolve_schema(response_schema_ref, spec)
      assert response_schema["properties"]["id"]["type"] == "integer"
    end

    test "generates spec with multiple response codes", %{conn: conn} do
      # Make successful request
      conn1 = get(conn, "/api/users/1")
      assert conn1.status == 200

      # Make failing request
      conn2 = get(conn, "/api/users/999")
      assert conn2.status == 404

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Verify both response codes documented
      operation = spec["paths"]["/api/users/{id}"]["get"]
      assert Map.has_key?(operation["responses"], "200")
      assert Map.has_key?(operation["responses"], "404")

      # Verify error response schema
      error_schema_ref = operation["responses"]["404"]["content"]["application/json"]["schema"]
      error_schema = resolve_schema(error_schema_ref, spec)
      assert error_schema["properties"]["error"]["type"] == "string"
    end

    test "generates spec with query parameters", %{conn: conn} do
      conn = get(conn, "/api/users", page: "2", per_page: "25")
      assert conn.status == 200

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      operation = spec["paths"]["/api/users"]["get"]
      params = operation["parameters"]

      param_names = Enum.map(params, & &1["name"])
      assert "page" in param_names
      assert "per_page" in param_names

      page_param = Enum.find(params, &(&1["name"] == "page"))
      assert page_param["in"] == "query"
      assert page_param["schema"]["type"] == "integer"
    end

    test "generates spec with nested resource paths", %{conn: conn} do
      conn = get(conn, "/api/users/1/posts/5")
      assert conn.status == 200

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Verify nested path
      assert Map.has_key?(spec["paths"], "/api/users/{user_id}/posts/{id}")

      operation = spec["paths"]["/api/users/{user_id}/posts/{id}"]["get"]
      params = operation["parameters"]

      param_names = Enum.map(params, & &1["name"])
      assert "user_id" in param_names
      assert "id" in param_names
    end

    test "generates spec with array response", %{conn: conn} do
      conn = get(conn, "/api/users")
      assert conn.status == 200

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      response_schema_ref =
        spec["paths"]["/api/users"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]

      response_schema = resolve_schema(response_schema_ref, spec)

      # Response has data array
      assert response_schema["properties"]["data"]["type"] == "array"

      # Array items have user properties (may be $ref or inline)
      item_schema_ref = response_schema["properties"]["data"]["items"]
      item_schema = resolve_schema(item_schema_ref, spec)
      assert item_schema["properties"]["id"]["type"] == "integer"
      assert item_schema["properties"]["name"]["type"] == "string"
    end

    test "handles empty response body", %{conn: conn} do
      conn = delete(conn, "/api/users/1")
      assert conn.status == 204

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      operation = spec["paths"]["/api/users/{id}"]["delete"]
      response = operation["responses"]["204"]

      assert response["description"] == "No content"
      # No content body for 204
      refute Map.has_key?(response, "content")
    end

    test "handles deeply nested response", %{conn: conn} do
      conn = get(conn, "/api/deep")
      assert conn.status == 200

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      response_schema_ref =
        spec["paths"]["/api/deep"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]

      response_schema = resolve_schema(response_schema_ref, spec)

      # Navigate the nested structure
      assert response_schema["properties"]["level1"]["type"] == "object"

      level5 =
        response_schema["properties"]["level1"]["properties"]["level2"]["properties"]["level3"]["properties"]["level4"]["properties"]["level5"]

      assert level5["type"] == "object"
      assert level5["properties"]["value"]["type"] == "string"
    end
  end

  describe "multiple requests same endpoint" do
    test "merges schemas from multiple requests", %{conn: conn} do
      # First request returns user with certain fields
      conn1 = get(conn, "/api/users/1")
      assert conn1.status == 200

      # Second request (different id, same endpoint)
      conn2 = get(conn, "/api/users/2")
      assert conn2.status == 200

      config = Config.load(router: ExUnitOpenAPI.TestApp.Router)
      collected = Collector.get_collected_data()

      # Should have 2 captured requests
      assert length(collected) == 2

      {:ok, spec} = Generator.generate(collected, config)

      # Should only have one path entry (merged)
      assert Map.has_key?(spec["paths"], "/api/users/{id}")
      refute Map.has_key?(spec["paths"], "/api/users/1")
      refute Map.has_key?(spec["paths"], "/api/users/2")
    end
  end
end
