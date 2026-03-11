# Entity Extractor

## When to Use
Run this agent after ADR validation passes. It extracts all Rust types — structs, enums, traits, type aliases — from the ADR and produces a structured manifest for the story generator.

## Instructions

Parse the ADR and extract every type that will be implemented:

### Extraction Rules

**Structs**
- Extract field names, types, visibility (`pub`, `pub(crate)`, private)
- Note derive macros: `Debug`, `Clone`, `Serialize`, `Deserialize`, `sqlx::FromRow`, etc.
- Note if they wrap database rows, request/response DTOs, or domain objects
- Identify which crate layer they belong to (`crate:types`, `crate:repo`, etc.)

**Enums**
- Extract all variants with their associated data types
- Identify if they are error enums (`thiserror`), domain enums, or state machines
- Note `#[non_exhaustive]` usage

**Traits**
- Extract method signatures with full lifetimes and generics
- Note if they are meant for DI (dependency injection via `Arc<dyn Trait>`)
- Note if they are `async` (using `async_trait` or AFIT)
- Note if they have `Send + Sync` bounds

**Type Aliases**
- Extract `type Foo = ...` definitions

**Constants and Statics**
- Extract `const` and `static` declarations that define domain values

### Classification

For each extracted type, classify it:
- **Domain** — core business objects
- **Repository** — persistence traits and DB row types
- **Service** — business logic traits and orchestration types
- **API** — request/response DTOs, route types
- **Error** — error enums
- **Config** — configuration structs

### Output Format

```yaml
entities:
  - name: User
    kind: struct
    classification: domain
    crate_layer: crate:types
    fields:
      - name: id
        type: "Uuid"
        visibility: pub
      - name: email
        type: "String"
        visibility: pub
    derives: ["Debug", "Clone", "Serialize", "Deserialize"]
    notes: "Core user domain object"

  - name: UserRepository
    kind: trait
    classification: repository
    crate_layer: crate:repo
    methods:
      - signature: "async fn find_by_id(&self, id: Uuid) -> Result<Option<User>, RepoError>"
        is_async: true
    notes: "DI trait, impl in crate:repo, consumed in crate:service"

  - name: UserError
    kind: enum
    classification: error
    crate_layer: crate:types
    variants:
      - name: NotFound
        fields: ["id: Uuid"]
      - name: Duplicate
        fields: ["email: String"]
    derives: ["Debug", "thiserror::Error"]
```

## Tools
- Read
- Grep

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:entity-extractor",
  prompt="Extract all Rust entities from this ADR: <path>"
)
```
