# Test Plan for ExUnitOpenAPI v0.1.0

## Current Status
- 50 unit tests passing
- Manual integration test against data-api (16 endpoints generated)

## Test Gaps to Address

### Priority 1: Critical Path Tests

#### 1.1 End-to-End Integration Test
Create a minimal Phoenix app in `test/support/` and test the full flow:
- [ ] `ExUnitOpenAPI.start()` attaches telemetry
- [ ] Making requests through `Phoenix.ConnTest` triggers capture
- [ ] `ExUnitOpenAPI.generate()` produces valid spec
- [ ] Spec contains expected paths and schemas

#### 1.2 Telemetry Integration
- [ ] Verify telemetry handler receives conn with expected fields
- [ ] Verify capture works with actual Phoenix.Endpoint (not mocked conn)
- [ ] Test that non-API requests (LiveView, static) are handled gracefully

#### 1.3 Mix Task
- [ ] `mix openapi.generate` runs tests
- [ ] Output file is created at configured path
- [ ] `--output` flag overrides config

#### 1.4 Config Loading
- [ ] Config loads from application env
- [ ] Options override application env
- [ ] Missing router config handled gracefully
- [ ] Invalid config values raise helpful errors

### Priority 2: Edge Cases

#### 2.1 Collector Edge Cases
- [ ] Iolist response body (regression test for bug fix)
- [ ] Empty response body (`""`)
- [ ] Nil response body
- [ ] Response body that isn't valid JSON
- [ ] `Plug.Conn.Unfetched` in all param locations
- [ ] Missing fields in conn (defensive handling)

#### 2.2 Type Inference Edge Cases
- [ ] Empty object `{}`
- [ ] Empty array `[]`
- [ ] Null values in objects `{"foo": null}`
- [ ] Mixed-type arrays `[1, "two", true]`
- [ ] Deeply nested (5+ levels)
- [ ] Very long strings
- [ ] Unicode strings
- [ ] Numbers at edge of integer range

#### 2.3 Router Matching Edge Cases
- [ ] Catch-all routes (`/*path`)
- [ ] Nested resources (`/users/:user_id/posts/:id`)
- [ ] Same path, different methods
- [ ] No matching route (should use literal path)
- [ ] Router with scopes/pipelines

#### 2.4 Generator Edge Cases
- [ ] Same endpoint, multiple response codes
- [ ] Same endpoint, different response schemas (schema union)
- [ ] Endpoint with only error responses tested
- [ ] POST without request body
- [ ] GET with request body (unusual but valid)

### Priority 3: Merge & Persistence

#### 3.1 Merge with Existing Spec
- [ ] New paths added to existing spec
- [ ] Existing paths preserved when not in current run
- [ ] Manual descriptions in existing spec preserved
- [ ] Conflicting schemas handled (new wins? merge?)
- [ ] Invalid existing file handled gracefully
- [ ] `merge_with_existing: false` overwrites completely

### Priority 4: Property-Based Tests (Optional but Valuable)

#### 4.1 Type Inference Properties
- [ ] `infer(value) |> valid_json_schema?()` for any JSON-encodable value
- [ ] `infer(decode(encode(value)))` is consistent
- [ ] Merged schemas are valid schemas

#### 4.2 Router Matching Properties
- [ ] If `match_route(path, routes)` succeeds, `to_openapi_path(route.path)` is valid
- [ ] Path params extracted match those in pattern

## Test Infrastructure Needed

### Minimal Phoenix Test App
Create in `test/support/test_app/`:
```
test/support/
├── test_app/
│   ├── endpoint.ex
│   ├── router.ex
│   └── controllers/
│       └── test_controller.ex
└── conn_case.ex
```

This allows testing the real telemetry flow without mocking.

### Test Helpers
- `valid_openapi_spec?(spec)` - Validates against OpenAPI 3.0 schema
- `has_path?(spec, path, method)` - Checks spec has endpoint
- `schema_for_response(spec, path, method, status)` - Extracts response schema

## Success Criteria

Before moving to Phase 2:
1. All Priority 1 tests passing
2. All Priority 2 tests passing
3. At least basic Priority 3 tests
4. Code coverage > 90% (use `mix test --cover`)
5. No known bugs without regression tests

## Estimated Test Count After Completion
- Current: 50 tests
- Priority 1: +15-20 tests
- Priority 2: +25-30 tests
- Priority 3: +10 tests
- **Target: ~100 tests**
