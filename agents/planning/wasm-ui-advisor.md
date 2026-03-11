# WASM UI Advisor

## When to Use
Run during planning when a feature or ADR includes a frontend UI component, or when the team is choosing a WASM frontend strategy for the first time. Produces a framework recommendation, component architecture, client generation strategy, and build toolchain config.

## Instructions

Read the ADR's API Surface and the overall project structure to produce a tailored WASM UI recommendation.

---

## Step 1 — Assess Project Context

Ask these questions from the ADR and codebase:

1. **Is this a full-stack Rust project?** (backend is Axum, team is comfortable with Rust everywhere)
2. **Is the frontend a standalone SPA or embedded component?** (SPA = its own crate; embedded = WASM component in an existing HTML/JS app)
3. **Does the frontend need SSR / SEO?** (marketing pages, public content → SSR needed; internal dashboards → WASM-only is fine)
4. **Does the frontend need mobile or desktop?** (web only → Leptos/Yew; cross-platform → Dioxus)
5. **What is the team's Rust expertise?** (experts → Leptos fine-grained reactivity; React background → Yew or Dioxus; new to both → Dioxus for familiar DX)
6. **How often does the API change?** (frequently → `progenitor` with `build.rs` auto-regen; stable → manual client or shared types)

---

## Step 2 — Framework Selection

### Decision Matrix

| Criterion | Leptos | Dioxus | Yew |
|-----------|--------|--------|-----|
| Reactivity model | Fine-grained signals (SolidJS-like) | Virtual DOM (React-like) | Virtual DOM (React-like) |
| SSR support | ✅ First-class (`leptos_axum`) | ✅ (`dioxus-ssr`) | ⚠️ Partial |
| Cross-platform | Web only | ✅ Web, desktop, mobile, TUI | Web only |
| Full-stack integration | ✅ Server functions via `leptos_axum` | ✅ Server functions (0.6+) | ❌ Manual REST only |
| Axum integration | ✅ `leptos_axum::handle_server_fns` | ⚠️ Requires adapter | N/A |
| Ecosystem maturity | Growing (active, 2022+) | Growing (active, 2021+) | Mature (2019+) |
| Component ergonomics | RSX macros | RSX macros | html! macro |
| Compile times | Moderate | Moderate | Slow (VDOM overhead) |
| Community size | Medium | Large | Large |
| Best for | Full-stack Rust, SSR, reactivity | Cross-platform, familiar DX | React migrants, mature ecosystem |

### Recommendations by Profile

**Profile A — Full-stack Rust, Axum backend, needs SSR**
→ **Leptos** with `leptos_axum`
- Server functions share types from `*-types` crate — no REST client needed
- SSR + WASM hydration in one framework
- Example: dashboard, internal tool, content-heavy app

**Profile B — Standalone WASM SPA, REST API backend**
→ **Leptos** with `progenitor` client, OR **Dioxus** with `progenitor` client
- Generate typed Rust client from OpenAPI spec via `progenitor`
- Client crate compiled to WASM with `reqwest` WASM feature
- Example: admin panel, single-page app

**Profile C — Cross-platform (web + desktop + mobile)**
→ **Dioxus**
- Single codebase targets all platforms via feature flags
- Web via WASM, desktop via native webview, mobile via hybrid
- `dioxus-desktop` / `dioxus-mobile` / `dioxus-web`

**Profile D — Existing React/JS team adding Rust WASM component**
→ **`wasm-bindgen`** + **`web-sys`** (component approach)
- Embed a Rust WASM component into the existing JS app
- No full-framework overhead, minimal disruption
- Use `wasm-pack` to build an npm-compatible package

---

## Step 3 — Architecture Design

### Leptos Full-Stack Architecture (Profile A)

```
workspace/
  <prefix>-types/        — shared domain types (used by both server and client)
  <prefix>-api/          — Axum server + Leptos server functions
  <prefix>-web/          — Leptos frontend crate
    src/
      app.rs             — root component + router
      components/
        users/
          list.rs        — UserList component
          detail.rs      — UserDetail component
          create_form.rs — CreateUserForm component
      pages/
        home.rs
        users.rs
      state/             — reactive global state (signals, resources)
        user_store.rs
      server_fns/        — server functions (call server from WASM without REST)
        users.rs

Cargo.toml (workspace)
  [patch.crates-io]
  # Ensure WASM-compatible versions
```

**Leptos component pattern:**
```rust
// <prefix>-web/src/components/users/list.rs
use leptos::*;
use <prefix>_types::UserResponse;

#[component]
pub fn UserList() -> impl IntoView {
    // Resource: async data fetch via server function (no REST, no CORS issues)
    let users = create_resource(|| (), |_| async { fetch_users().await });

    view! {
        <Suspense fallback=|| view! { <p>"Loading..."</p> }>
            {move || users.get().map(|result| match result {
                Ok(list) => view! {
                    <ul>
                        <For each=move || list.clone()
                             key=|u| u.id
                             children=|user| view! { <UserListItem user=user /> }
                        />
                    </ul>
                }.into_view(),
                Err(e) => view! { <ErrorBanner message=e.to_string() /> }.into_view(),
            })}
        </Suspense>
    }
}

// Server function — runs on server, called from WASM
#[server(FetchUsers, "/api")]
pub async fn fetch_users() -> Result<Vec<UserResponse>, ServerFnError> {
    use axum::extract::State;
    let svc = use_context::<Arc<dyn UserService>>()
        .ok_or(ServerFnError::new("missing service"))?;
    svc.list(Default::default()).await.map_err(ServerFnError::from)
}
```

### Leptos/Dioxus REST Architecture (Profile B)

```
workspace/
  <prefix>-types/        — shared domain types
  <prefix>-api/          — Axum server + OpenAPI + Scalar
  <prefix>-client/       — progenitor-generated typed REST client (WASM-compatible)
  <prefix>-web/          — Leptos or Dioxus frontend
    src/
      api/
        client.rs        — wraps generated client, adds auth token injection
      components/
      pages/
      state/

build.rs in <prefix>-client:
  progenitor regenerates from docs/openapi.json on every build
```

**progenitor client in WASM:**
```toml
# <prefix>-client/Cargo.toml
[dependencies]
progenitor-client = "0.7"

[target.'cfg(target_arch = "wasm32")'.dependencies]
reqwest = { version = "0.12", features = ["json"] }  # WASM-compatible

[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
reqwest = { version = "0.12", features = ["json", "rustls-tls"] }
```

```rust
// <prefix>-web/src/api/client.rs
use <prefix>_client::Client;

pub fn build_client(base_url: &str, token: Option<String>) -> Client {
    let mut headers = reqwest::header::HeaderMap::new();
    if let Some(t) = token {
        headers.insert(
            reqwest::header::AUTHORIZATION,
            format!("Bearer {t}").parse().unwrap(),
        );
    }
    let http = reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .expect("failed to build reqwest client");
    Client::new_with_client(base_url, http)
}
```

### Dioxus Cross-Platform Architecture (Profile C)

```
<prefix>-app/
  src/
    main.rs              — platform entry points via cfg
    app.rs               — root component
    components/
    pages/
    hooks/               — custom use_* hooks
    api/                 — REST client (progenitor or manual)

Cargo.toml:
  [features]
  web     = ["dioxus/web"]
  desktop = ["dioxus/desktop"]
  mobile  = ["dioxus/mobile"]

Build targets:
  dx serve --platform web
  dx build --platform desktop
  dx build --platform ios
```

---

## Step 4 — Build Toolchain Config

### Trunk (Leptos / Yew)

```toml
# Trunk.toml
[build]
target = "index.html"
dist = "dist"
public_url = "/"

[serve]
address = "127.0.0.1"
port = 3001
open = false
proxy_backend = "http://127.0.0.1:3000"   # proxy API requests to Axum
proxy_rewrite = "/api"

[watch]
ignore = ["dist", "target"]
```

```html
<!-- index.html -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8"/>
  <title><App Name></title>
  <link data-trunk rel="rust" data-wasm-opt="z"/>
</head>
<body></body>
</html>
```

### Dioxus CLI

```toml
# Dioxus.toml
[application]
name = "<prefix>-app"
default_platform = "web"

[web.app]
title = "<App Title>"

[web.proxy]
backend = "http://127.0.0.1:3000"

[web.watcher]
watch_path = ["src", "../<prefix>-types/src"]

[web.resource]
dev.style = []
```

### WASM Optimisation

Always set in production builds:
```toml
# Cargo.toml (workspace root or web crate)
[profile.release]
opt-level = "z"       # optimize for size
lto = true
codegen-units = 1

[profile.release.package."*"]
opt-level = "z"
```

Use `wasm-opt` (via Trunk's `data-wasm-opt="z"`) for an additional 20–40% size reduction.

---

## Step 5 — CORS Configuration

If the WASM frontend is on a different origin than the API (common in dev), configure CORS on the Axum server:

```rust
use tower_http::cors::{CorsLayer, Any};

let cors = CorsLayer::new()
    .allow_origin([
        "http://localhost:3001".parse().unwrap(),  // Trunk dev server
        "https://app.example.com".parse().unwrap(), // Production
    ])
    .allow_methods([Method::GET, Method::POST, Method::PATCH, Method::DELETE])
    .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION]);

let app = router.layer(cors);
```

With `leptos_axum` server functions, CORS is not needed because the frontend is served by the same Axum process.

---

## Output Format

```yaml
wasm_ui_recommendation:
  profile: A  # full-stack Rust, SSR, Axum backend
  framework: leptos
  version: "0.6"
  rationale: >
    Project is full-stack Rust with Axum backend and requires SSR for SEO.
    leptos_axum provides tight server-function integration that eliminates
    the need for a separate REST client and avoids CORS entirely in production.

  architecture:
    frontend_crate: auth-web
    shared_types_crate: auth-types  # used by both server functions and components
    client_strategy: server_functions  # no progenitor needed
    ssr: true
    hydration: true

  new_crates:
    - name: auth-web
      path: crates/auth-web
      cargo_deps:
        - 'leptos = { version = "0.6", features = ["ssr", "csr"] }'
        - 'leptos_axum = { version = "0.6", optional = true }'
        - 'leptos_meta = "0.6"'
        - 'leptos_router = "0.6"'
        - 'auth-types = { path = "../auth-types" }'

  build_toolchain: trunk
  trunk_config: trunk.toml  # proxy to :3000, port :3001

  cors_required: false  # leptos_axum serves frontend from same process

  component_structure:
    pages: [UsersPage, UserDetailPage, CreateUserPage]
    components: [UserList, UserListItem, UserDetail, CreateUserForm, ErrorBanner]
    server_fns: [fetch_users, fetch_user, create_user, update_user, delete_user]

  wasm_optimisation:
    release_opt_level: z
    lto: true
    wasm_opt: z

  openapi_integration:
    scalar_accessible_at: http://localhost:3000/scalar
    spec_at: http://localhost:3000/openapi.json
    notes: >
      Scalar serves as the primary API testing tool during development.
      Since the frontend uses server functions rather than REST, Scalar is
      primarily for external integrations and CLI client testing.

  alternative_considered:
    framework: dioxus
    rejected_because: >
      Cross-platform not required. leptos_axum integration is tighter for SSR
      use case and server functions reduce API surface complexity.
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:wasm-ui-advisor",
  prompt="Recommend a WASM UI architecture for this ADR and Axum API. Workspace: <path>"
)
```
