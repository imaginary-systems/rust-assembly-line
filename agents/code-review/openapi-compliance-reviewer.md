# OpenAPI Compliance Reviewer

## When to Use
Run on every PR that touches `*-api` crates. Verifies that every public HTTP handler has a complete `#[utoipa::path]` annotation, every DTO has `#[derive(ToSchema)]`, the top-level `ApiDoc` struct is complete, and the Scalar UI is properly wired.

## Instructions

Review all changed files in `*-api` crates for OpenAPI annotation correctness and completeness.

---

## Part 1 — Handler Annotation Coverage

### CRITICAL: Public handler missing `#[utoipa::path]`

Every `pub async fn` registered as an Axum route MUST have `#[utoipa::path(…)]` immediately above it. A handler without this annotation is invisible in Scalar and the generated spec.

Detection strategy:
1. Find all route registrations in `router.rs`: `.route("/path", get(handler_fn).post(other_fn))`
2. For each handler function name found, verify `#[utoipa::path` appears in its source
3. Flag any handler that is routed but unannotated

```rust
// CRITICAL: routed but not annotated
pub async fn create_user(/* ... */) -> impl IntoResponse { ... }

// CORRECT
#[utoipa::path(
    post,
    path = "/users",
    request_body = CreateUserRequest,
    responses(
        (status = 201, description = "User created", body = UserResponse),
        (status = 409, description = "Duplicate email", body = ErrorResponse),
        (status = 422, description = "Validation error", body = ErrorResponse),
        (status = 401, description = "Unauthenticated", body = ErrorResponse),
    ),
    security(("bearer_auth" = [])),
    tag = "users"
)]
pub async fn create_user(/* ... */) -> impl IntoResponse { ... }
```

### ERROR: Annotation responses don't match actual handler behaviour

Compare the documented status codes against the actual response types returned by the handler body:

```rust
// ERROR: annotation claims 200 but handler returns 201 on success
#[utoipa::path(
    post, path = "/users",
    responses((status = 200, body = UserResponse))  // wrong status code
)]
pub async fn create_user(/* ... */) -> impl IntoResponse {
    // ...
    (StatusCode::CREATED, Json(user_response))  // 201, not 200
}
```

**Rules:**
- `POST` creation → 201 (not 200)
- `DELETE` with no body → 204 (not 200)
- `GET` not found → 404 documented
- Any handler that can return `ServiceError::NotFound` → 404 must be in responses
- Any handler that can return `ServiceError::Duplicate` → 409 must be in responses
- Any handler with `Json(body)` extractor → 422 must be in responses

### ERROR: Missing `security` on authenticated endpoints

If the router applies an auth middleware layer, every handler under that layer must have a `security(…)` annotation:

```rust
// ERROR: auth middleware applied but no security annotation
#[utoipa::path(
    get, path = "/users/{id}",
    responses((status = 200, body = UserResponse))
    // missing: security(("bearer_auth" = []))
)]
pub async fn get_user(/* ... */) -> impl IntoResponse { ... }
```

### WARNING: Missing `operation_id`

Without an explicit `operation_id`, utoipa generates one from the function name. Generated IDs are often ugly (`create_user_handler`). Prefer explicit:

```rust
#[utoipa::path(
    post, path = "/users",
    operation_id = "createUser",   // camelCase for OpenAPI convention
    // ...
)]
```

---

## Part 2 — DTO Schema Coverage

### CRITICAL: DTO missing `#[derive(ToSchema)]`

Every struct or enum used as a `request_body` or `body` in any `#[utoipa::path]` response MUST derive `ToSchema`. Without it the spec will fail to compile or produce a broken `$ref`.

```rust
// CRITICAL: used as request_body but missing ToSchema
#[derive(Debug, Deserialize)]  // missing ToSchema
pub struct CreateUserRequest { ... }

// CORRECT
#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateUserRequest { ... }
```

Detection: for each type named in any `#[utoipa::path]` annotation, check its `#[derive(...)]` list.

### ERROR: No `#[schema(example = ...)]` on fields

DTOs without examples produce empty fields in the Scalar playground, making it useless for testing. Every field that a user would fill in must have an example.

```rust
// ERROR: no examples — Scalar playground is blank
pub struct CreateUserRequest {
    pub email: String,
    pub name: String,
}

// CORRECT
pub struct CreateUserRequest {
    #[schema(example = "alice@example.com", format = "email")]
    pub email: String,
    #[schema(example = "Alice Smith", min_length = 1, max_length = 100)]
    pub name: String,
}
```

Minimum requirement: at least one `#[schema(example = ...)]` per struct. Flag structs with zero examples.

### ERROR: Domain type used directly as response body

Domain types from `*-types` crates should not be used as API response bodies directly. They often contain internal fields, have no `#[schema]` attributes, and create tight coupling between the API contract and the domain model.

```rust
// ERROR: domain type as response body
#[utoipa::path(get, path = "/users/{id}",
    responses((status = 200, body = User))   // User is from auth-types — should be UserResponse
)]
```

Flag any `body = T` where `T` is imported from a `*-types` crate rather than the local DTO module.

### WARNING: Nested type missing `ToSchema`

```rust
#[derive(ToSchema)]
pub struct UsersResponse {
    pub items: Vec<UserResponse>,  // UserResponse also needs ToSchema
    pub total: usize,
}
```

If `UserResponse` is missing `ToSchema`, the nested schema will be `{}` in the spec. Check all nested types transitively.

---

## Part 3 — `ApiDoc` Completeness

### CRITICAL: Handler registered in router but missing from `ApiDoc::paths`

```rust
// Router wires get_user, but ApiDoc doesn't list it
#[derive(OpenApi)]
#[openapi(
    paths(create_user, list_users),  // get_user missing!
    // ...
)]
pub struct ApiDoc;
```

Detection: compare the list of annotated handlers in source against the `paths(...)` list in `ApiDoc`.

### ERROR: DTO with `ToSchema` not listed in `ApiDoc::components(schemas(...))`

```rust
#[openapi(
    paths(...),
    components(schemas(
        CreateUserRequest,
        UserResponse,
        // ErrorResponse missing — will appear as {} inline
    ))
)]
```

Every type with `#[derive(ToSchema)]` must be listed in `components(schemas(...))`.

### WARNING: `ApiDoc` missing `info` fields

A spec without title, version, or description produces a poor Scalar UI header. At minimum, `title` and `version` must be set:

```rust
#[openapi(
    info(
        title = "My API",
        version = env!("CARGO_PKG_VERSION"),  // ties version to Cargo.toml
    )
)]
```

### WARNING: No `servers` defined

Without `servers`, Scalar defaults to the current window origin. For local dev this is fine, but for shared team use the production and staging URLs should be listed.

---

## Part 4 — Scalar UI Wiring

### ERROR: Scalar not mounted in router

The Scalar endpoint must be present in the router. Check `router.rs` for:

```rust
.merge(Scalar::with_url("/scalar", ApiDoc::openapi()))
.route("/openapi.json", get(|| async { Json(ApiDoc::openapi()) }))
```

If neither `.merge(Scalar::…)` nor any equivalent `/openapi.json` route is present, flag as ERROR.

### WARNING: Scalar always served in production

Scalar should be gated behind a build flag or env variable in production to avoid exposing the API schema publicly (unless intentional):

```rust
// Recommended pattern
if cfg!(debug_assertions) || std::env::var("SERVE_DOCS").is_ok() {
    router = openapi::with_scalar(router);
}
```

---

## Output Format

```yaml
openapi_compliance_review:
  files_reviewed:
    - path: crates/auth-api/src/handlers/users.rs
      violations:
        - line: 34
          severity: critical
          category: missing_annotation
          code: "pub async fn update_user("
          issue: "Handler is routed (router.rs:22 PATCH /users/:id) but has no #[utoipa::path]"
          fix: "Add #[utoipa::path(patch, path = \"/users/{id}\", ...)] above update_user"

        - line: 89
          severity: error
          category: wrong_status_code
          code: "(status = 200, body = UserResponse)"
          issue: "POST handler documents 200 but returns StatusCode::CREATED (201)"
          fix: "Change to (status = 201, description = \"User created\", body = UserResponse)"

    - path: crates/auth-api/src/dto/requests.rs
      violations:
        - line: 12
          severity: critical
          category: missing_to_schema
          code: "#[derive(Debug, Deserialize)]"
          issue: "UpdateUserRequest is used as request_body but is missing ToSchema"
          fix: "Add ToSchema to the derive list"

        - line: 12
          severity: error
          category: no_schema_examples
          code: "pub struct UpdateUserRequest {"
          issue: "No #[schema(example = ...)] on any field — Scalar playground will be blank"
          fix: "Add at least one example per field"

    - path: crates/auth-api/src/openapi.rs
      violations:
        - line: 18
          severity: critical
          category: api_doc_incomplete
          code: "paths(create_user, list_users, get_user, delete_user)"
          issue: "update_user handler is annotated but missing from ApiDoc paths list"
          fix: "Add update_user to the paths(...) list"

        - line: 26
          severity: error
          category: schema_not_registered
          code: "components(schemas(CreateUserRequest, UserResponse, ErrorResponse))"
          issue: "UpdateUserRequest derives ToSchema but is not listed in components schemas"
          fix: "Add UpdateUserRequest to schemas(...) list"

summary:
  files_reviewed: 5
  handlers_audited: 5
  handlers_annotated: 4
  handlers_missing_annotation: 1
  dtos_audited: 4
  dtos_with_schema: 3
  dtos_missing_schema: 1
  scalar_wired: true
  api_doc_complete: false
  critical: 3
  errors: 2
  warnings: 1
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:openapi-compliance-reviewer",
  prompt="Review OpenAPI annotation compliance in changed files. Workspace: <path>"
)
```
