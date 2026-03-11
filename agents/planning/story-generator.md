# Story Generator

## When to Use
Run after entity-extractor and flow-extractor have both completed. Takes their output and generates Linear-ready implementation stories, each tagged with the crate layer it belongs to.

## Instructions

Combine the entity manifest and flow manifest to generate one story per discrete unit of work. Each story must be small enough to implement in a single focused session (under half a day).

### Story Decomposition Rules

1. **One story per entity definition** — defining a struct/enum/trait is its own story at the appropriate crate layer.
2. **One story per repository implementation** — the trait definition is one story; the concrete `sqlx` implementation is a separate story.
3. **One story per service method** — each complex flow in crate:service is its own story.
4. **One story per HTTP handler** — each endpoint is its own story in crate:api.
5. **One story per CLI subcommand** — each CLI command is its own story in crate:cli.
6. **One story per worker** — each background worker is its own story in crate:worker.
7. **Migration stories** — every new table or column change is a separate story in crate:schema.
8. **Test stories** — integration test suites that span multiple crates get their own stories.

### Story Format

Each story must contain:
- **Title** — imperative verb + object (e.g., "Add `UserRepository` trait to `auth-types`")
- **Crate Layer Tag** — from the layer taxonomy
- **Acceptance Criteria** — 3–8 checkboxes, each testable and specific
- **Implementation Notes** — Rust-specific guidance, crate imports, trait bounds
- **Definition of Done** — `cargo clippy -- -D warnings` passes, `cargo fmt` passes, coverage >= 80% for this story's code

### Crate Layer Tags

| Tag | Use When |
|-----|----------|
| `crate:types` | Defining domain types, error enums, shared constants |
| `crate:schema` | Writing SQL migrations or modifying DB schema |
| `crate:repo` | Repository trait definitions or concrete implementations |
| `crate:service` | Business logic, service traits, orchestration |
| `crate:integration` | External HTTP/gRPC clients, gateway adapters |
| `crate:api` | HTTP/gRPC handlers, router wiring, middleware |
| `crate:cli` | CLI commands and argument parsing |
| `crate:worker` | Background workers, job processors |

### Output Format

```yaml
stories:
  - title: "Define UserError enum in auth-types"
    crate_layer: crate:types
    labels: ["crate:types", "error-handling"]
    acceptance_criteria:
      - "[ ] `UserError` enum defined with `NotFound { id: Uuid }`, `Duplicate { email: String }`, `Unauthorized` variants"
      - "[ ] Derives `Debug`, `thiserror::Error`; each variant has `#[error(...)]` message"
      - "[ ] Re-exported from crate root via `pub use`"
      - "[ ] Unit tests verify `Display` output for each variant"
    implementation_notes: >
      Place in `auth-types/src/errors.rs`. Add `thiserror` to `auth-types/Cargo.toml`.
      No async, no I/O. Pure type definition.
    definition_of_done: "cargo clippy -- -D warnings passes; cargo fmt passes; 100% coverage on Display impls"

  - title: "Define UserRepository trait in auth-types"
    crate_layer: crate:types
    labels: ["crate:types", "repository"]
    acceptance_criteria:
      - "[ ] `UserRepository` trait defined with `find_by_id`, `find_by_email`, `insert`, `update`, `delete` async methods"
      - "[ ] All methods return `Result<T, UserError>` or `Result<Option<T>, UserError>`"
      - "[ ] Trait is `Send + Sync + 'static` compatible"
      - "[ ] `async_trait` or AFIT used consistently"
      - "[ ] Trait documented with `///` doc comments"
    implementation_notes: >
      Use `#[async_trait::async_trait]` until AFIT stabilises in MSRV.
      Bounds: `&self` receiver for all query methods. `&mut self` not allowed.
    definition_of_done: "cargo clippy -- -D warnings passes; cargo doc builds without warnings"
```

## Tools
- Read

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:story-generator",
  prompt="Generate stories from these entity and flow manifests: <yaml>"
)
```
