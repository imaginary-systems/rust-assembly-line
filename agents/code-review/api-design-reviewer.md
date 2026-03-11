# API Design Reviewer

## When to Use
Run on PRs that add or change public API — HTTP endpoints, public trait/function signatures, CLI commands. Validates ergonomics, documentation, and semver compatibility.

## Instructions

Review the public-facing API changes in the PR for design quality, documentation completeness, and backward compatibility.

### Documentation Requirements

**Every `pub fn`, `pub struct`, `pub enum`, `pub trait` MUST have**:
- `///` doc comment explaining what it does (not just restating the name)
- `# Errors` section if it returns `Result<T, E>` — listing each error variant and when it occurs
- `# Panics` section if it can panic
- `# Examples` section with a working code example for `crate:types` public items

**Missing documentation is an ERROR on:**
- Any function in a library crate that could be used by downstream
- Any trait method

**Missing documentation is a WARNING on:**
- Private helper functions
- Test utility functions

### HTTP API Design

**RESTful Conventions**
- Resource names are plural nouns: `/users`, `/orders`, not `/user`, `/getOrder`
- HTTP verbs match semantics: GET reads, POST creates, PUT replaces, PATCH updates, DELETE removes
- Status codes are semantically correct:
  - 200 for successful GET/PUT/PATCH
  - 201 for successful POST (creation)
  - 204 for successful DELETE (no body)
  - 400 for client validation errors
  - 401 for unauthenticated
  - 403 for unauthorized (authenticated but not permitted)
  - 404 for not found
  - 409 for conflict (duplicate)
  - 422 for unprocessable entity (business rule violation)

**Request/Response Types**
- Request bodies should use dedicated types (not domain types directly)
- Response types should not expose internal database IDs as raw integers — use UUIDs
- Paginated responses must include `total`, `page`, `per_page`, `items` fields
- Error responses must be consistent: `{ "error": "...", "code": "...", "details": {} }`

### Trait API Design

- Every method has a doc comment
- `# Errors` documents the error type and when each variant is returned
- Default method implementations are documented to explain why the default is safe
- Sealed traits are documented with "This trait is sealed and cannot be implemented outside this crate"

### Semver Compatibility

Flag any change that is not backward-compatible:
- Removing a public function, type, or field
- Changing a function's parameter types or return type
- Adding a method to a trait without a default implementation
- Making a previously-optional feature required

### Output Format

```yaml
api_design_review:
  files_reviewed:
    - path: crates/auth-api/src/handlers.rs
      issues:
        - line: 34
          severity: error
          category: documentation
          code: "pub async fn create_user(State(svc): State<Arc<dyn UserService>>, ..."
          issue: "Public handler missing doc comment — API consumers need to know what this does"
          fix: "Add /// Creates a new user account. Returns 201 on success, 409 if email exists."

        - line: 112
          severity: error
          category: status_code
          code: "return Ok(StatusCode::OK);"
          issue: "POST handler returning 200 instead of 201 Created"
          fix: "return Ok((StatusCode::CREATED, Json(response)));"

        - line: 178
          severity: warning
          category: response_shape
          code: "Json(users)" // returning Vec<User> directly
          issue: "Returning bare array — not extendable; wrap in envelope for future pagination"
          fix: "Json(UsersResponse { items: users, total: users.len() })"

    - path: crates/auth-types/src/traits.rs
      issues:
        - line: 22
          severity: error
          category: documentation
          code: "async fn find_by_email(&self, email: &str) -> Result<Option<User>, UserError>;"
          issue: "Missing # Errors doc section — callers don't know which UserError variants to expect"
          fix: "Add: /// # Errors\n/// Returns [`UserError::Database`] on connection failure."

semver_issues:
  - change: "Removed UserRole::Guest variant from UserRole enum"
    impact: "BREAKING — all match arms in downstream crates must be updated"
    severity: critical

summary:
  files_reviewed: 3
  documentation_errors: 2
  design_errors: 1
  design_warnings: 1
  semver_breaking_changes: 1
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:api-design-reviewer",
  prompt="Review public API design in changed files. Workspace: <path>"
)
```
