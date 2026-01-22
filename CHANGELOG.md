# Changelog

All notable changes to ExUnitOpenAPI will be documented in this file.

## [0.1.0] - 2026-01-22

### Initial Release - MVP

First working version of ExUnitOpenAPI. Generates OpenAPI 3.0.3 specifications from Phoenix controller tests with zero annotations required.

#### Features

- **Telemetry-based capture**: Automatically hooks into `[:phoenix, :endpoint, :stop]` events to capture HTTP request/response data during test runs
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
- Handle charlists in type inference

---

## Roadmap

### Phase 2 (v0.2.0) - Enhanced Type Inference
- [ ] Schema deduplication with `$ref`
- [ ] Component schema generation
- [ ] Enum inference from repeated string values
- [ ] Nullable field detection

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
- 50 unit tests passing
- Tests cover: TypeInferrer, RouterAnalyzer, Collector, Generator, Config

### Integration Testing
- Tested against Zappi data-api project
- Generated spec for 16 endpoints from 50 API controller tests
- Validated output in Swagger Editor
