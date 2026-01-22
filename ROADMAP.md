# ExUnitOpenAPI Roadmap

Automatically generate OpenAPI specifications from Phoenix controller tests. Zero annotations required.

---

## Vision

**API documentation should be a byproduct of testing, not a separate maintenance burden.**

ExUnitOpenAPI captures HTTP request/response data during test runs and generates OpenAPI specs automatically. Your tests become your documentation - if it's tested, it's documented; if it's not tested, it shouldn't be documented.

Inspired by Ruby's [rspec-openapi](https://github.com/exoego/rspec-openapi).

---

## Current Status

| Metric | Value |
|--------|-------|
| Version | 0.1.0 (MVP) |
| Tests | 108 passing |
| Test Coverage | Priority 1 complete, Priority 2 partial |
| Validated Against | Personal Project (16 endpoints from 50 tests) |

### What Works Today

- **Zero-config capture**: Attaches to Phoenix telemetry, captures all controller test requests automatically
- **Router analysis**: Parses `__routes__/0` to match requests to path patterns (`/users/123` → `/users/{id}`)
- **Type inference**: Generates JSON Schema from response bodies with format detection (uuid, date-time, email, uri)
- **Full request capture**: Method, path, query params, body params, headers
- **Full response capture**: Status code, body, headers, content type
- **Multiple response codes**: Documents all status codes observed (200, 404, 422, etc.)
- **Controller-based tags**: Auto-generates tags from controller names
- **Merge with existing**: Preserves manual edits when regenerating
- **Mix task**: `mix openapi.generate` or `OPENAPI=1 mix test`

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ExUnit Test Run                        │
│                                                             │
│  Phoenix.ConnTest requests trigger telemetry events         │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              ExUnitOpenAPI.Collector                │   │
│  │   (GenServer capturing conn via [:phoenix,          │   │
│  │    :router_dispatch, :stop] telemetry)              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Post-Test Processing                      │
│                                                             │
│  RouterAnalyzer ──▶ TypeInferrer ──▶ Generator             │
│  (path patterns)    (JSON schemas)   (OpenAPI spec)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    openapi.json output
```

### Library Structure

```
lib/
├── exunit_openapi.ex           # Main entry point, telemetry attachment
├── exunit_openapi/
│   ├── collector.ex            # GenServer for request/response capture
│   ├── router_analyzer.ex      # Phoenix router parsing
│   ├── type_inferrer.ex        # JSON Schema inference
│   ├── generator.ex            # OpenAPI spec generation
│   ├── config.ex               # Configuration management
│   └── application.ex          # OTP application
└── mix/tasks/
    └── openapi.generate.ex     # Mix task
```

---

## Release Plan

### v0.1.0 - MVP ✅ (Current)

**Status: Complete**

The minimum viable product that generates useful OpenAPI specs from existing Phoenix tests.

#### Features Delivered
- [x] Telemetry-based capture (zero test modification)
- [x] Router analysis for path patterns
- [x] Type inference (primitives, objects, arrays)
- [x] Format detection (uuid, date-time, email, uri)
- [x] Path parameter extraction
- [x] Query parameter capture
- [x] Request body schemas (POST/PUT/PATCH)
- [x] Response schemas from JSON bodies
- [x] Multiple response codes per endpoint
- [x] Controller-based operation IDs and tags
- [x] Merge with existing spec
- [x] Mix task (`mix openapi.generate`)
- [x] JSON output

#### Known Limitations
- No `$ref` schema deduplication (schemas are inlined)
- No automatic descriptions (only generic ones)
- No example values in schemas
- No YAML output
- Test coverage = documentation coverage

---

### v0.2.0 - Enhanced Type Inference

**Status: Not Started**

Smarter schema generation with deduplication and enhanced type detection.

#### Planned Features
- [ ] **Schema deduplication with `$ref`**: Detect similar response structures, create reusable component schemas
- [ ] **Component schema generation**: Move repeated schemas to `#/components/schemas/`
- [ ] **Schema naming**: Generate meaningful names (`UserShowResponse`, `CreateUserRequest`)
- [ ] **Enum inference**: Detect repeated string values and generate enum types
- [ ] **Nullable field detection**: Track when fields are sometimes null
- [ ] **oneOf/anyOf for mixed types**: Handle arrays with mixed types properly

#### Success Criteria
- Generated specs are 50%+ smaller due to deduplication
- Schema names are human-readable and consistent
- Nullable fields correctly documented

---

### v0.3.0 - Developer Experience

**Status: Not Started**

Polish and convenience features for day-to-day use.

#### Planned Features
- [ ] **YAML output format**: `format: :yaml` config option
- [ ] **Optional test metadata**: Allow descriptions/tags via `@tag openapi: [...]`
- [ ] **Diff mode**: `mix openapi.generate --diff` shows what changed
- [ ] **Better merge strategy**: Smarter conflict resolution when merging
- [ ] **Warnings for undocumented endpoints**: Alert when routes exist but aren't tested
- [ ] **Custom operation IDs**: Override auto-generated operation IDs

#### Success Criteria
- YAML output validates against OpenAPI spec
- Diff mode clearly shows additions/removals/modifications
- Metadata opt-in is truly optional (no test changes required for basic use)

---

### v0.4.0 - Validation & Coverage

**Status: Not Started**

Ensure API behavior matches documentation.

#### Planned Features
- [ ] **Request validation mode**: Fail tests if requests don't match documented spec
- [ ] **Response validation mode**: Fail tests if responses don't match documented schemas
- [ ] **Coverage reporting**: `mix openapi.coverage` shows which endpoints lack tests
- [ ] **Strict mode**: Require all routes to have test coverage

#### Success Criteria
- Validation catches real mismatches between code and docs
- Coverage report identifies documentation gaps
- < 5% performance impact on test suite

---

### v1.0.0 - Production Ready

**Status: Not Started**

Feature-complete, battle-tested, ready for production use.

#### Planned Features
- [ ] **Multi-spec support**: Generate separate specs for API versions
- [ ] **CI integration helpers**: GitHub Action, fail-on-change mode
- [ ] **Auto-commit spec updates**: Option to commit generated changes
- [ ] **Publish to doc platforms**: Integrate with SwaggerHub, Redoc, etc.
- [ ] **Example Phoenix project**: Reference implementation
- [ ] **Comprehensive documentation**: Guides, tutorials, API docs

#### Success Criteria
- Used in 3+ production Phoenix projects
- Zero known bugs without regression tests
- Performance impact < 5%
- Complete documentation

---

## Testing Strategy

### Test Categories

| Priority | Category | Status | Tests |
|----------|----------|--------|-------|
| 1 | End-to-end integration | ✅ Complete | 9 |
| 1 | Telemetry integration | ✅ Complete | 9 |
| 1 | Mix task | ✅ Complete | 8 |
| 1 | Config loading | ✅ Complete | 18 |
| 1 | Regression tests | ✅ Complete | 14 |
| 2 | Collector edge cases | ✅ Partial | (in regression) |
| 2 | Type inference edge cases | 🔄 Partial | (in unit tests) |
| 2 | Router matching edge cases | 🔄 Partial | (in unit tests) |
| 2 | Generator edge cases | 🔄 Partial | (in integration) |
| 3 | Merge & persistence | ⬜ Not started | - |
| 4 | Property-based tests | ⬜ Not started | - |

### Test Infrastructure

```
test/
├── test_helper.exs
├── support/
│   ├── conn_case.ex                    # Phoenix test case
│   └── test_app/                       # Minimal Phoenix app
│       ├── endpoint.ex
│       ├── router.ex
│       └── controllers/
│           ├── user_controller.ex      # CRUD operations
│           ├── post_controller.ex      # Nested resources
│           └── test_controller.ex      # Edge cases
├── exunit_openapi/
│   ├── collector_test.exs
│   ├── config_test.exs
│   ├── generator_test.exs
│   ├── router_analyzer_test.exs
│   ├── type_inferrer_test.exs
│   └── regression_test.exs
├── integration/
│   ├── end_to_end_test.exs
│   └── telemetry_test.exs
└── mix/tasks/
    └── openapi_generate_test.exs
```

### Bug Fixes (with regression tests)

1. **Iolist response bodies**: Phoenix returns iolists, not plain strings
2. **Unfetched params**: `Plug.Conn.Unfetched` structs handled gracefully
3. **Conn pattern matching**: Duck-typing instead of `%Plug.Conn{}` struct
4. **Telemetry event**: Changed to `[:phoenix, :router_dispatch, :stop]`

---

## Configuration Reference

```elixir
# config/test.exs
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
    %{url: "https://api.example.com", description: "Production"}
  ],

  # Security schemes (optional)
  security_schemes: %{
    "BearerAuth" => %{
      "type" => "http",
      "scheme" => "bearer"
    }
  },

  # Preserve manual edits when regenerating (default: true)
  merge_with_existing: true
```

---

## Usage

### Quick Start

```elixir
# 1. Add to mix.exs
{:exunit_openapi, "~> 0.1.0", only: :test}

# 2. Configure in config/test.exs
config :exunit_openapi,
  router: MyAppWeb.Router,
  output: "priv/static/openapi.json",
  info: [title: "My API", version: "1.0.0"]

# 3. Add to test/test_helper.exs
ExUnitOpenAPI.start()
ExUnit.start()

# 4. Generate spec
OPENAPI=1 mix test
# or
mix openapi.generate
```

### Your tests stay unchanged

```elixir
# No annotations needed - just normal Phoenix tests
test "returns user by id", %{conn: conn} do
  user = insert(:user, name: "Alice")
  conn = get(conn, "/api/users/#{user.id}")
  assert %{"id" => _, "name" => "Alice"} = json_response(conn, 200)
end
```

---

## Open Questions

1. **Ecto schema integration**: Should we optionally read Ecto schemas for enhanced type info?
2. **Authentication inference**: Can we detect auth requirements from plugs?
3. **Error response patterns**: Should we detect common patterns like `{:error, changeset}`?
4. **LiveView support**: Is there value in documenting LiveView events?

---

## Contributing

See [TEST_PLAN.md](TEST_PLAN.md) for testing requirements before submitting PRs.

Priority areas for contribution:
1. Complete Priority 2 edge case tests
2. Schema deduplication (v0.2.0)
3. YAML output (v0.3.0)
