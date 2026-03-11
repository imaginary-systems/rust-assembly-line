# /ral:es-scaffold — Event Sourcing Scaffold

## Overview

Generates a complete Event Sourcing implementation for a domain aggregate using a **Functional Core / Imperative Shell** architecture with an explicit **Fold → Decide → Evolve** workflow.

The scaffold enforces the FCIS boundary at the crate level: the `domain` crate is purely functional (no I/O, no async, no side effects), while the `store`, `service`, and `api` crates form the imperative shell that connects the domain to infrastructure.

## The Fold → Decide → Evolve Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     FUNCTIONAL CORE                              │
│                   (<prefix>-domain crate)                        │
│                                                                  │
│  past events ──► fold(events) ──────────────► State             │
│                                                  │               │
│  command ────────────────────────────────► decide(state, cmd)   │
│                                                  │               │
│                                    Ok(Vec<Event>) or Err(Error)  │
│                                                  │               │
│  state + event ──► evolve(state, event) ─────► State'           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     IMPERATIVE SHELL                             │
│            (<prefix>-store, -service, -api crates)              │
│                                                                  │
│  1. load_events(aggregate_id)          ← event store (I/O)      │
│  2. A::fold(&events)                   ← functional core        │
│  3. A::decide(&state, command)         ← functional core        │
│  4. store.append(id, version, events)  ← event store (I/O)     │
│  5. publisher.publish(&envelopes)      ← event bus (I/O)        │
└─────────────────────────────────────────────────────────────────┘
```

**Rule**: The functional core calls nothing. The imperative shell calls everything.

## Usage

```
/ral:es-scaffold <AggregateName> [options]
```

## DSL Reference

### Minimal invocation
```
/ral:es-scaffold Order --crate-prefix order
```
Scaffolds with placeholder commands, events, and state that the author fills in.

### Full DSL
```
/ral:es-scaffold Order \
  --id "OrderId: Uuid" \
  --state "
    status: OrderStatus,
    items: Vec<LineItem>,
    customer_id: CustomerId,
    total: Decimal
  " \
  --enums "
    OrderStatus: Uninitialised | Placed | Shipped | Cancelled
  " \
  --commands "
    PlaceOrder { customer_id: CustomerId, items: Vec<LineItem> },
    CancelOrder { reason: String },
    ShipOrder   { tracking_number: String }
  " \
  --events "
    OrderPlaced    { customer_id: CustomerId, items: Vec<LineItem>, total: Decimal },
    OrderCancelled { reason: String },
    OrderShipped   { tracking_number: String }
  " \
  --projections "OrderSummary { id: OrderId, status: OrderStatus, total: Decimal }" \
  --crate-prefix order \
  --versioning optimistic \
  --snapshot 500
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--id` | `"Name: Type"` | `<Name>Id: Uuid` | ID newtype name and inner type |
| `--state` | field list | empty | Fields of the aggregate state struct |
| `--enums` | enum list | none | Supporting enum types (e.g., status enums) |
| `--commands` | variant list | `Create<Name>, Update<Name>, Delete<Name>` | Command enum variants with fields |
| `--events` | variant list | `<Name>Created, <Name>Updated, <Name>Deleted` | Event enum variants with fields |
| `--projections` | name + fields | none | Read model projection structs |
| `--crate-prefix` | string | lowercase `<Name>` | Prefix for all generated crate names |
| `--versioning` | `optimistic\|timestamp` | `optimistic` | Concurrency strategy for event appends |
| `--snapshot` | integer | disabled | Generate snapshot support every N events |
| `--skip` | layer list | none | Skip: `domain`, `store`, `service`, `projection`, `api` |
| `--with-saga` | flag | false | Generate a saga/process manager crate |

## Generated Crate Layers

Generation follows strict order — each layer depends on all prior layers.

### Layer 1 — `es:types` → `<prefix>-types`

Shared contracts. No logic. No I/O. Consumed by both core and shell.

**Files generated:**
```
<prefix>-types/src/
  lib.rs                 — re-exports
  aggregate.rs           — Aggregate trait definition
  id.rs                  — <Name>Id newtype
  commands.rs            — <Name>Command enum
  events.rs              — <Name>Event enum
  state.rs               — <Name>State struct + supporting enums
  errors.rs              — <Name>Error (domain), StoreError, HandlerError
  envelope.rs            — EventEnvelope<E>, CommandEnvelope<C>
```

**Core generated code — the `Aggregate` trait:**
```rust
/// The central contract of the functional core.
/// All implementors MUST be pure functions: no I/O, no async, no side effects.
pub trait Aggregate: Sized + Default {
    type Id: Copy + Eq + Hash + fmt::Display + Into<Uuid> + From<Uuid>;
    type Command;
    type Event: Clone + Serialize + DeserializeOwned;
    type Error: std::error::Error + Send + Sync + 'static;

    /// DECIDE: given current state and a command, return the events to emit.
    /// Pure function. No I/O. No async. Contains ALL business logic.
    fn decide(state: &Self, command: Self::Command) -> Result<Vec<Self::Event>, Self::Error>;

    /// EVOLVE: given current state and one event, return the next state.
    /// Pure function. No I/O. No async. Must be total — never panic.
    fn evolve(state: Self, event: &Self::Event) -> Self;

    /// FOLD: reconstruct state by replaying a sequence of events from scratch.
    /// Default impl folds `evolve` over events starting from `Default::default()`.
    fn fold(events: &[Self::Event]) -> Self {
        events.iter().fold(Self::default(), |s, e| Self::evolve(s, e))
    }
}
```

**`EventEnvelope<E>` — the persistence wrapper:**
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEnvelope<E> {
    pub event_id: Uuid,
    pub aggregate_id: Uuid,
    pub aggregate_type: &'static str,
    /// Monotonically increasing per-aggregate sequence number.
    /// Used for optimistic concurrency — append only succeeds if
    /// expected_version matches the latest persisted sequence.
    pub sequence: u64,
    pub occurred_at: DateTime<Utc>,
    pub event_type: String,
    pub payload: E,
    pub metadata: serde_json::Value,
}
```

---

### Layer 2 — `es:domain` → `<prefix>-domain` ← **FUNCTIONAL CORE**

The pure heart of the aggregate. Zero infrastructure dependencies. Zero async.

**`Cargo.toml` dependencies:** only `<prefix>-types` and pure logic crates (`thiserror`, `rust_decimal`, etc.). **Absolutely no** `sqlx`, `tokio`, `axum`, `reqwest`, or any I/O crate.

**Files generated:**
```
<prefix>-domain/src/
  lib.rs
  aggregate.rs           — impl Aggregate for <Name>
  invariants.rs          — private guard functions (preconditions for decide)
  tests/
    mod.rs
    spec.rs              — GWT (Given-When-Then) test harness
    <name>_spec.rs       — aggregate behavior tests
```

**Generated aggregate implementation:**
```rust
// <prefix>-domain/src/aggregate.rs
use <prefix>_types::{Aggregate, <Name>Command, <Name>Error, <Name>Event, <Name>State};

pub struct <Name>;

impl Aggregate for <Name> {
    type Id      = <Name>Id;
    type Command = <Name>Command;
    type Event   = <Name>Event;
    type Error   = <Name>Error;

    fn decide(state: &<Name>State, command: <Name>Command)
        -> Result<Vec<<Name>Event>, <Name>Error>
    {
        match command {
            <Name>Command::PlaceOrder { customer_id, items } => {
                // Invariant: cannot place an already-placed order
                invariants::must_be_uninitialised(state)?;
                let total = invariants::calculate_total(&items)?;
                Ok(vec![<Name>Event::OrderPlaced { customer_id, items, total }])
            }
            <Name>Command::CancelOrder { reason } => {
                invariants::must_be_cancellable(state)?;
                Ok(vec![<Name>Event::OrderCancelled { reason }])
            }
            <Name>Command::ShipOrder { tracking_number } => {
                invariants::must_be_placed(state)?;
                Ok(vec![<Name>Event::OrderShipped { tracking_number }])
            }
        }
    }

    fn evolve(mut state: <Name>State, event: &<Name>Event) -> <Name>State {
        match event {
            <Name>Event::OrderPlaced { customer_id, items, total } => {
                state.status      = OrderStatus::Placed;
                state.customer_id = *customer_id;
                state.items       = items.clone();
                state.total       = *total;
                state
            }
            <Name>Event::OrderCancelled { .. } => {
                state.status = OrderStatus::Cancelled;
                state
            }
            <Name>Event::OrderShipped { tracking_number } => {
                state.tracking_number = Some(tracking_number.clone());
                state.status          = OrderStatus::Shipped;
                state
            }
        }
    }
}
```

**Generated GWT test harness (`tests/spec.rs`):**
```rust
/// Zero-infrastructure aggregate test harness.
/// No mocks. No database. No async. Just pure functions.
pub struct Spec<A: Aggregate> { given: Vec<A::Event> }

impl<A: Aggregate> Spec<A> {
    pub fn given(events: impl IntoIterator<Item = A::Event>) -> Self {
        Self { given: events.into_iter().collect() }
    }
    pub fn given_no_prior_events() -> Self { Self { given: vec![] } }

    pub fn when(self, command: A::Command) -> Outcome<A> {
        let state = A::fold(&self.given);
        Outcome { result: A::decide(&state, command) }
    }
}

pub struct Outcome<A: Aggregate> { result: Result<Vec<A::Event>, A::Error> }

impl<A: Aggregate> Outcome<A>
where A::Event: PartialEq + fmt::Debug, A::Error: fmt::Debug
{
    pub fn then_events(self, expected: impl IntoIterator<Item = A::Event>) {
        assert_eq!(self.result.unwrap(), expected.into_iter().collect::<Vec<_>>());
    }
    pub fn then_error(self, f: impl Fn(A::Error)) {
        f(self.result.unwrap_err());
    }
    pub fn then_no_events(self) {
        assert_eq!(self.result.unwrap(), vec![]);
    }
}
```

**Example tests generated (`tests/<name>_spec.rs`):**
```rust
use super::spec::Spec;
use <prefix>_domain::<Name>;
use <prefix>_types::*;

#[test]
fn placing_an_order_emits_order_placed() {
    Spec::<Name>::given_no_prior_events()
        .when(<Name>Command::PlaceOrder {
            customer_id: CustomerId::new(),
            items: vec![LineItem::fixture()],
        })
        .then_events([<Name>Event::OrderPlaced {
            customer_id: /* same */,
            items: /* same */,
            total: Decimal::from(100),
        }]);
}

#[test]
fn cannot_place_an_already_placed_order() {
    Spec::<Name>::given([<Name>Event::OrderPlaced { /* ... */ }])
        .when(<Name>Command::PlaceOrder { /* ... */ })
        .then_error(|e| assert!(matches!(e, <Name>Error::AlreadyPlaced)));
}

#[test]
fn shipping_requires_a_placed_order() {
    Spec::<Name>::given_no_prior_events()
        .when(<Name>Command::ShipOrder { tracking_number: "TRK123".into() })
        .then_error(|e| assert!(matches!(e, <Name>Error::NotPlaced)));
}
```

---

### Layer 3 — `es:store` → `<prefix>-store` ← **IMPERATIVE SHELL**

Append-only event persistence. Never mutates. Enforces optimistic concurrency.

**Files generated:**
```
<prefix>-store/src/
  lib.rs
  trait.rs               — EventStore<E> trait
  postgres.rs            — PostgresEventStore: EventStore<<Name>Event>
  publisher.rs           — EventPublisher<E> trait + no-op impl
  error.rs               — StoreError
  migrations/
    0001_create_<name>_events.sql
  tests/
    store_integration.rs — sqlx::test integration tests
```

**`EventStore` trait:**
```rust
#[async_trait::async_trait]
pub trait EventStore<E: Serialize + DeserializeOwned>: Send + Sync {
    /// Load all events for an aggregate ordered by sequence number.
    async fn load(&self, id: Uuid) -> Result<Vec<EventEnvelope<E>>, StoreError>;

    /// Load events starting from a sequence number (after snapshot).
    async fn load_from(&self, id: Uuid, after_seq: u64)
        -> Result<Vec<EventEnvelope<E>>, StoreError>;

    /// Append events, enforcing optimistic concurrency.
    /// Pass None for expected_version when creating a new aggregate stream.
    /// Returns StoreError::Conflict if actual latest sequence != expected_version.
    async fn append(
        &self,
        id: Uuid,
        expected_version: Option<u64>,
        events: Vec<E>,
    ) -> Result<Vec<EventEnvelope<E>>, StoreError>;
}
```

**Migration generated (`0001_create_<name>_events.sql`):**
```sql
-- migrate:up
CREATE TABLE <name>_events (
    event_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id   UUID        NOT NULL,
    aggregate_type TEXT        NOT NULL DEFAULT '<Name>',
    sequence       BIGINT      NOT NULL,
    event_type     TEXT        NOT NULL,
    payload        JSONB       NOT NULL,
    metadata       JSONB       NOT NULL DEFAULT '{}',
    occurred_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optimistic concurrency: no two events on the same aggregate
    -- can share a sequence number
    CONSTRAINT <name>_events_aggregate_sequence_unique
        UNIQUE (aggregate_id, sequence)
);

CREATE INDEX <name>_events_aggregate_id_seq_idx
    ON <name>_events (aggregate_id, sequence ASC);

-- migrate:down
DROP TABLE <name>_events;
```

---

### Layer 4 — `es:service` → `<prefix>-service` ← **IMPERATIVE SHELL**

Orchestrates the full load → fold → decide → append → publish cycle.

**Files generated:**
```
<prefix>-service/src/
  lib.rs
  handler.rs             — CommandHandler<A, S, P>
  error.rs               — HandlerError<DomainError>
  projections/
    mod.rs
    <projection_name>.rs — one file per --projections entry
```

**`CommandHandler` generated:**
```rust
pub struct CommandHandler<A, S, P>
where
    A: Aggregate,
    S: EventStore<A::Event>,
    P: EventPublisher<A::Event>,
{
    store:     Arc<S>,
    publisher: Arc<P>,
    _aggregate: PhantomData<A>,
}

impl<A, S, P> CommandHandler<A, S, P>
where
    A: Aggregate,
    A::Event: Serialize + DeserializeOwned + Send + Sync + 'static,
    S: EventStore<A::Event>,
    P: EventPublisher<A::Event>,
{
    pub async fn handle(
        &self,
        aggregate_id: A::Id,
        command: A::Command,
    ) -> Result<Vec<EventEnvelope<A::Event>>, HandlerError<A::Error>> {
        // ── IMPERATIVE: load from store ────────────────────────────────
        let envelopes = self.store
            .load(aggregate_id.into()).await
            .map_err(HandlerError::Store)?;

        let expected_version = envelopes.last().map(|e| e.sequence);
        let past_events: Vec<_> = envelopes.into_iter().map(|e| e.payload).collect();

        // ── FUNCTIONAL CORE: fold → decide ─────────────────────────────
        let state      = A::fold(&past_events);
        let new_events = A::decide(&state, command).map_err(HandlerError::Domain)?;

        if new_events.is_empty() {
            return Ok(vec![]);
        }

        // ── IMPERATIVE: append to store ────────────────────────────────
        let persisted = self.store
            .append(aggregate_id.into(), expected_version, new_events).await
            .map_err(HandlerError::Store)?;

        // ── IMPERATIVE: publish (fire-and-forget, non-fatal) ───────────
        if let Err(e) = self.publisher.publish(&persisted).await {
            tracing::warn!(error = %e, "event publish failed — events persisted");
        }

        Ok(persisted)
    }
}
```

**Projection trait and generated read model:**
```rust
/// A projection folds domain events into a read model.
/// Pure function — same guarantees as Aggregate::evolve.
pub trait Projection: Default {
    type Event;
    type ReadModel;

    fn apply(self, event: &Self::Event) -> Self;

    fn project(events: &[Self::Event]) -> Self::ReadModel
    where Self: Into<Self::ReadModel>
    {
        events.iter().fold(Self::default(), |p, e| p.apply(e)).into()
    }
}
```

---

### Layer 5 — `es:api` → `<prefix>-api` ← **IMPERATIVE SHELL**

HTTP interface: command endpoints (write side) and query endpoints (read side via projections).

**Files generated:**
```
<prefix>-api/src/
  handlers/
    commands.rs          — POST /aggregates/:id/commands
    queries.rs           — GET  /aggregates/:id (fold on demand or from projection)
  router.rs
  dto/
    requests.rs          — per-command request DTOs
    responses.rs         — EventEnvelope response DTO, projection response DTO
```

**Generated route structure:**
```
POST   /<name>s/:id/commands/place     → PlaceOrder command
POST   /<name>s/:id/commands/cancel    → CancelOrder command
POST   /<name>s/:id/commands/ship      → ShipOrder command
GET    /<name>s/:id                    → current state (fold on demand)
GET    /<name>s/:id/events             → raw event stream
GET    /<name>s/:id/<projection-name>  → projection read model
```

---

### Layer 6 — `es:snapshot` → `<prefix>-snapshots` *(only with `--snapshot N`)*

Periodic state snapshots to bound event replay cost. Generated only if `--snapshot <N>` is provided.

```rust
pub struct Snapshot<S> {
    pub aggregate_id: Uuid,
    pub sequence: u64,        // sequence of the last event included in this snapshot
    pub state: S,
    pub taken_at: DateTime<Utc>,
}

#[async_trait::async_trait]
pub trait SnapshotStore<S: Serialize + DeserializeOwned>: Send + Sync {
    async fn load_latest(&self, id: Uuid) -> Result<Option<Snapshot<S>>, StoreError>;
    async fn save(&self, snapshot: Snapshot<S>) -> Result<(), StoreError>;
}
```

The `CommandHandler` is modified to check for a snapshot before loading the full event history.

---

### Layer 7 — `es:saga` → `<prefix>-saga` *(only with `--with-saga`)*

A saga (process manager) reacts to events from one or more aggregates and issues commands to others. Sagas are themselves event-sourced.

```rust
pub trait Saga: Sized + Default {
    type Event;     // events this saga listens to
    type Command;   // commands this saga can issue
    type Error: std::error::Error + Send + Sync + 'static;

    /// React to an incoming event: emit commands to dispatch.
    /// Pure function — no I/O.
    fn react(state: &Self, event: &Self::Event)
        -> Result<Vec<Self::Command>, Self::Error>;

    /// Evolve saga state based on the event.
    fn evolve(state: Self, event: &Self::Event) -> Self;
}
```

---

## Output

```
ES scaffold generated for: Order

Crates created (5):
  order-types/       [es:types]       Aggregate trait, commands, events, state, errors
  order-domain/      [es:domain]      Functional core: decide + evolve + fold (pure)
  order-store/       [es:store]       EventStore trait + Postgres impl + migration
  order-service/     [es:service]     CommandHandler: load→fold→decide→append→publish
  order-api/         [es:api]         HTTP command + query endpoints

Files created (31):
  order-types/src/{lib,aggregate,id,commands,events,state,errors,envelope}.rs
  order-domain/src/{lib,aggregate,invariants}.rs
  order-domain/src/tests/{mod,spec,order_spec}.rs
  order-store/src/{lib,trait,postgres,publisher,error}.rs
  order-store/migrations/0001_create_order_events.sql
  order-store/src/tests/store_integration.rs
  order-service/src/{lib,handler,error}.rs
  order-service/src/projections/{mod,order_summary}.rs
  order-api/src/{router,handlers/commands,handlers/queries}.rs
  order-api/src/dto/{requests,responses}.rs

FCIS boundary enforced:
  Functional core:  order-types, order-domain  (no I/O, no async runtime deps)
  Imperative shell: order-store, order-service, order-api

Next steps:
  1. cargo check --workspace        — verify scaffold compiles
  2. cargo test -p order-domain     — GWT tests should all pass (stubs pass trivially)
  3. Fill in decide() invariants in order-domain/src/invariants.rs
  4. Fill in evolve() state transitions in order-domain/src/aggregate.rs
  5. Add failing GWT tests first, then make them pass (TDD from the core out)
```

## FCIS Rules Enforced by the `es-invariant-reviewer` Agent

The `es-invariant-reviewer` code review agent (runs automatically in `/ral:review`) enforces:

1. `<prefix>-domain/Cargo.toml` contains **no** `sqlx`, `tokio`, `axum`, `reqwest`, or any I/O crate
2. No `async fn` anywhere in `<prefix>-domain/src/`
3. `decide()` contains no `println!`, `eprintln!`, logging macros, or file/network I/O
4. `evolve()` does not call external functions — only struct field mutations
5. `fold()` is not overridden unless there is a snapshot strategy, and if it is, the override must call `evolve` internally
6. The imperative shell never calls `Default::default()` on the aggregate state directly — only through `A::fold(&[])`

## Comparison: CRUD Scaffold vs ES Scaffold

| Concern | CRUD (`/ral:scaffold`) | Event Sourcing (`/ral:es-scaffold`) |
|---------|------------------------|-------------------------------------|
| State storage | Current state row | Append-only event stream |
| Write path | `UPDATE` / `INSERT` | `append_events` |
| Read path | `SELECT` current row | `fold(load_events())` or projection |
| Business logic location | Service layer (imperative) | `decide()` (pure function) |
| State recovery | Read DB | Replay events through `fold` |
| History | Audit log (optional) | Intrinsic — events ARE the source of truth |
| Testing | Requires DB mock or real DB | Pure unit tests via GWT harness |
| Complexity | Lower — good for CRUD | Higher — good for complex domains with rich history |
