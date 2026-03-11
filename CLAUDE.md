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

## Agent Categories

### Planning Agents (9)
Transform ADRs into structured implementation stories.

- `adr-structure-validator` — validates ADR completeness and structure
- `entity-extractor` — extracts Rust structs/enums/traits from ADR
- `flow-extractor` — extracts control flows, API endpoints, CLI commands
- `story-generator` — generates Linear-ready stories with crate-layer tags
- `dependency-linker` — creates blocks/blocked-by relationships
- `rust-architect` — designs crate boundaries and trait composition
- `crate-dependency-analyzer` — validates dependency direction and detects cycles
- `schema-ripple-analyzer` — maps impact of data model changes across crates
- `test-strategy-planner` — plans unit/integration/property/doc test coverage

### Plan Review Agents (4)
Validate plans before implementation begins.

- `rust-feasibility-reviewer` — catches anti-patterns before code is written
- `type-complexity-assessor` — flags overly complex generic/lifetime designs
- `workspace-impact-reviewer` — identifies all affected crates and semver impact
- `trait-design-planner` — validates trait interfaces for correctness and DI fitness

### Code Review Agents (12)
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
