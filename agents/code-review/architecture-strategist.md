# Architecture Strategist

## When to Use
Run on every PR. Validates that changed code respects crate layer boundaries, dependency direction, separation of concerns, and does not introduce architectural drift.

## Instructions

Review the changed files and their import statements against the crate layer architecture.

### Layer Boundary Violations

**Forbidden Import Patterns**
- `crate:types` importing from `crate:repo`, `crate:service`, or higher → CRITICAL
- `crate:service` importing concrete database types from `crate:repo` directly (should use traits) → ERROR
- `crate:service` importing `crate:api` types (HTTP request/response models) → CRITICAL
- `crate:repo` importing `crate:service` types → CRITICAL
- `crate:api` importing `crate:cli` types or vice versa → ERROR
- Any lower-layer crate depending on a higher-layer crate → CRITICAL

**Separation of Concerns**
- HTTP handler containing business logic → should call service layer
- Repository method containing business rules → should be in service layer
- Service method building HTTP responses → service must not know about HTTP
- Database query embedded in service method instead of repository → extract to repository
- CLI command containing business logic → should call service layer

**Domain Integrity**
- Domain types (in `crate:types`) contaminated with framework-specific types:
  - `axum::extract::Path` in a domain struct → CRITICAL
  - `sqlx::types::*` in a public domain type → ERROR (use From/Into conversions)
  - `serde_json::Value` in a domain struct → use typed structs
- Infrastructure concerns bleeding into domain logic:
  - `tracing::Span` stored in a domain struct
  - Database connection pool in a domain object

**Dependency Injection**
- Concrete types injected instead of trait objects:
  - `AuthService { repo: SqlxUserRepository }` → should be `AuthService<R: UserRepository>`
  - HTTP handler with `State(pool): State<PgPool>` instead of `State(svc): State<Arc<dyn UserService>>`
- Fat constructors: `new()` with 8+ parameters → use builder or config struct

### Output Format

```yaml
architecture_review:
  files_reviewed:
    - path: crates/auth-service/src/service.rs
      violations:
        - line: 3
          severity: critical
          code: "use auth_db::SqlxUserRepository;"
          issue: "auth-service importing concrete SqlxUserRepository from auth-db — violates DI principle"
          fix: "Import and use auth_types::UserRepository trait; inject via generic or Arc<dyn UserRepository>"

        - line: 89
          severity: error
          code: "let response = axum::Json(UserResponse::from(user));"
          issue: "Service layer constructing HTTP response type — service must not know about HTTP"
          fix: "Return User domain type from service; let the handler convert to UserResponse"

        - line: 145
          severity: error
          code: "let row: PgRow = sqlx::query(\"...\").fetch_one(&self.pool).await?;"
          issue: "Raw SQL query in service method — move to UserRepository trait implementation"
          fix: "Add UserRepository::find_by_criteria method, implement in auth-db"

    - path: crates/auth-types/src/models.rs
      violations:
        - line: 5
          severity: critical
          code: "use sqlx::FromRow;"
          issue: "Domain types crate importing sqlx — creates hard coupling to database library"
          fix: "Move sqlx::FromRow derive to auth-db crate; use a separate DB row type with From/Into conversion"

summary:
  files_reviewed: 4
  layer_violations: 2
  separation_violations: 2
  di_violations: 1
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:architecture-strategist",
  prompt="Review architecture of changed files. Workspace: <path>"
)
```
