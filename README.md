# ExUnitOpenAPI

Automatically generate OpenAPI 3.0 specifications from your Phoenix controller tests. Zero annotations required - just run your tests and get documentation.

## The Problem

API documentation is tedious to maintain. Existing solutions require either:
- **Manual OpenAPI specs** that drift from reality
- **Heavy DSL annotations** (OpenApiSpex, PhoenixSwagger) that clutter your code
- **Separate schema definitions** that duplicate what's already in your tests

## The Solution

ExUnitOpenAPI captures HTTP request/response data during your test runs and generates an OpenAPI spec automatically. Your tests become your documentation.

```elixir
# Your existing test - no changes needed
test "returns user by id", %{conn: conn} do
  user = insert(:user, name: "Alice")

  conn = get(conn, "/api/users/#{user.id}")

  assert %{"id" => _, "name" => "Alice"} = json_response(conn, 200)
end
```

Run `OPENAPI=1 mix test` and get a complete OpenAPI spec with paths, parameters, and response schemas inferred from your actual test data.

## Installation

Add `exunit_openapi` to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exunit_openapi, "~> 0.1.0", only: :test}
  ]
end
```

Also add the preferred environment for the mix task:

```elixir
def cli do
  [preferred_envs: ["openapi.generate": :test]]
end
```

## Quick Start

### 1. Configure in `config/test.exs`

```elixir
config :exunit_openapi,
  router: MyAppWeb.Router,
  output: "priv/static/openapi.json",
  info: [
    title: "My API",
    version: "1.0.0",
    description: "My awesome API"
  ]
```

### 2. Add to `test/test_helper.exs`

```elixir
ExUnitOpenAPI.start()
ExUnit.start()
```

### 3. Generate the spec

```bash
# Option 1: Environment variable
OPENAPI=1 mix test

# Option 2: Mix task
mix openapi.generate
```

That's it! Your OpenAPI spec will be generated at the configured output path.

## How It Works

1. **Telemetry Capture**: ExUnitOpenAPI attaches to Phoenix's built-in telemetry events (`[:phoenix, :router_dispatch, :stop]`)

2. **Request Collection**: When your tests make requests via `Phoenix.ConnTest`, the library captures:
   - Request method, path, and parameters
   - Request body (for POST/PUT/PATCH)
   - Response status and JSON body

3. **Route Matching**: Captured requests are matched against your Phoenix router to get path patterns (e.g., `/users/:id`)

4. **Type Inference**: JSON response bodies are analyzed to generate schemas:
   - Primitive types (string, integer, boolean)
   - Objects with properties
   - Arrays with item types
   - Format detection (date-time, uuid, email, uri)

5. **Spec Generation**: Everything is combined into a valid OpenAPI 3.0 specification

## Configuration Options

```elixir
config :exunit_openapi,
  # Required: Your Phoenix router module
  router: MyAppWeb.Router,

  # Output file path (default: "openapi.json")
  output: "priv/static/openapi.json",

  # Output format: :json or :yaml (default: :json)
  format: :json,

  # OpenAPI info object
  info: [
    title: "My API",
    version: "1.0.0",
    description: "API description"
  ],

  # Server URLs (optional)
  servers: [
    %{url: "https://api.example.com", description: "Production"},
    %{url: "https://staging-api.example.com", description: "Staging"}
  ],

  # Security schemes (optional)
  security_schemes: %{
    "BearerAuth" => %{
      "type" => "http",
      "scheme" => "bearer",
      "bearerFormat" => "JWT"
    }
  },

  # Preserve manual edits when regenerating (default: true)
  merge_with_existing: true
```

## Generated Output

Given tests for a users API, ExUnitOpenAPI generates:

```json
{
  "openapi": "3.0.3",
  "info": {
    "title": "My API",
    "version": "1.0.0"
  },
  "paths": {
    "/api/users/{id}": {
      "get": {
        "operationId": "User.show",
        "tags": ["User"],
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {"type": "integer"}
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "id": {"type": "integer"},
                    "name": {"type": "string"},
                    "email": {"type": "string", "format": "email"},
                    "created_at": {"type": "string", "format": "date-time"}
                  }
                }
              }
            }
          },
          "404": {
            "description": "Not found"
          }
        }
      }
    }
  }
}
```

## Tips

### Test Coverage = Documentation Coverage

Only endpoints exercised in your tests will appear in the generated spec. This is a feature, not a bug - it encourages comprehensive testing.

### Multiple Response Codes

Test both success and error cases to document all response types:

```elixir
test "returns user", %{conn: conn} do
  # Documents 200 response
end

test "returns 404 for missing user", %{conn: conn} do
  # Documents 404 response
end
```

### Manual Edits Are Preserved

By default, ExUnitOpenAPI merges with the existing spec file, preserving any manual additions like descriptions or examples. Set `merge_with_existing: false` to always overwrite.

## Roadmap

- [x] Basic request/response capture
- [x] Type inference from JSON
- [x] Router analysis for path patterns
- [x] OpenAPI 3.0 generation
- [ ] Schema deduplication with `$ref`
- [ ] **Security scheme support** (auto-detect from headers, global defaults, per-endpoint overrides)
- [ ] YAML output format
- [ ] Test metadata for descriptions/tags
- [ ] Request validation mode
- [ ] Coverage reporting

## Inspiration

This library is inspired by [rspec-openapi](https://github.com/exoego/rspec-openapi) for Ruby/Rails.

## License

MIT License
