# /ral:scaffold — Generate a CRUD Scaffold Across Rust Crate Layers

## Overview

Generates a complete CRUD scaffold for a named entity across all appropriate Rust crate layers: domain types, error types, repository trait, sqlx implementation, service layer, HTTP handlers, and tests.

## Usage

```
/ral:scaffold <EntityName>
/ral:scaffold <EntityName> --fields "id:Uuid,name:String,email:String,created_at:DateTime<Utc>"
/ral:scaffold <EntityName> --belongs-to <ParentEntity>
/ral:scaffold <EntityName> --skip api,cli
/ral:scaffold <EntityName> --crate-prefix auth
```

## Arguments

- `<EntityName>` — PascalCase entity name (e.g., `User`, `BlogPost`, `OrderItem`)
- `--fields "<spec>"` — Comma-separated field definitions: `name:Type`
- `--belongs-to <Parent>` — Add a foreign key reference to a parent entity
- `--skip <layers>` — Comma-separated crate layers to skip (e.g., `cli,worker`)
- `--crate-prefix <prefix>` — Prefix for generated crate names (e.g., `auth` → `auth-types`, `auth-db`)

## Generation Order

Generate in strict layer order (later layers depend on earlier):

1. `crate:types` — domain types and error enum
2. `crate:schema` — SQL migration
3. `crate:repo` — repository trait (in types) + sqlx implementation
4. `crate:service` — service trait (in types) + implementation
5. `crate:api` — HTTP handlers and router registration
6. `crate:cli` — CLI subcommands (if not skipped)

## Generated Files

### `crate:types` — Domain Types (`<prefix>-types/src/<entity_snake>.rs`)

```rust
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// A <EntityName> in the system.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[non_exhaustive]
pub struct <EntityName> {
    pub id: Uuid,
    // ... generated fields
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Input for creating a new <EntityName>.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct New<EntityName> {
    // ... required fields (no id, no timestamps)
}

/// Input for updating an existing <EntityName>.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Update<EntityName> {
    // ... all optional fields (Option<T>)
}

/// Errors that can occur when working with <EntityName>.
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum <EntityName>Error {
    #[error("<entity> not found: {id}")]
    NotFound { id: Uuid },
    #[error("<entity> already exists")]
    Duplicate,
    #[error("validation failed: {message}")]
    Validation { message: String },
    #[error("database error")]
    Database(#[from] sqlx::Error),
}
```

### `crate:types` — Repository Trait

```rust
/// Data access interface for <EntityName>.
#[async_trait::async_trait]
pub trait <EntityName>Repository: Send + Sync + 'static {
    async fn find_by_id(&self, id: Uuid) -> Result<Option<<EntityName>>, <EntityName>Error>;
    async fn find_all(&self, page: u32, per_page: u32) -> Result<Vec<<EntityName>>, <EntityName>Error>;
    async fn insert(&self, input: New<EntityName>) -> Result<<EntityName>, <EntityName>Error>;
    async fn update(&self, id: Uuid, input: Update<EntityName>) -> Result<<EntityName>, <EntityName>Error>;
    async fn delete(&self, id: Uuid) -> Result<(), <EntityName>Error>;
}
```

### `crate:schema` — Migration (`<prefix>-db/migrations/<timestamp>_create_<entity_snake>s.sql`)

```sql
-- migrate:up
CREATE TABLE <entity_snake>s (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- ... generated columns
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- migrate:down
DROP TABLE <entity_snake>s;
```

### `crate:repo` — sqlx Implementation (`<prefix>-db/src/<entity_snake>_repo.rs`)

Concrete `SqlxEntityRepository` implementing the trait with `sqlx::query_as!` macros.

### `crate:service` — Service Trait + Impl

Service trait in types, implementation in `<prefix>-service`.

### `crate:api` — HTTP Handlers (`<prefix>-api/src/handlers/<entity_snake>.rs`)

```
GET    /<entity_snake>s          → list (paginated)
GET    /<entity_snake>s/:id      → get by id
POST   /<entity_snake>s          → create
PATCH  /<entity_snake>s/:id      → update
DELETE /<entity_snake>s/:id      → delete
```

### Tests

Each crate gets a corresponding test module:
- `crate:types` — unit tests for validation, Display impls
- `crate:repo` — integration tests with `sqlx::test`
- `crate:service` — unit tests with `mockall` mock repository
- `crate:api` — integration tests with `axum-test`

## Output

```
Scaffold generated for: User

Files created (14):
  auth-types/src/user.rs              — domain types + error enum
  auth-types/src/traits/user_repo.rs  — UserRepository trait
  auth-types/src/traits/user_svc.rs   — UserService trait
  auth-db/migrations/20240101_create_users.sql
  auth-db/src/user_repo.rs            — sqlx implementation
  auth-db/src/tests/user_repo_test.rs
  auth-service/src/user_service.rs    — service implementation
  auth-service/src/tests/user_svc_test.rs
  auth-api/src/handlers/users.rs      — HTTP handlers
  auth-api/src/tests/users_test.rs
  auth-cli/src/commands/users.rs      — CLI subcommands

Cargo.toml updated (2):
  auth-types/Cargo.toml — added: thiserror, async-trait, uuid, chrono, serde
  auth-db/Cargo.toml    — added: sqlx (with postgres feature)

Next: run `cargo check --workspace` to verify the scaffold compiles
```
