# Rust Assembly Line

A Rust-focused software assembly line that orchestrates multi-agent workflows to prepare Architecture Decision Records (ADRs), plan implementation stories, enforce code quality, and capture learnings — all tuned for Rust workspace projects.

## Overview

Rust Assembly Line is an opinionated development framework that enforces best practices through automated agents and structured workflows. It guides teams from architectural decisions through implementation to code review, with specialized support for both CRUD and Event Sourcing patterns.

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/adversarial-systems/rust-assembly-line.git

# Run setup to install hooks and quality gates
/ral:setup
```

### Basic Workflow

1. **Design** — Author an ADR with `/ral:adr`
2. **Plan** — Transform ADR into Linear issues with `/ral:plan`
3. **Implement** — Pick and implement stories with `/ral:work`
4. **Review** — Run multi-agent code review with `/ral:review`
5. **Learn** — Capture patterns with `/ral:compound`

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

All code produced by this assembly line adheres to strict quality standards:

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

## Architecture

### Crate Layer System

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

### ADR Structure

Every feature begins with an Architecture Decision Record. ADRs are numbered (`docs/adr/NNNN-title.md`), accumulate over time, and are never deleted — only superseded.

#### Required Sections (13)

1. **Title** — Short imperative phrase
2. **Status** — `proposed` | `accepted` | `deprecated` | `superseded by ADR-NNNN`
3. **Context** — Forces, constraints, and the problem requiring a decision
4. **Decision** — The concrete choice made
5. **Entities & Data Models** — Rust structs, enums, trait definitions involved
6. **Concurrency Model** — Sync vs async, channels, shared state strategy
7. **Error Strategy** — Error type hierarchy and propagation rules
8. **API Surface** — Public trait interfaces and HTTP/gRPC endpoints
9. **Crate Impact** — Which crates are added/modified and dependency direction
10. **Test Strategy** — Unit, integration, doc tests, property tests
11. **Consequences** — Trade-offs: what becomes easier, harder, what risks are introduced
12. **Alternatives Considered** — Other approaches evaluated and why rejected
13. **Out of Scope** — Explicit non-goals (at least two)

## Event Sourcing: Fold → Decide → Evolve

The `/ral:es-scaffold` command generates a domain aggregate following the **Functional Core / Imperative Shell (FCIS)** pattern with an explicit **Fold → Decide → Evolve** workflow.

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

### CRUD vs Event Sourcing

| | CRUD (`/ral:scaffold`) | Event Sourcing (`/ral:es-scaffold`) |
|--|------------------------|-------------------------------------|
| Persistence | Current state row | Append-only event stream |
| Business logic | Service layer (imperative) | `decide()` (pure function) |
| History | Optional audit log | Intrinsic — events ARE the record |
| Testing | Requires DB or mock | Pure unit tests via GWT harness |
| Complexity | Lower | Higher — use for complex domains |

## OpenAPI, Scalar UI, and WASM Frontends

### OpenAPI Toolchain

All HTTP API crates use `utoipa` for schema annotation:

| Role | Crate | Used In |
|------|-------|---------|
| Schema derivation | `utoipa` (`#[derive(ToSchema)]`) | DTOs in `*-api` |
| Handler annotation | `utoipa-axum` (`#[utoipa::path]`) | Handlers in `*-api` |
| Spec assembly | `utoipa::OpenApi` (`ApiDoc` struct) | `*-api/src/openapi.rs` |
| Scalar UI | `utoipa-scalar` (served at `/scalar`) | `*-api/src/router.rs` |
| Rust client gen | `progenitor` (from `openapi.json`) | `*-client` crate |
| TS type gen | `openapi-typescript` | Hybrid JS frontends |

**Non-negotiable OpenAPI rules:**
- Every routed `pub async fn` handler has `#[utoipa::path]`
- Every DTO used as `request_body` or `body` derives `ToSchema`
- Every DTO field has at least one `#[schema(example = ...)]` for Scalar playground usability
- `ApiDoc` lists all paths and all schemas — nothing is silently omitted
- Scalar mounted at `/scalar`; raw spec at `/openapi.json`
- ES command endpoints return `202 Accepted`, not `201 Created`

### Scalar UI

```
Dev:        http://localhost:3000/scalar
Spec:       http://localhost:3000/openapi.json
CI export:  cargo run -p <prefix>-api --features export-spec -- export-spec > docs/openapi.json
Validate:   npx @scalar/cli validate docs/openapi.json
```

### WASM Frontend Recommendations

| Profile | Framework | When to choose |
|---------|-----------|---------------|
| Full-stack Rust + SSR | **Leptos** + `leptos_axum` | Axum backend, SEO needed, team is Rust-first |
| Standalone WASM SPA | **Leptos** or **Dioxus** + `progenitor` | Single-page app consuming REST API |
| Cross-platform | **Dioxus** | Same codebase targets web (WASM), desktop, and mobile |

## Multi-Agent System

### Planning Agents (12)

Transform ADRs into structured implementation stories:

- `adr-structure-validator` — validates ADR completeness and structure
- `entity-extractor` — extracts Rust structs/enums/traits from ADR
- `flow-extractor` — extracts control flows, API endpoints, CLI commands
- `story-generator` — generates Linear-ready stories with crate-layer tags
- `dependency-linker` — creates blocks/blocked-by relationships
- `rust-architect` — designs crate boundaries and trait composition
- `es-aggregate-architect` — designs Event Sourcing aggregate vocabulary, FCIS layout, projections
- `openapi-schema-designer` — designs `utoipa` annotation strategy, DTO shapes, Scalar config
- `wasm-ui-advisor` — recommends WASM framework, component architecture, client strategy
- `crate-dependency-analyzer` — validates dependency direction and detects cycles
- `schema-ripple-analyzer` — maps impact of data model changes across crates
- `test-strategy-planner` — plans unit/integration/property/doc test coverage

### Plan Review Agents (4)

Validate plans before implementation begins:

- `rust-feasibility-reviewer` — catches anti-patterns before code is written
- `type-complexity-assessor` — flags overly complex generic/lifetime designs
- `workspace-impact-reviewer` — identifies all affected crates and semver impact
- `trait-design-planner` — validates trait interfaces for correctness and DI fitness

### Code Review Agents (14)

Specialized reviewers run in parallel on every PR:

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
- `es-invariant-reviewer` — FCIS boundary, decide/evolve purity, event schema safety
- `openapi-compliance-reviewer` — `utoipa` annotation coverage, `ToSchema` completeness

### Compound Agents (3)

Capture learnings after completing implementation:

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

## Project Structure

```
rust-assembly-line/
├── agents/
│   ├── planning/          # 12 planning agents
│   ├── plan-review/       # 4 plan review agents
│   ├── code-review/       # 14 code review agents
│   └── compound/          # 3 learning capture agents
├── commands/              # 9 workflow commands
├── skills/                # Reusable skills (git-worktree, etc.)
├── CLAUDE.md             # Full system documentation
└── LICENSE               # MIT License
```

## License

MIT License - Copyright (c) 2026 adversarial.systems

See [LICENSE](LICENSE) for full details.

## Documentation

For complete documentation, see [CLAUDE.md](CLAUDE.md).

## Contributing

This project enforces strict quality standards. All contributions must:

- Pass `cargo clippy -- -D warnings` with zero warnings
- Pass `cargo fmt --check`
- Achieve 100% test coverage
- Follow the error handling and async patterns documented above
- Be reviewed by the multi-agent code review system

---

**Built for teams that take Rust seriously.**
