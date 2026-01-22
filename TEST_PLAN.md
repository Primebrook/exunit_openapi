# Test Plan for ExUnitOpenAPI v0.1.0

## Current Status
- **108 tests passing**
- Manual integration test against personal project (16 endpoints generated)
- Priority 1 tests complete
- Partial Priority 2 coverage via regression tests

## Test Files

| File | Tests | Description |
|------|-------|-------------|
| `test/exunit_openapi/collector_test.exs` | Unit tests for request data collection |
| `test/exunit_openapi/config_test.exs` | 18 | Config loading and accessors |
| `test/exunit_openapi/generator_test.exs` | Unit tests for OpenAPI spec generation |
| `test/exunit_openapi/router_analyzer_test.exs` | Unit tests for Phoenix router analysis |
| `test/exunit_openapi/type_inferrer_test.exs` | Unit tests for JSON Schema inference |
| `test/exunit_openapi/regression_test.exs` | 14 | Regression tests for fixed bugs |
| `test/integration/end_to_end_test.exs` | 9 | Full flow integration tests |
| `test/integration/telemetry_test.exs` | 9 | Telemetry handler integration |
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
