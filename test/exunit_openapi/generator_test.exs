defmodule ExUnitOpenAPI.GeneratorTest do
  use ExUnit.Case, async: true

  alias ExUnitOpenAPI.{Generator, Config}

  describe "generate/2" do
    test "generates valid OpenAPI structure" do
      config = Config.load(
        router: nil,
        info: [title: "Test API", version: "1.0.0"]
      )

      collected_data = [
        %{
          method: "GET",
          path: "/users",
          path_params: %{},
          query_params: %{},
          body_params: %{},
          response_status: 200,
          response_body: [%{"id" => 1, "name" => "Alice"}],
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      assert spec["openapi"] == "3.0.3"
      assert spec["info"]["title"] == "Test API"
      assert spec["info"]["version"] == "1.0.0"
      assert is_map(spec["paths"])
    end

    test "generates paths from collected data" do
      config = Config.load(router: nil, info: [title: "Test", version: "1.0"])

      collected_data = [
        %{
          method: "GET",
          path: "/users/123",
          path_params: %{},
          query_params: %{},
          body_params: %{},
          response_status: 200,
          response_body: %{"id" => 123, "name" => "Alice"},
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      assert Map.has_key?(spec["paths"], "/users/123")
      assert Map.has_key?(spec["paths"]["/users/123"], "get")
    end

    test "generates response schemas from response body" do
      # Disable deduplication to test inline schema generation
      config = Config.load(router: nil, info: [title: "Test", version: "1.0"], schema_deduplication: false)

      collected_data = [
        %{
          method: "GET",
          path: "/users",
          path_params: %{},
          query_params: %{},
          body_params: %{},
          response_status: 200,
          response_body: %{"id" => 1, "name" => "Alice", "email" => "alice@example.com"},
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      response = spec["paths"]["/users"]["get"]["responses"]["200"]
      schema = response["content"]["application/json"]["schema"]

      assert schema["type"] == "object"
      assert schema["properties"]["id"]["type"] == "integer"
      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["email"]["type"] == "string"
    end

    test "generates multiple response codes for same endpoint" do
      config = Config.load(router: nil, info: [title: "Test", version: "1.0"])

      collected_data = [
        %{
          method: "GET",
          path: "/users/123",
          path_params: %{},
          query_params: %{},
          body_params: %{},
          response_status: 200,
          response_body: %{"id" => 123},
          content_type: "application/json"
        },
        %{
          method: "GET",
          path: "/users/999",
          path_params: %{},
          query_params: %{},
          body_params: %{},
          response_status: 404,
          response_body: %{"error" => "Not found"},
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      # Both paths should be present (without router, they're treated as different paths)
      assert Map.has_key?(spec["paths"], "/users/123")
      assert Map.has_key?(spec["paths"], "/users/999")
    end

    test "generates request body for POST requests" do
      # Disable deduplication to test inline schema generation
      config = Config.load(router: nil, info: [title: "Test", version: "1.0"], schema_deduplication: false)

      collected_data = [
        %{
          method: "POST",
          path: "/users",
          path_params: %{},
          query_params: %{},
          body_params: %{"name" => "Alice", "email" => "alice@example.com"},
          response_status: 201,
          response_body: %{"id" => 1, "name" => "Alice"},
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      request_body = spec["paths"]["/users"]["post"]["requestBody"]
      assert request_body["required"] == true

      schema = request_body["content"]["application/json"]["schema"]
      assert schema["type"] == "object"
      assert schema["properties"]["name"]["type"] == "string"
      assert schema["properties"]["email"]["type"] == "string"
    end

    test "generates query parameters" do
      config = Config.load(router: nil, info: [title: "Test", version: "1.0"])

      collected_data = [
        %{
          method: "GET",
          path: "/users",
          path_params: %{},
          query_params: %{"page" => "1", "per_page" => "10"},
          body_params: %{},
          response_status: 200,
          response_body: [],
          content_type: "application/json"
        }
      ]

      {:ok, spec} = Generator.generate(collected_data, config)

      params = spec["paths"]["/users"]["get"]["parameters"]
      param_names = Enum.map(params, & &1["name"])

      assert "page" in param_names
      assert "per_page" in param_names

      page_param = Enum.find(params, &(&1["name"] == "page"))
      assert page_param["in"] == "query"
      assert page_param["schema"]["type"] == "integer"
    end

    test "includes servers when configured" do
      config = Config.load(
        router: nil,
        info: [title: "Test", version: "1.0"],
        servers: [%{url: "https://api.example.com", description: "Production"}]
      )

      {:ok, spec} = Generator.generate([], config)

      assert spec["servers"] == [%{url: "https://api.example.com", description: "Production"}]
    end

    test "includes security schemes when configured" do
      config = Config.load(
        router: nil,
        info: [title: "Test", version: "1.0"],
        security_schemes: %{
          "BearerAuth" => %{"type" => "http", "scheme" => "bearer"}
        }
      )

      {:ok, spec} = Generator.generate([], config)

      assert spec["components"]["securitySchemes"]["BearerAuth"]["type"] == "http"
    end
  end
end
