# Changelog

All notable changes to ExUnitOpenAPI will be documented in this file.

## [0.2.0] - 2026-01-22

### Schema Deduplication & Enhanced Type Inference

This release adds intelligent schema deduplication with `$ref` support, enum inference, and nullable field detection.

#### Added

- **Schema deduplication with `$ref`**: Identical schemas are automatically deduplicated using JSON Reference pointers. Extracted schemas appear in `components/schemas`.
- **Schema naming**: Context-aware names like `UserResponse`, `CreateUserRequest`, `UserNotFoundError` generated automatically from controller, action, and status.
- **Schema name overrides**: Two ways to customize schema names:
  - Config: `schema_names: %{{UserController, :show, :response, 200} => "UserProfile"}`
  - Test tags: `@tag openapi: [response_schema: "CustomName"]`
- **Enum inference**: String fields with limited unique values across requests are inferred as enums.
- **Nullable detection**: Properties missing in some requests are marked `nullable: true`.
- **oneOf support**: Arrays with genuinely mixed types (not just nullable) use `oneOf`.
- **New `infer_merged/2` function**: Aggregates values by property for proper enum detection.

#### New Modules

- `ExUnitOpenAPI.SchemaFingerprint` - Deterministic SHA256 hashing for schema identity
- `ExUnitOpenAPI.SchemaNamer` - Context-based schema naming with collision resolution
- `ExUnitOpenAPI.SchemaRegistry` - Central registry for deduplication and `$ref` generation

#### New Configuration Options

```elixir
config :exunit_openapi,
  schema_deduplication: true,        # Enable $ref deduplication (default: true)
  schema_names: %{},                 # Override inferred schema names
  extract_single_use: false,         # Extract schemas used only once
  min_properties_for_extraction: 3,  # Min properties for nested extraction
  enum_inference: true,              # Auto-detect enums (default: true)
  enum_min_samples: 3,               # Min samples for enum detection
  enum_max_values: 10                # Max unique values for enum
```

#### Changed

- Generator now uses `SchemaRegistry` for all schema handling
- `TypeInferrer.merge_schemas/1` now properly handles nullable detection
- Response and request body schemas are registered and potentially extracted

#### Tests

- 175+ tests passing (up from 108)
- New test files for schema modules
- Integration tests for schema deduplication

---

## [0.1.0] - 2026-01-22

### Initial Release - MVP

First working version of ExUnitOpenAPI. Generates OpenAPI 3.0.3 specifications from Phoenix controller tests with zero annotations required.

#### Features

- **Telemetry-based capture**: Automatically hooks into `[:phoenix, :router_dispatch, :stop]` events to capture HTTP request/response data during test runs
- **Router analysis**: Parses Phoenix router's `__routes__/0` to extract path patterns and match requests to route definitions
- **Type inference**: Infers JSON Schema types from actual request/response data:
  - Primitives: string, integer, number, boolean, null
  - Objects with nested properties
  - Arrays with item schemas
  - Format detection: uuid, date, date-time, email, uri
- **Path parameters**: Extracts from router patterns (`:id` → `{id}` in OpenAPI format)
- **Query parameters**: Captured from request data
- **Request body schemas**: Generated for POST/PUT/PATCH requests
- **Response schemas**: Inferred from JSON response bodies
- **Multiple response codes**: Documents all status codes observed in tests (200, 404, 422, etc.)
- **Controller-based tags**: Auto-generates tags from controller names (`UserController` → "User")
- **Merge with existing**: Preserves manual edits when regenerating spec
- **Mix task**: `mix openapi.generate` runs tests and generates spec
- **Configuration**: Router, output path, format, info section, servers, security schemes

#### Known Limitations

- No `$ref` schema deduplication (schemas are inlined, making large specs)
- No automatic descriptions (only generic ones like "Successful response")
- No example values in schemas
- No YAML output (JSON only)
- Test coverage = documentation coverage (untested endpoints won't appear)

#### Bug Fixes During Development

- Handle `Plug.Conn.Unfetched` structs in path/query/body params
- Handle iolist response bodies (Phoenix uses these instead of plain strings)
- Use `[:phoenix, :router_dispatch, :stop]` telemetry event (not `[:phoenix, :endpoint, :stop]`)
- Use duck-typing for conn pattern matching (Plug is test-only dependency)

---

## Roadmap

### Phase 2 (v0.2.0) - Enhanced Type Inference ✅
- [x] Schema deduplication with `$ref`
- [x] Component schema generation
- [x] Enum inference from repeated string values
- [x] Nullable field detection
- [x] Schema naming with overrides

### Phase 2.5 (v0.2.5) - Security Scheme Support
- [ ] Apply security to operations
- [ ] Auto-detect security from request headers
- [ ] Test tag overrides for security

### Phase 3 (v0.3.0) - Developer Experience
- [ ] Optional test metadata for descriptions/tags
- [ ] YAML output format
- [ ] Diff mode (show changes between runs)
- [x] Merge with existing spec (basic - done in 0.1.0)

### Phase 4 (v1.0.0) - Production Ready
- [ ] Request validation mode
- [ ] Coverage reporting (which endpoints lack tests)
- [ ] Multi-spec support (separate specs for API versions)
- [ ] CI integration helpers

---

## Testing Status

### Library Tests
- **175+ tests passing**
- Unit tests: TypeInferrer, RouterAnalyzer, Collector, Generator, Config
- Unit tests: SchemaFingerprint, SchemaNamer, SchemaRegistry (v0.2.0)
- Integration tests: End-to-end flow, telemetry capture, schema deduplication
- Regression tests: Bug fixes for iolist, unfetched params, telemetry event

### Integration Testing
- Tested against personal project
- Generated spec for 16 endpoints from 50 API controller tests
- Validated output in Swagger Editor
