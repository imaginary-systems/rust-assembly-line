# OpenAPI Schema Designer

## When to Use
Run during planning when an ADR includes an API surface section. Designs the complete `utoipa` annotation strategy for every endpoint and DTO before implementation begins, so the schema is planned alongside the code rather than retrofitted afterward.

## Instructions

Read the ADR's API Surface, Entities & Data Models, and Error Strategy sections to produce a complete OpenAPI schema design.

### Step 1 — Inventory the API Surface

Extract every endpoint from the ADR:
- HTTP method + path
- Request body type (if any)
- Path and query parameters
- Response body types per status code
- Authentication requirement

For ES-sourced APIs, extract:
- Command endpoints (`POST .../commands/:type`)
- Query endpoints (`GET .../aggregate/:id`)
- Projection endpoints (`GET .../aggregate/:id/projection-name`)

### Step 2 — Design Request/Response DTOs

For each endpoint, design separate request and response DTOs — never expose domain types directly in the API:

**Request DTOs** (`CreateFooRequest`, `UpdateFooRequest`):
- Only include fields the caller provides — no server-generated IDs, no timestamps
- Fields that are optional on update should be `Option<T>`
- Add `#[schema(example = "...")]` for every field that a Scalar user would type

**Response DTOs** (`FooResponse`, `FoosResponse`):
- Always wrap paginated lists: `{ items: Vec<T>, total: usize, page: u32, per_page: u32 }`
- Include `created_at` / `updated_at` as ISO 8601 strings
- UUIDs as strings with `format: "uuid"`
- Never include internal database sequence IDs

**Error DTO** (single shared type across all endpoints):
```rust
#[derive(Debug, Serialize, ToSchema)]
pub struct ErrorResponse {
    /// Machine-readable error code matching the DomainError variant name.
    #[schema(example = "USER_NOT_FOUND")]
    pub code: String,
    /// Human-readable message safe to display.
    #[schema(example = "User not found")]
    pub message: String,
    /// Optional structured detail (validation errors, etc.).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}
```

### Step 3 — Design `#[utoipa::path]` Annotations

For each endpoint, produce the full annotation:

```
utoipa::path(
  method,
  path,
  params,            // path params + query params
  request_body,
  responses,         // every realistic status code
  security,          // if auth required
  tag
)
```

**Status code coverage rules:**
- Every endpoint must document at least: success, 401 (if auth required), 422 (if request body)
- GET by ID must document 404
- POST creation must document 409 if uniqueness constraint exists
- Every error code must map to `ErrorResponse`

### Step 4 — Design the `ApiDoc` Struct

List every path and schema that must be registered in the top-level `#[derive(OpenApi)]` struct. Missing a path or schema from this struct means it disappears from the Scalar UI even if the annotation exists.

### Step 5 — Design Scalar Configuration

Recommend Scalar UI settings appropriate for the API:
- Theme choice
- Which authentication scheme to pre-configure in the UI
- Whether to show the sidebar (useful for many endpoints)
- Default code snippet language (suggest `rust` with `reqwest` or `shell` with `curl`)

### Step 6 — Design Client Generation Strategy

Recommend which client generation approach fits the project:

| Project Type | Recommended Strategy |
|-------------|---------------------|
| Full-stack Rust (Leptos/Dioxus server functions) | Skip progenitor — use shared types from `*-types` crate directly |
| Rust WASM client calling REST API | `progenitor` — typed Rust client, WASM-compatible via reqwest WASM feature |
| TypeScript frontend | `openapi-typescript` for types + `openapi-fetch` for the client |
| External consumers (public API) | Publish `openapi.json` in CI; let consumers choose tooling |
| CLI tool | `progenitor` — same typed client as WASM, used in binary |

### Output Format

```yaml
openapi_design:
  api_title: "Auth API"
  api_version: "1.0.0"
  base_path: "/api/v1"

  security_schemes:
    - name: bearer_auth
      type: http
      scheme: bearer
      bearer_format: JWT

  endpoints:
    - method: POST
      path: /users
      operation_id: create_user
      tag: users
      auth_required: true
      request_body:
        type: CreateUserRequest
        fields:
          - "email: String  // #[schema(example = 'alice@example.com', format = 'email')]"
          - "name: String   // #[schema(example = 'Alice Smith', min_length = 1)]"
      responses:
        - status: 201
          body: UserResponse
          description: "User created"
        - status: 409
          body: ErrorResponse
          description: "Email already registered"
          code_value: "USER_DUPLICATE"
        - status: 422
          body: ErrorResponse
          description: "Validation failure"
        - status: 401
          body: ErrorResponse
          description: "Unauthenticated"

    - method: GET
      path: /users/{id}
      operation_id: get_user
      tag: users
      auth_required: true
      path_params:
        - "id: Uuid  // #[schema(format = 'uuid')]"
      responses:
        - status: 200
          body: UserResponse
        - status: 404
          body: ErrorResponse
          code_value: "USER_NOT_FOUND"
        - status: 401
          body: ErrorResponse

  dto_designs:
    - name: CreateUserRequest
      kind: request
      fields:
        - "email: String"
        - "name: String"
      utoipa_derives: ["ToSchema", "Deserialize"]

    - name: UserResponse
      kind: response
      fields:
        - "id: Uuid"
        - "email: String"
        - "name: String"
        - "created_at: DateTime<Utc>"
      utoipa_derives: ["ToSchema", "Serialize"]

    - name: ErrorResponse
      kind: error
      shared: true
      fields:
        - "code: String"
        - "message: String"
        - "details: Option<serde_json::Value>"
      utoipa_derives: ["ToSchema", "Serialize"]

  api_doc_struct:
    paths:
      - "crate::handlers::users::create_user"
      - "crate::handlers::users::get_user"
      - "crate::handlers::users::list_users"
      - "crate::handlers::users::update_user"
      - "crate::handlers::users::delete_user"
    schemas:
      - "CreateUserRequest"
      - "UpdateUserRequest"
      - "UserResponse"
      - "UsersResponse"
      - "ErrorResponse"

  scalar_config:
    theme: purple
    default_client: rust/reqwest
    authentication_scheme: bearer_auth
    show_sidebar: true
    search_hotkey: k

  client_strategy:
    approach: progenitor
    output_crate: auth-client
    wasm_compatible: true
    rationale: "Rust WASM frontend (Leptos) needs a typed async client; progenitor generates one from the spec with reqwest WASM feature enabled"

  cargo_additions:
    - crate: auth-api
      deps:
        - 'utoipa = { version = "4", features = ["axum_extras", "uuid", "chrono"] }'
        - 'utoipa-axum = "0.1"'
        - 'utoipa-scalar = { version = "0.1", features = ["axum"] }'
```

## Tools
- Read
- Grep

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:openapi-schema-designer",
  prompt="Design the OpenAPI schema for this ADR: <path>. Workspace: <path>"
)
```
