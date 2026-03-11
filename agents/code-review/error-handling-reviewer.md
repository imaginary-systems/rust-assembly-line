# Error Handling Reviewer

## When to Use
Run on every PR. Enforces typed error handling, bans `unwrap`/`expect` in production code, validates error propagation, and ensures errors are informative.

## Instructions

Audit all error handling in changed non-test Rust files.

### CRITICAL Violations (block merge)

**Panicking in Production Code**
- `.unwrap()` in any non-test, non-`fn main` file → CRITICAL
- `.expect("...")` in any non-test, non-`fn main` file → CRITICAL
- `panic!(...)` in library code (crates that are not binary entry points) → CRITICAL
- `unreachable!()` in code paths that are theoretically reachable at runtime → CRITICAL
- `todo!()` or `unimplemented!()` in code that ships → CRITICAL

Detection: grep for these patterns, then check if they are inside `#[cfg(test)]` or `fn main()`. If not → CRITICAL.

**Type Erasure in Library Errors**
- `Box<dyn std::error::Error>` in a public function signature in a library crate → CRITICAL
- `anyhow::Error` in a public function signature in a library crate → CRITICAL
  (anyhow is for binaries/applications only)

### ERROR Violations

**Silent Error Swallowing**
- `let _ = fallible_operation();` without comment explaining why the error is safe to ignore
- `.ok()` on a `Result` without explanation
- `if let Ok(x) = fallible() { ... }` where the `Err` case is silently discarded

**Error Context Loss**
- Re-wrapping errors without `#[from]` or `#[source]` — losing the error chain
- Converting a rich error to a string with `.to_string()` and losing structured info
- Using `map_err(|_| SomeError)` discarding the original error — use `map_err(|e| SomeError::from(e))` or `#[from]`

**Missing Variants**
- `DomainError` enum that has no `NotFound` variant for entity lookups
- Error enums without `#[error("...")]` message on every variant

### WARNING Violations

- Using `String` as error type: `Result<T, String>` — define a proper error type
- `.unwrap_or_else(|e| { log::error!(...); default })` in a loop — consider propagating
- `eprintln!` for error output in a library — use `tracing::error!` or return the error
- Missing `#[non_exhaustive]` on error enums that might gain variants

### Required Error Pattern

Library crates must use:
```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ServiceError {
    #[error("entity not found: {id}")]
    NotFound { id: Uuid },
    #[error("invalid input: {message}")]
    Validation { message: String },
    #[error("database error")]
    Database(#[from] sqlx::Error),
    #[error("internal error")]
    Internal(#[source] Box<dyn std::error::Error + Send + Sync>),
}
```

Application/binary main functions may use:
```rust
use anyhow::{Context, Result};
fn main() -> Result<()> {
    do_thing().context("failed to do thing")?;
    Ok(())
}
```

### Output Format

```yaml
error_handling_review:
  files_reviewed:
    - path: crates/auth-service/src/service.rs
      violations:
        - line: 45
          severity: critical
          code: "let user = repo.find_by_id(id).await.unwrap();"
          issue: "unwrap() in production service code — will panic if user is not found"
          fix: "let user = repo.find_by_id(id).await?.ok_or(ServiceError::NotFound { id })?;"

        - line: 92
          severity: error
          code: "repo.delete(id).await.map_err(|_| ServiceError::DeleteFailed)?;"
          issue: "Original sqlx error discarded — loses diagnostic information"
          fix: "repo.delete(id).await.map_err(ServiceError::Database)?"

        - line: 156
          severity: warning
          code: "let _ = audit_log.record(event).await;"
          issue: "Audit log errors silently discarded — add a comment or log at warning level"
          fix: "if let Err(e) = audit_log.record(event).await { tracing::warn!(error = %e, \"audit log write failed\"); }"

summary:
  files_reviewed: 3
  critical: 1
  errors: 1
  warnings: 1
  unwrap_count: 1
  expect_count: 0
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:error-handling-reviewer",
  prompt="Review error handling in changed files. Workspace: <path>"
)
```
