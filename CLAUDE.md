# Rust Assembly Line

A Rust-focused software assembly line that orchestrates multi-agent workflows to prepare Architecture Decision Records (ADRs), plan implementation stories, enforce code quality, and capture learnings — all tuned for Rust workspace projects.

## Commands

| Command | Description |
|---------|-------------|
| `/ral:adr` | Author and validate an Architecture Decision Record |
| `/ral:plan` | Transform an ADR into Linear issues with crate-layer dependencies |
| `/ral:work` | Pick the next unblocked story and implement it |
| `/ral:review` | Run multi-agent code review on a branch or PR |
| `/ral:compound` | Capture learnings and update project documentation |
| `/ral:scaffold` | Generate CRUD scaffold across Rust crate layers |
| `/ral:es-scaffold` | Generate an Event Sourcing scaffold with domain aggregate, fold→decide→evolve, and FCIS architecture |
| `/ral:openapi` | Validate annotations, serve Scalar UI, export spec, generate typed clients |
| `/ral:setup` | Install hooks and quality gates |

## Rust Quality Standards

All code produced by this assembly line MUST adhere to:

### Mandatory Rules
- **No `unwrap()` or `expect()` in non-test code** — use `?` operator or handle errors explicitly
- **No `clone()` overuse** — prefer borrows; every `.clone()` in a hot path is a bug
- **Typed errors** — use `thiserror` for library errors, `anyhow` for binary/app errors
- **Clippy clean** — `cargo clippy -- -D warnings` must pass with zero warnings
- **Formatted** — `cargo fmt --check` must pass; no unformatted code merged
- **No `unsafe` without justification** — every `unsafe` block must have a `// SAFETY:` comment
- **No blocking in async** — never call `std::thread::sleep` or blocking I/O inside `async fn`
- **No `std::sync::Mutex` in async** — use `tokio::sync::Mutex` or restructure to avoid
- **Trait-based DI** — dependencies injected via traits, not concrete types
- **100% test coverage** — verified with `cargo llvm-cov` or `cargo tarpaulin`

### Error Handling Pattern
```rust
// GOOD
use thiserror::Error;
#[derive(Debug, Error)]
pub enum DomainError {
    #[error("entity not found: {id}")]
    NotFound { id: Uuid },
    #[error("validation failed: {0}")]
    Validation(String),
}

// BAD
fn bad() -> Result<(), Box<dyn std::error::Error>> {
    let x = something().unwrap(); // FORBIDDEN
    Ok(())
}
```

### Async Pattern
```rust
// GOOD
pub async fn fetch(client: &impl HttpClient, id: Uuid) -> Result<Entity, DomainError> {
    client.get(id).await.map_err(DomainError::from)
}

// BAD
pub async fn bad_fetch(id: Uuid) -> Entity {
    std::thread::sleep(Duration::from_secs(1)); // FORBIDDEN: blocking in async
    SomeConcreteClient::new().get(id).await.unwrap() // FORBIDDEN: unwrap + concrete type
}
```

## Crate Layer System

Stories are tagged by the crate layer they belong to. Lower layers block higher layers for the same entity:

| Priority | Tag | Crate Convention | Description |
|----------|-----|-----------------|-------------|
| 1 | `crate:types` | `*-types` / `*-domain` | Shared types, error types, domain structs |
| 2 | `crate:schema` | `*-db` / `*-migrations` | Database migrations, SQL schemas |
| 3 | `crate:repo` | `*-repo` / `*-store` | Repository/persistence traits + implementations |
| 4 | `crate:service` | `*-service` / `*-core` | Business logic, orchestration, service traits |
| 5 | `crate:integration` | `*-client` / `*-gateway` | External service clients, API gateways |
| 6 | `crate:api` | `*-api` / `*-server` | HTTP handlers, gRPC services, router |
| 7 | `crate:cli` | `*-cli` | Command-line interface |
| 8 | `crate:worker` | `*-worker` / `*-job` | Background workers, scheduled jobs |

## ADR Structure

Every feature begins with an Architecture Decision Record. ADRs are numbered (`docs/adr/NNNN-title.md`), accumulate over time, and are never deleted — only superseded.

### Required Sections (13)

1. **Title** — Short imperative phrase (e.g., "Use sqlx for database access")
2. **Status** — `proposed` | `accepted` | `deprecated` | `superseded by ADR-NNNN`
3. **Context** — Forces, constraints, and the problem requiring a decision
4. **Decision** — The concrete choice made ("We will...")
5. **Entities & Data Models** — Rust structs, enums, trait definitions involved
6. **Concurrency Model** — Sync vs async, channels, shared state strategy
7. **Error Strategy** — Error type hierarchy and propagation rules
8. **API Surface** — Public trait interfaces and HTTP/gRPC endpoints
9. **Crate Impact** — Which crates are added/modified and dependency direction
10. **Test Strategy** — Unit, integration, doc tests, property tests
11. **Consequences** — Trade-offs: what becomes easier, harder, what risks are introduced
12. **Alternatives Considered** — Other approaches evaluated and why rejected
13. **Out of Scope** — Explicit non-goals (at least two)

### ADR Lifecycle

```
proposed → accepted → deprecated
                    ↘ superseded by ADR-NNNN
```

## Event Sourcing: Fold → Decide → Evolve

The `es-scaffold` command generates a domain aggregate following the **Functional Core / Imperative Shell (FCIS)** pattern with an explicit **Fold → Decide → Evolve** workflow. The boundary between core and shell is enforced at the Cargo crate level.

### The Workflow

```
past events ──► fold(events) ──────────────────► State
                                                    │
command ─────────────────────────────────────► decide(state, cmd)
                                                    │
                                       Ok(Vec<Event>) | Err(DomainError)

state + event ──► evolve(state, event) ──────────► State'
```

| Function | Type | Description |
|----------|------|-------------|
| `fold` | `&[Event] → State` | Reconstruct current state by replaying all past events through `evolve` |
| `decide` | `(&State, Command) → Result<Vec<Event>, Error>` | Pure business logic: given state + intent, return what happened or why not |
| `evolve` | `(State, &Event) → State` | Pure state transition: unconditionally apply one event to produce the next state |

### FCIS Crate Boundary

```
┌─────────────────────────────────────┐
│         FUNCTIONAL CORE             │  Zero I/O. Zero async. Pure functions.
│  <prefix>-types   (contracts)       │  Freely unit-testable with no infrastructure.
│  <prefix>-domain  (decide+evolve)   │  All business logic lives here.
└─────────────────────────────────────┘
             ↑ depended upon by ↑
┌─────────────────────────────────────┐
│         IMPERATIVE SHELL            │  I/O allowed. Async allowed.
│  <prefix>-store   (event store)     │  Connects the domain to the outside world.
│  <prefix>-service (cmd handler)     │  Orchestrates: load → fold → decide → append
│  <prefix>-api     (HTTP/gRPC)       │  Never contains business logic.
└─────────────────────────────────────┘
```

**Non-negotiable FCIS rules** (enforced by `es-invariant-reviewer`):
- `*-domain` and `*-types` `Cargo.toml` must never list `sqlx`, `tokio`, `axum`, or any I/O crate
- No `async fn` anywhere in `*-domain/src/`
- `decide()` and `evolve()` contain no logging, no I/O, no clock reads, no randomness
- `evolve()` handles every event variant exhaustively — no `unreachable!()`
- `fold()` delegates to `evolve()` — it never duplicates match logic

### ES Layer Tags

| Tag | Crate Suffix | Role |
|-----|-------------|------|
| `es:types` | `*-types` | Aggregate trait, commands, events, state, errors, envelopes |
| `es:domain` | `*-domain` | `decide` + `evolve` + `fold` — **functional core** |
| `es:store` | `*-store` | EventStore trait + append-only SQL implementation |
| `es:service` | `*-service` | CommandHandler — load→fold→decide→append orchestration |
| `es:projection` | (in `-service`) | Read model projections over the event stream |
| `es:api` | `*-api` | HTTP command + query endpoints |

### CRUD vs Event Sourcing

| | CRUD (`/ral:scaffold`) | Event Sourcing (`/ral:es-scaffold`) |
|--|------------------------|-------------------------------------|
| Persistence | Current state row | Append-only event stream |
| Business logic | Service layer (imperative) | `decide()` (pure function) |
| History | Optional audit log | Intrinsic — events ARE the record |
| Testing | Requires DB or mock | Pure unit tests via GWT harness |
| Complexity | Lower | Higher — use for complex domains |

## Agent Categories

## OpenAPI, Scalar UI, and WASM Frontends

### OpenAPI Toolchain

All HTTP API crates use `utoipa` for schema annotation. The toolchain is opinionated:

| Role | Crate | Used In |
|------|-------|---------|
| Schema derivation | `utoipa` (`#[derive(ToSchema)]`) | DTOs in `*-api` |
| Handler annotation | `utoipa-axum` (`#[utoipa::path]`) | Handlers in `*-api` |
| Spec assembly | `utoipa::OpenApi` (`ApiDoc` struct) | `*-api/src/openapi.rs` |
| Scalar UI | `utoipa-scalar` (served at `/scalar`) | `*-api/src/router.rs` |
| Rust client gen | `progenitor` (from `openapi.json`) | `*-client` crate |
| TS type gen | `openapi-typescript` | Hybrid JS frontends |

**Non-negotiable OpenAPI rules** (enforced by `openapi-compliance-reviewer`):
- Every routed `pub async fn` handler has `#[utoipa::path]`
- Every DTO used as `request_body` or `body` derives `ToSchema`
- Every DTO field has at least one `#[schema(example = ...)]` for Scalar playground usability
- `ApiDoc` lists all paths and all schemas — nothing is silently omitted
- Scalar mounted at `/scalar`; raw spec at `/openapi.json`
- ES command endpoints return `202 Accepted`, not `201 Created`

### Scalar UI

Scalar is the interactive API testing UI, served directly from the Axum process. It replaces Swagger UI with a modern interface that supports authentication, code snippet generation, and a full request playground.

```
Dev:        http://localhost:3000/scalar
Spec:       http://localhost:3000/openapi.json
CI export:  cargo run -p <prefix>-api --features export-spec -- export-spec > docs/openapi.json
Validate:   npx @scalar/cli validate docs/openapi.json
```

Scalar is gated in production (`cfg(debug_assertions)` or `SERVE_DOCS=true`). For public APIs, serve it unconditionally.

### WASM Frontend Recommendations

Three framework profiles, chosen by project context:

| Profile | Framework | When to choose |
|---------|-----------|---------------|
| Full-stack Rust + SSR | **Leptos** + `leptos_axum` | Axum backend, SEO needed, team is Rust-first; server functions share `*-types` directly — no REST client |
| Standalone WASM SPA | **Leptos** or **Dioxus** + `progenitor` | Single-page app consuming REST API; `progenitor` generates a WASM-compatible typed Rust client from `openapi.json` |
| Cross-platform | **Dioxus** | Same codebase targets web (WASM), desktop, and mobile via feature flags |

**Build toolchain:** `trunk` for Leptos/Yew; `dx` (dioxus-cli) for Dioxus.

**WASM optimisation** (always in release):
```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
```

**`wasm-ui-advisor` agent** produces a complete architecture recommendation — framework choice with rationale, component structure, client strategy, Trunk/dioxus-cli config, CORS requirements, and WASM size optimisation settings.

## Agent Categories

### Planning Agents (12)
Transform ADRs into structured implementation stories.

- `adr-structure-validator` — validates ADR completeness and structure
- `entity-extractor` — extracts Rust structs/enums/traits from ADR
- `flow-extractor` — extracts control flows, API endpoints, CLI commands
- `story-generator` — generates Linear-ready stories with crate-layer tags
- `dependency-linker` — creates blocks/blocked-by relationships
- `rust-architect` — designs crate boundaries and trait composition
- `es-aggregate-architect` — designs Event Sourcing aggregate vocabulary, FCIS layout, projections, and saga need
- `openapi-schema-designer` — designs `utoipa` annotation strategy, DTO shapes, Scalar config, and client generation plan for an ADR's API surface
- `wasm-ui-advisor` — recommends WASM framework (Leptos/Dioxus/Yew), component architecture, client strategy, build toolchain, and CORS config
- `crate-dependency-analyzer` — validates dependency direction and detects cycles
- `schema-ripple-analyzer` — maps impact of data model changes across crates
- `test-strategy-planner` — plans unit/integration/property/doc test coverage

### Plan Review Agents (4)
Validate plans before implementation begins.

- `rust-feasibility-reviewer` — catches anti-patterns before code is written
- `type-complexity-assessor` — flags overly complex generic/lifetime designs
- `workspace-impact-reviewer` — identifies all affected crates and semver impact
- `trait-design-planner` — validates trait interfaces for correctness and DI fitness

### Code Review Agents (14)
Specialized reviewers run in parallel on every PR.

- `ownership-borrow-reviewer` — lifetime correctness, unnecessary clones, borrow patterns
- `unsafe-code-reviewer` — safety invariants, SAFETY comments, soundness
- `async-tokio-reviewer` — blocking in async, proper spawning, cancellation safety
- `error-handling-reviewer` — no unwrap/expect, typed errors, propagation chains
- `clippy-compliance-reviewer` — clippy lint adherence, pedantic rules
- `type-strictness-reviewer` — no unnecessary type erasure, proper generics
- `security-sentinel` — OWASP, injection, secrets, auth
- `performance-oracle` — allocations, clones, O(n²), unnecessary locking
- `architecture-strategist` — crate layer boundaries, dependency direction
- `pattern-recognition-specialist` — anti-patterns, naming, idiomatic Rust
- `test-coverage-reviewer` — 100% coverage, proper test isolation
- `api-design-reviewer` — public API ergonomics, documentation, semver
- `es-invariant-reviewer` — FCIS boundary, decide/evolve purity, event schema safety, optimistic concurrency
- `openapi-compliance-reviewer` — `utoipa` annotation coverage, `ToSchema` on all DTOs, `ApiDoc` completeness, Scalar wiring, example fields

### Compound Agents (3)
Capture learnings after completing implementation.

- `rust-pattern-documenter` — reusable Rust patterns discovered
- `lifetime-solution-documenter` — lifetime and borrow checker solutions
- `crate-integration-documenter` — cross-crate integration patterns

## Structured Markers

Commands emit structured markers for orchestration:

```
[RAL:ADR:VALID] {"number": "0042", "sections": 13, "status": "accepted"}
[RAL:ADR:INVALID] {"missing": ["Consequences", "Alternatives Considered"]}
[RAL:PLAN:COMPLETE] {"stories": 12, "project": "RUST-42"}
[RAL:WORK:START] {"storyId": "RUST-56", "branch": "feat/RUST-56-add-auth", "crate": "auth-service"}
[RAL:WORK:PROGRESS] {"criterion": 2, "total": 6, "status": "complete"}
[RAL:WORK:COMPLETE] {"storyId": "RUST-56", "prUrl": "https://..."}
[RAL:REVIEW:COMPLETE] {"critical": 0, "warnings": 2, "fixed": 5}
[RAL:COMPOUND:COMPLETE] {"patterns": 2, "lifetimes": 1, "integrations": 0}
```
