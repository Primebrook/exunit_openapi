# Test Plan for ExUnitOpenAPI v0.2.0

## Current Status
- **175+ tests passing**
- Manual integration test against personal project (16 endpoints generated)
- Priority 1 tests complete
- Partial Priority 2 coverage via regression tests
- v0.2.0 schema deduplication tests complete

## Test Files

| File | Tests | Description |
|------|-------|-------------|
| `test/exunit_openapi/collector_test.exs` | Unit tests for request data collection |
| `test/exunit_openapi/config_test.exs` | 18 | Config loading and accessors |
| `test/exunit_openapi/generator_test.exs` | Unit tests for OpenAPI spec generation |
| `test/exunit_openapi/router_analyzer_test.exs` | Unit tests for Phoenix router analysis |
| `test/exunit_openapi/type_inferrer_test.exs` | 40 | JSON Schema inference (incl. enum, nullable) |
| `test/exunit_openapi/regression_test.exs` | 14 | Regression tests for fixed bugs |
| `test/exunit_openapi/schema_fingerprint_test.exs` | 11 | Schema identity hashing (v0.2.0) |
| `test/exunit_openapi/schema_namer_test.exs` | 15 | Schema naming and overrides (v0.2.0) |
| `test/exunit_openapi/schema_registry_test.exs` | 14 | Deduplication registry (v0.2.0) |
| `test/integration/end_to_end_test.exs` | 9 | Full flow integration tests |
| `test/integration/telemetry_test.exs` | 9 | Telemetry handler integration |
| `test/integration/schema_deduplication_test.exs` | 5 | Schema deduplication flow (v0.2.0) |
| `test/mix/tasks/openapi_generate_test.exs` | 8 | Mix task option parsing |

## Test Infrastructure

### Minimal Phoenix Test App (`test/support/test_app/`)
```
test/support/
├── conn_case.ex              # ExUnit case with Phoenix.ConnTest
└── test_app/
    ├── endpoint.ex           # Minimal Phoenix endpoint
    ├── router.ex             # Test routes
    └── controllers/
        ├── user_controller.ex   # CRUD operations
        ├── post_controller.ex   # Nested resources
        └── test_controller.ex   # Edge cases (empty, null, deep nested)
```

## Completed Tests

### Priority 1: Critical Path Tests ✅

#### 1.1 End-to-End Integration Test
- [x] `ExUnitOpenAPI.start()` attaches telemetry
- [x] Making requests through `Phoenix.ConnTest` triggers capture
- [x] `ExUnitOpenAPI.generate()` produces valid spec
- [x] Spec contains expected paths and schemas
- [x] GET, POST, DELETE requests work
- [x] Query parameters captured
- [x] Nested resources (`/users/:user_id/posts/:id`)
- [x] Multiple response codes (200, 404)
- [x] Array responses
- [x] Deeply nested responses

#### 1.2 Telemetry Integration
- [x] Verify telemetry handler receives conn with expected fields
- [x] Verify capture works with actual Phoenix.Endpoint
- [x] Handler attachment when OPENAPI env is set
- [x] Handler not attached when OPENAPI env is not set
- [x] Collector starts when OPENAPI env is set
- [x] Multiple requests captured
- [x] POST body captured
- [x] Response body captured
- [x] Query parameters captured
- [x] Error resilience when Collector is down

#### 1.3 Mix Task
- [x] Option parsing (--output, --format, --only, --exclude)
- [x] Test argument building from options
- [x] Module has correct shortdoc and moduledoc

#### 1.4 Config Loading
- [x] Config loads from application env
- [x] Options override application env
- [x] Default values used when not configured
- [x] Info keyword list normalized to map
- [x] All accessor functions work
- [x] Edge cases (empty info, nil values, unknown keys)

### v0.2.0: Schema Deduplication Tests ✅

#### SchemaFingerprint
- [x] Returns 64-character hex fingerprint
- [x] Identical schemas produce identical fingerprints
- [x] Property order does not affect fingerprint
- [x] Different schemas produce different fingerprints
- [x] Nested schema property order independence
- [x] Array items fingerprinted correctly
- [x] Empty and non-map input handling

#### SchemaNamer
- [x] Generates names from controller and action
- [x] Create/Update/Delete action prefixes
- [x] Error suffixes for 400/401/403/404/422 status
- [x] Generates names from path when no controller
- [x] Test tag overrides (`@tag openapi: [response_schema: "Name"]`)
- [x] Config overrides via `schema_names` option
- [x] Test tag takes precedence over config
- [x] Collision resolution (User, User2, User3)

#### SchemaRegistry
- [x] Creates registry with config
- [x] Extracts top-level schemas and returns $ref
- [x] Returns same $ref for identical schemas
- [x] Different $refs for different schemas
- [x] Deduplication disabled returns inline schema
- [x] Empty schemas unchanged
- [x] force_inline option
- [x] Finalize returns named schemas map
- [x] Process nested object properties
- [x] Process array items

#### TypeInferrer Enhancements
- [x] Nullable detection when merging with null
- [x] oneOf for mixed types
- [x] infer_with_samples enum detection
- [x] infer_merged for property-level enum detection
- [x] infer_merged nested object handling
- [x] infer_merged optional property nullable marking

#### Integration
- [x] Schema deduplication end-to-end
- [x] $ref generation in responses
- [x] Config-based schema name override
- [x] Test tag schema name override

### Priority 2: Edge Cases (Partial)

#### 2.1 Collector Edge Cases (via regression tests)
- [x] Iolist response body (regression test for bug fix)
- [x] Nested iolist response body
- [x] Binary response body
- [x] Empty response body (`""`)
- [x] Nil response body
- [x] Null JSON response (`"null"`)
- [x] `Plug.Conn.Unfetched` in path_params
- [x] `Plug.Conn.Unfetched` in query_params
- [x] `Plug.Conn.Unfetched` in body_params
- [x] Mixed fetched/unfetched params
- [x] Plain map (not Plug.Conn struct) accepted

#### 2.2 Type Inference Edge Cases (via regression tests)
- [x] Integer arrays (not confused with charlists)
- [x] Small integer arrays (65, 66, 67 - potential charlist confusion)
- [ ] Empty object `{}`
- [ ] Empty array `[]`
- [ ] Null values in objects `{"foo": null}`
- [ ] Mixed-type arrays `[1, "two", true]`
- [ ] Very long strings
- [ ] Unicode strings
- [ ] Numbers at edge of integer range

#### 2.3 Router Matching Edge Cases
- [x] Nested resources (`/users/:user_id/posts/:id`)
- [ ] Catch-all routes (`/*path`)
- [ ] Same path, different methods
- [ ] No matching route (should use literal path)
- [ ] Router with scopes/pipelines

#### 2.4 Generator Edge Cases
- [x] Same endpoint, multiple response codes
- [x] Empty response (204 No Content)
- [ ] Same endpoint, different response schemas (schema union)
- [ ] Endpoint with only error responses tested
- [ ] POST without request body
- [ ] GET with request body (unusual but valid)

### Priority 3: Merge & Persistence
- [ ] New paths added to existing spec
- [ ] Existing paths preserved when not in current run
- [ ] Manual descriptions in existing spec preserved
- [ ] Conflicting schemas handled
- [ ] Invalid existing file handled gracefully
- [ ] `merge_with_existing: false` overwrites completely

### Priority 4: Property-Based Tests (Optional)
- [ ] Type inference produces valid JSON schemas
- [ ] Router matching is consistent
- [ ] Merged schemas are valid

## Key Bug Fixes (with regression tests)

1. **Iolist response bodies**: Phoenix returns iolists, not plain strings. Fixed with `IO.iodata_to_binary/1`.

2. **Unfetched params**: `Plug.Conn.Unfetched` structs handled gracefully, returning empty map.

3. **Conn pattern matching**: Changed from `%Plug.Conn{}` to duck-typing `%{method: _, request_path: _}` since Plug is test-only.

4. **Telemetry event**: Changed from `[:phoenix, :endpoint, :stop]` to `[:phoenix, :router_dispatch, :stop]` - the event that actually fires in Phoenix tests.

## Success Criteria

Before moving to Phase 2:
1. [x] All Priority 1 tests passing
2. [ ] All Priority 2 tests passing
3. [ ] At least basic Priority 3 tests
4. [ ] Code coverage > 90%
5. [x] No known bugs without regression tests

## Next Steps

1. Complete remaining Priority 2 edge case tests
2. Add Priority 3 merge/persistence tests
3. Run coverage report and fill gaps
4. Move to Phase 2 (schema deduplication with `$ref`)
