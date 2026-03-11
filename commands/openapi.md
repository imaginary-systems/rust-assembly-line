# /ral:openapi — OpenAPI Schema Management

## Overview

Manages the OpenAPI schema lifecycle for Rust Axum services: validates annotation completeness, generates the JSON/YAML spec, serves the Scalar interactive testing UI, exports for CI/CD, and optionally generates typed client crates from the spec.

The canonical OpenAPI toolchain for this plugin is:

| Concern | Crate |
|---------|-------|
| Schema derivation | `utoipa` + `#[derive(ToSchema)]` |
| Handler annotation | `utoipa-axum` + `#[utoipa::path]` |
| Spec assembly | `utoipa::OpenApi` derive on `ApiDoc` struct |
| Scalar UI | `utoipa-scalar` served at `/scalar` |
| Rust client generation | `progenitor` (from the emitted JSON spec) |
| Type-only TS generation | `openapi-typescript` (for hybrid WASM+JS apps) |

## Usage

```
/ral:openapi validate                         # Check annotation coverage
/ral:openapi serve                            # Start Scalar UI locally
/ral:openapi export [--format json|yaml]      # Write spec to disk
/ral:openapi generate-client --lang rust      # Generate progenitor Rust client
/ral:openapi generate-client --lang ts        # Generate TypeScript types
/ral:openapi diff <base-ref>                  # Detect breaking changes vs git ref
```

## Sub-commands

### `validate`

Runs `rust-assembly-line:code-review:openapi-compliance-reviewer` against all `*-api` crates.
Fails if any public route handler is missing `#[utoipa::path]` annotation or any DTO is missing `#[derive(ToSchema)]`.

```
/ral:openapi validate
/ral:openapi validate --crate auth-api
```

Output:
```
OpenAPI validation: auth-api

  Handlers annotated:   12 / 12  ✓
  DTOs with ToSchema:   8  / 9   ✗
    MISSING: UpdateUserRequest (auth-api/src/dto/requests.rs:45)

  ApiDoc completeness:
    paths registered:   12 / 12  ✓
    schemas registered: 8  / 9   ✗
    Missing from ApiDoc: UpdateUserRequest

  Scalar wired:  ✓  (GET /scalar)
  Spec exportable: ✓

Result: INVALID — 1 missing ToSchema, 1 missing from ApiDoc
```

---

### `serve`

Compiles the `*-api` crate in test mode and starts a local server with Scalar UI. Useful for interactive API exploration during development.

```
/ral:openapi serve
/ral:openapi serve --crate auth-api --port 3001
```

Starts: `http://localhost:3000/scalar` (default)

The Scalar UI provides:
- Interactive request builder with authentication support
- Response examples auto-populated from `#[schema(example = ...)]` attributes
- Schema explorer with type definitions
- Collection-style saved requests
- Dark/light mode, keyboard navigation

---

### `export`

Emits the `openapi.json` or `openapi.yaml` spec to disk by running the binary in spec-export mode.

```
/ral:openapi export
/ral:openapi export --format yaml --output docs/openapi.yaml
```

Default output: `docs/openapi.json`

CI usage — add to `.github/workflows/ci.yml`:
```yaml
- name: Export OpenAPI spec
  run: cargo run -p <prefix>-api --features export-spec -- export-spec > docs/openapi.json

- name: Validate spec
  run: npx @scalar/cli validate docs/openapi.json
```

---

### `generate-client --lang rust`

Generates a `<prefix>-client` crate using [`progenitor`](https://github.com/oxidecomputer/progenitor) from the exported spec. The generated crate is a fully-typed async Rust client that mirrors every API endpoint.

```
/ral:openapi generate-client --lang rust --crate-name auth-client --out crates/auth-client
```

Generated `auth-client` includes:
- One async method per endpoint: `client.create_user(body).await?`
- Request/response types matching the server's schema
- `reqwest`-based transport with configurable base URL and auth headers
- Ready to use in WASM frontends (via `reqwest` WASM feature) or CLI tools

`build.rs` integration pattern for keeping client in sync:
```rust
// auth-client/build.rs
fn main() {
    // Re-run if the spec changes
    println!("cargo:rerun-if-changed=../../docs/openapi.json");
    progenitor::generate_api(
        "../../docs/openapi.json",
        "src/generated.rs",
        progenitor::GenerationSettings::default()
            .with_derive(["Clone", "Debug"])
    ).unwrap();
}
```

---

### `generate-client --lang ts`

Generates TypeScript types and a fetch-based client from the spec using `openapi-typescript`. Useful for hybrid Yew/Dioxus apps that use `wasm-bindgen` to call a JS fetch layer, or for any non-Rust frontend.

```
/ral:openapi generate-client --lang ts --out frontend/src/api/generated.ts
```

Generates:
```typescript
// frontend/src/api/generated.ts
export interface User { id: string; email: string; name: string; }
export interface CreateUserRequest { email: string; name: string; }
export interface UserResponse extends User {}
export interface ErrorResponse { error: string; code: string; }
// ... fetch wrapper per endpoint
```

---

### `diff <base-ref>`

Detects breaking changes in the OpenAPI spec compared to a git ref. Runs `oasdiff` or equivalent.

```
/ral:openapi diff main
/ral:openapi diff v1.2.3
```

Breaking changes detected:
- Removed endpoint
- Removed required request field
- Changed response field type
- Changed HTTP method
- Added required request field (non-breaking = optional fields only)

Non-breaking changes allowed:
- Added optional request field
- Added new endpoint
- Added new response field (if `additionalProperties: false` not set)

---

## Canonical utoipa Setup

When `--with-openapi` is passed to `scaffold` or `es-scaffold`, this exact pattern is generated.

### `Cargo.toml` additions (`*-api`)

```toml
[dependencies]
utoipa          = { version = "4", features = ["axum_extras", "uuid", "chrono", "decimal"] }
utoipa-axum     = { version = "0.1" }
utoipa-scalar   = { version = "0.1", features = ["axum"] }

[features]
# Enables a CLI flag to dump the spec to stdout and exit — used by /ral:openapi export
export-spec = []
```

### Top-level `ApiDoc` struct (`*-api/src/openapi.rs`)

```rust
use utoipa::OpenApi;
use utoipa_scalar::{Scalar, Servable};

#[derive(OpenApi)]
#[openapi(
    paths(
        crate::handlers::users::create_user,
        crate::handlers::users::get_user,
        crate::handlers::users::list_users,
        crate::handlers::users::update_user,
        crate::handlers::users::delete_user,
    ),
    components(schemas(
        User,
        CreateUserRequest,
        UpdateUserRequest,
        UserResponse,
        UsersResponse,
        ErrorResponse,
    )),
    tags(
        (name = "users", description = "User management endpoints")
    ),
    info(
        title = "Auth API",
        version = env!("CARGO_PKG_VERSION"),
        description = "Authentication and user management service",
        contact(name = "Team", email = "team@example.com"),
        license(name = "MIT"),
    ),
    servers(
        (url = "http://localhost:3000", description = "Local development"),
        (url = "https://api.example.com", description = "Production"),
    )
)]
pub struct ApiDoc;

/// Mounts the Scalar UI and spec endpoint onto the router.
pub fn with_scalar(router: axum::Router) -> axum::Router {
    router
        .merge(Scalar::with_url("/scalar", ApiDoc::openapi()))
        // Raw spec endpoint for tooling
        .route("/openapi.json", axum::routing::get(|| async {
            axum::Json(ApiDoc::openapi())
        }))
}
```

### Router wiring (`*-api/src/router.rs`)

```rust
pub fn build_router(state: AppState) -> axum::Router {
    let api_router = axum::Router::new()
        .route("/users",     axum::routing::post(create_user).get(list_users))
        .route("/users/:id", axum::routing::get(get_user).patch(update_user).delete(delete_user))
        .with_state(state);

    // Wrap with OpenAPI + Scalar in all non-production builds,
    // or always if SERVE_DOCS=true
    #[cfg(any(debug_assertions, feature = "export-spec"))]
    let api_router = openapi::with_scalar(api_router);

    api_router
}
```

### Handler annotation pattern

```rust
use utoipa::ToSchema;

/// Request body for creating a user.
#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateUserRequest {
    /// User's email address. Must be unique.
    #[schema(example = "alice@example.com", format = "email")]
    pub email: String,

    /// Display name shown in the UI.
    #[schema(example = "Alice Smith", min_length = 1, max_length = 100)]
    pub name: String,
}

/// A user resource.
#[derive(Debug, Serialize, ToSchema)]
pub struct UserResponse {
    #[schema(example = "550e8400-e29b-41d4-a716-446655440000", format = "uuid")]
    pub id: Uuid,
    #[schema(example = "alice@example.com")]
    pub email: String,
    #[schema(example = "Alice Smith")]
    pub name: String,
    pub created_at: DateTime<Utc>,
}

#[utoipa::path(
    post,
    path = "/users",
    request_body = CreateUserRequest,
    responses(
        (status = 201, description = "User created successfully",    body = UserResponse),
        (status = 409, description = "Email already exists",         body = ErrorResponse),
        (status = 422, description = "Request validation failed",    body = ErrorResponse),
        (status = 401, description = "Authentication required",      body = ErrorResponse),
    ),
    security(("bearer_auth" = [])),
    tag = "users"
)]
pub async fn create_user(
    State(svc): State<Arc<dyn UserService>>,
    Json(body): Json<CreateUserRequest>,
) -> impl IntoResponse {
    // ...
}
```

### Scalar UI Configuration

Scalar supports deep configuration via the `Scalar::with_url` builder:

```rust
use utoipa_scalar::{Scalar, Servable, ScalarConfig};

Scalar::with_url("/scalar", ApiDoc::openapi())
    .custom_html(include_str!("scalar-custom.html"))  // Optional: custom theme
```

Or as a standalone HTML page served separately (useful for WASM frontends):

```html
<!-- scalar.html -->
<!doctype html>
<html>
<head>
  <title>Auth API — Scalar</title>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body>
  <script id="api-reference" data-url="/openapi.json"></script>
  <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
</body>
</html>
```

Configure Scalar behaviour with `data-configuration`:
```html
<script
  id="api-reference"
  data-url="/openapi.json"
  data-configuration='{
    "theme": "purple",
    "layout": "modern",
    "defaultHttpClient": { "targetKey": "rust", "clientKey": "reqwest" },
    "authentication": {
      "preferredSecurityScheme": "bearer_auth",
      "http": { "bearer": { "token": "" } }
    },
    "showSidebar": true,
    "searchHotKey": "k"
  }'
></script>
```

Available Scalar themes: `default`, `alternate`, `moon`, `purple`, `solarized`, `bluePlanet`, `deepSpace`, `saturn`, `kepler`, `mars`, `none`
