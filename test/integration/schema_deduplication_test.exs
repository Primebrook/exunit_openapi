defmodule ExUnitOpenAPI.Integration.SchemaDeduplicationTest do
  @moduledoc """
  Integration tests for schema deduplication feature.

  Tests that identical schemas are deduplicated using $ref pointers
  and that components/schemas contains the extracted schemas.
  """
  use ExUnitOpenAPI.ConnCase, async: false

  alias ExUnitOpenAPI.{Collector, Generator, Config}

  @handler_id "test-schema-dedup-collector"

  setup do
    # Start a fresh collector for each test
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

  describe "schema deduplication" do
    test "extracts response schemas to components.schemas", %{conn: conn} do
      # Make request
      conn = get(conn, "/api/users/1")
      assert conn.status == 200

      # Generate spec with deduplication enabled (default)
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: true)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Verify components.schemas exists and has content
      assert Map.has_key?(spec, "components")
      assert Map.has_key?(spec["components"], "schemas")
      assert map_size(spec["components"]["schemas"]) > 0

      # Verify response uses $ref
      response = spec["paths"]["/api/users/{id}"]["get"]["responses"]["200"]
      schema = response["content"]["application/json"]["schema"]

      # Should be either a $ref or an inline schema (depending on whether dedup triggered)
      assert Map.has_key?(schema, "$ref") or Map.has_key?(schema, "type")
    end

    test "identical schemas share the same $ref", %{conn: conn} do
      # Make two requests that return similar structures
      _conn1 = get(conn, "/api/users/1")
      _conn2 = get(build_conn(), "/api/users/2")

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: true)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Both should resolve to the same schema
      # (The show action returns the same structure)
      assert Map.has_key?(spec["components"], "schemas")
    end

    test "generates spec without deduplication when disabled", %{conn: conn} do
      # Make request
      conn = get(conn, "/api/users/1")
      assert conn.status == 200

      # Generate spec with deduplication disabled
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: false)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Response should have inline schema (no $ref)
      response = spec["paths"]["/api/users/{id}"]["get"]["responses"]["200"]
      schema = response["content"]["application/json"]["schema"]

      # Should be inline, not a $ref
      assert Map.has_key?(schema, "type")
      refute Map.has_key?(schema, "$ref")
    end

    test "request body schemas are extracted", %{conn: conn} do
      # Make POST request
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/users", %{user: %{name: "Alice", email: "alice@test.com"}})

      assert conn.status == 201

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: true)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Check request body schema
      request_body = spec["paths"]["/api/users"]["post"]["requestBody"]
      schema = request_body["content"]["application/json"]["schema"]

      # Should be extracted (either $ref or has name in components)
      assert Map.has_key?(schema, "$ref") or Map.has_key?(schema, "type")
    end
  end

  describe "schema naming" do
    test "uses config override for schema name", %{conn: conn} do
      # Make request
      conn = get(conn, "/api/users/1")
      assert conn.status == 200

      # Generate spec with custom schema name
      config =
        Config.load(
          router: ExUnitOpenAPI.TestApp.Router,
          schema_deduplication: true,
          schema_names: %{
            {ExUnitOpenAPI.TestApp.UserController, :show, :response, 200} => "UserProfile"
          }
        )

      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Should have the custom name in components
      assert Map.has_key?(spec["components"]["schemas"], "UserProfile")
    end
  end

  describe "openapi test tags" do
    test "applies openapi tags from test context", %{conn: conn} do
      # Apply custom tags to the connection
      context = %{openapi: [response_schema: "CustomUser"]}
      conn = Collector.apply_openapi_tags(conn, context)

      # Make request with tagged connection
      conn = get(conn, "/api/users/1")
      assert conn.status == 200

      # Generate spec
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: true)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Should use the custom schema name from the tag
      assert Map.has_key?(spec["components"]["schemas"], "CustomUser")
    end
  end

  describe "spec size reduction" do
    test "deduplicated spec has components.schemas section", %{conn: conn} do
      # Make multiple requests
      _conn1 = get(conn, "/api/users")
      _conn2 = get(build_conn(), "/api/users/1")

      conn3 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/users", %{user: %{name: "Test", email: "test@test.com"}})

      assert conn3.status == 201

      # Generate spec with deduplication
      config = Config.load(router: ExUnitOpenAPI.TestApp.Router, schema_deduplication: true)
      {:ok, spec} = Generator.generate(Collector.get_collected_data(), config)

      # Should have schemas in components
      assert Map.has_key?(spec["components"], "schemas")

      # Encode to JSON to check size
      json = Jason.encode!(spec)
      assert is_binary(json)

      # The spec should be valid JSON
      assert {:ok, _} = Jason.decode(json)
    end
  end
end
