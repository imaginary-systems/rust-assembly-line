# Test Strategy Planner

## When to Use
Run during planning to design the complete test strategy for a feature. Ensures tests are planned at every layer before implementation begins.

## Instructions

Given the ADR entities, flows, and crate structure, design a comprehensive test strategy. Output a test plan that covers every layer and identifies what tooling is needed.

### Test Categories

**Unit Tests** (`#[cfg(test)]` modules within the source file)
- Pure functions and methods with no I/O
- Domain logic, validation, error formatting
- State machine transitions
- Use `assert_eq!`, custom assertions, no mocking required

**Integration Tests** (`tests/` directory in each crate)
- Repository implementations against a real database (use `testcontainers-rs` or `sqlx::test`)
- Service layer with real repositories (use test database)
- HTTP handlers with a real `axum::Router` and `reqwest` or `axum-test`
- Never mock the database in integration tests

**Property Tests** (using `proptest` or `quickcheck`)
- Serialization round-trips (`serde` JSON/binary)
- Parser correctness
- Invariant preservation under random input
- Suitable for domain validation logic

**Doc Tests** (`///` code examples in public API docs)
- Every public function in `crate:types` must have a doc test
- Every public trait method must have a documented example
- Run with `cargo test --doc`

**Benchmark Tests** (`benches/` with `criterion`)
- Hot paths: serialization, database queries, frequently-called service methods
- Regression gates: set baselines and fail if > 10% slower

**Snapshot Tests** (`insta` crate)
- HTTP response bodies for API endpoints
- CLI output formatting
- Error message formatting

### Test Tooling Recommendations

| Need | Crate |
|------|-------|
| Database integration | `sqlx::test` macro or `testcontainers` |
| HTTP handler testing | `axum-test` or `reqwest` against test server |
| Property testing | `proptest` |
| Mocking traits | `mockall` (sparingly — prefer test doubles) |
| Snapshot testing | `insta` |
| Coverage reporting | `cargo llvm-cov` |
| Benchmarking | `criterion` |

### Coverage Requirement
- Minimum 80% line coverage per crate (enforced by CI)
- 100% coverage for `crate:types` (pure logic, no excuses)
- Integration tests count toward coverage when run with `cargo llvm-cov --all-features`

### Output Format

```yaml
test_strategy:
  crates:
    - crate: auth-types
      unit_tests:
        - "UserError Display impls for all variants"
        - "UserId newtype wraps Uuid correctly"
        - "User::new() validation rejects empty email"
      property_tests:
        - "User serialization round-trip (JSON)"
      doc_tests:
        - "All public functions have working examples"
      coverage_target: 100%

    - crate: auth-db
      integration_tests:
        - "UserRepository::insert creates row and returns User with generated id"
        - "UserRepository::find_by_id returns None for unknown id"
        - "UserRepository::insert returns UserError::Duplicate on email conflict"
      test_infrastructure:
        - "sqlx::test macro for per-test database isolation"
        - "Migrations run automatically via sqlx test infrastructure"
      coverage_target: 85%

    - crate: auth-api
      integration_tests:
        - "POST /users returns 201 with UserResponse on success"
        - "POST /users returns 409 on duplicate email"
        - "POST /users returns 422 on invalid request body"
        - "GET /users/:id returns 404 for unknown user"
      test_infrastructure:
        - "axum-test TestClient for handler tests"
        - "Test database via sqlx::test"
      snapshot_tests:
        - "UserResponse JSON shape"
        - "ErrorResponse JSON shape"
      coverage_target: 80%

tooling_additions:
  - crate: sqlx
    feature: "test"
    dev_dependency: true
  - crate: axum-test
    dev_dependency: true
  - crate: proptest
    dev_dependency: true

ci_commands:
  - "cargo llvm-cov --all-features --workspace --lcov --output-path coverage.lcov"
  - "cargo llvm-cov report --fail-under-lines 80"
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:test-strategy-planner",
  prompt="Design test strategy for this ADR and crate structure: <path>"
)
```
