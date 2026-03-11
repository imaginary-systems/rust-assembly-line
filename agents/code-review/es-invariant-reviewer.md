# ES Invariant Reviewer

## When to Use
Run on every PR that touches Event Sourcing crates (`*-domain`, `*-types`, `*-store`, `*-service`). Audits for violations of FCIS purity, decide/evolve/fold contract adherence, event schema safety, and optimistic concurrency correctness.

## Instructions

Review all changed files in ES crates. Apply the FCIS boundary rules and the fold→decide→evolve contract rules.

---

## Part 1 — FCIS Boundary Enforcement

The single most important invariant: **the functional core must be purely functional**.

### `*-domain` and `*-types` Crates — ZERO I/O allowed

**CRITICAL: I/O crates in functional core `Cargo.toml`**

Check `<prefix>-domain/Cargo.toml` and `<prefix>-types/Cargo.toml` for forbidden dependencies:

```toml
# FORBIDDEN in functional core Cargo.toml — any of these is CRITICAL
sqlx = ...
tokio = ...
axum = ...
actix-web = ...
reqwest = ...
hyper = ...
tonic = ...           # gRPC
rdkafka = ...         # Kafka
lapin = ...           # RabbitMQ
redis = ...
mongodb = ...
aws-sdk-* = ...
```

If any of the above appear in `[dependencies]` (not `[dev-dependencies]`), it is a CRITICAL violation. The entire FCIS contract is broken.

**CRITICAL: `async fn` in domain crate**

Scan `<prefix>-domain/src/**/*.rs` for `async fn`. There must be none.

```rust
// CRITICAL: async fn in the functional core
pub async fn decide(state: &Self, cmd: Self::Command) -> ... { }

// CORRECT: synchronous
pub fn decide(state: &Self, cmd: Self::Command) -> ... { }
```

**CRITICAL: I/O calls in domain crate**

Scan for any of the following in domain crate source:
- `std::fs::` calls
- `std::net::` calls
- `tokio::` calls
- `println!` / `eprintln!` (use `tracing::` only in shell)
- `tracing::info!` / `tracing::error!` etc. (logging belongs in the shell)
- `reqwest::` / `hyper::` calls
- Any `use sqlx` statement

**ERROR: Shell crate importing from wrong direction**

Check that no shell crate is depended upon by any core crate. Scan `[dependencies]` in `<prefix>-types/Cargo.toml` and `<prefix>-domain/Cargo.toml`:

```toml
# ERROR in order-types/Cargo.toml or order-domain/Cargo.toml:
order-store   = ...   # shell depending on core is fine; core depending on shell is WRONG
order-service = ...   # same
order-api     = ...   # same
```

---

## Part 2 — `decide()` Contract

**CRITICAL: Side effects in `decide()`**

`decide()` must be a pure function. Scan for:

```rust
// CRITICAL: writing to anything in decide()
fn decide(state: &Self, command: Self::Command) -> ... {
    self.store.save(...);              // FORBIDDEN
    tokio::spawn(...);                 // FORBIDDEN
    std::fs::write(...);              // FORBIDDEN
    tracing::info!("deciding...");    // FORBIDDEN (side effect)
    println!("{:?}", state);          // FORBIDDEN
}
```

**CRITICAL: Non-determinism in `decide()`**

```rust
fn decide(state: &Self, cmd: Self::Command) -> ... {
    if Utc::now() > some_deadline { ... }  // CRITICAL: clock in decide is non-deterministic
    // Pass timestamps in via the command instead
}
```

**ERROR: `decide()` returning events that contain mutable references or raw pointers**

All events must be owned, `Clone`, `Serialize`, `DeserializeOwned` — no references.

**ERROR: Swallowing commands silently**

```rust
// ERROR: a match arm that returns Ok(vec![]) without explanation is likely a bug
OrderCommand::CancelOrder { .. } => Ok(vec![]),   // missing invariant check?
```

Flag any match arm in `decide()` that returns `Ok(vec![])` with no accompanying comment or invariant guard.

**WARNING: `decide()` calling `evolve()` internally**

```rust
fn decide(state: &Self, cmd: Self::Command) -> ... {
    let next = Self::evolve(state.clone(), &some_event);   // WARNING
    // decide should only READ state, never advance it
}
```

Calling `evolve` inside `decide` is a smell — it means the logic is trying to speculatively advance state to make a decision. This usually indicates a missing invariant field in state.

---

## Part 3 — `evolve()` Contract

**CRITICAL: I/O or side effects in `evolve()`**

`evolve()` must be total and pure. Same restrictions as `decide()`.

**CRITICAL: `evolve()` calling `decide()`**

```rust
fn evolve(state: Self, event: &Self::Event) -> Self {
    let cmds = Self::decide(&state, some_cmd);  // CRITICAL: circular dependency
    ...
}
```

**ERROR: `evolve()` that can panic**

```rust
fn evolve(state: Self, event: &Self::Event) -> Self {
    match event {
        OrderEvent::OrderPlaced { items, .. } => {
            state.items = items.clone();
            state.total = items.iter().map(|i| i.price).sum::<Decimal>(); // OK
            state
        }
        // Missing match arms will cause a compile warning, but unreachable!() is ERROR:
        _ => unreachable!("unexpected event"),  // ERROR: evolve must be total
    }
}
```

Every `evolve()` match must handle every variant. `unreachable!()` is forbidden — if an event can be stored, it can be replayed, and `evolve` must handle it.

**ERROR: `evolve()` performing validation**

`evolve()` applies events unconditionally — validation belongs in `decide()`.

```rust
fn evolve(state: Self, event: &Self::Event) -> Self {
    if state.status == OrderStatus::Shipped {
        // ERROR: evolve must not check invariants — it blindly applies events
        panic!("cannot ship an already-shipped order");
    }
    ...
}
```

**WARNING: `evolve()` discarding event data**

If an event carries a field that `evolve()` completely ignores, flag it:

```rust
OrderEvent::OrderPlaced { customer_id, items, total } => {
    state.status = OrderStatus::Placed;
    // WARNING: customer_id, items, total are never applied to state
    state
}
```

Either the field belongs in state (add it) or it doesn't belong in the event (remove it).

---

## Part 4 — `fold()` Contract

**ERROR: Overriding `fold()` without a snapshot strategy**

If `fold()` is overridden in an `impl Aggregate`, verify there is a corresponding snapshot crate and that the override correctly loads from a snapshot then replays subsequent events.

**ERROR: `fold()` that doesn't use `evolve()`**

```rust
fn fold(events: &[Self::Event]) -> Self {
    let mut state = Self::default();
    for event in events {
        // ERROR: manually replicating evolve logic instead of calling Self::evolve
        match event {
            OrderEvent::OrderPlaced { .. } => { state.status = ...; }
            ...
        }
    }
    state
}
```

`fold` must delegate to `evolve` — it must not contain its own event-matching logic.

---

## Part 5 — Event Schema Safety

**CRITICAL: Removing an event variant**

Removing any variant from an `<Name>Event` enum is a CRITICAL breaking change. Old events in the store will fail to deserialize. Flag any removed variant.

**CRITICAL: Removing a required field from an event variant**

Removing a non-optional field from an event variant breaks deserialization of old events.

**ERROR: Adding a required (non-`Option`) field to an existing event variant**

Adding a required field to an existing event variant breaks deserialization of old events stored before the change.

```rust
// Before:
OrderPlaced { customer_id: CustomerId, items: Vec<LineItem> }

// AFTER — ERROR: total is new and required, old events have no total field
OrderPlaced { customer_id: CustomerId, items: Vec<LineItem>, total: Decimal }

// CORRECT: add as Option with a default or use serde(default):
OrderPlaced { customer_id: CustomerId, items: Vec<LineItem>, #[serde(default)] total: Option<Decimal> }
```

**WARNING: Event enum without `#[non_exhaustive]`**

Event enums consumed by projections outside this workspace should be `#[non_exhaustive]` to allow new variants without breaking downstream match arms.

---

## Part 6 — Optimistic Concurrency

**ERROR: `append()` called without `expected_version` when updating an existing stream**

```rust
// ERROR: always passing None means you will silently create duplicate/conflicting events
store.append(id, None, new_events).await?;

// CORRECT: track the version from load()
let version = envelopes.last().map(|e| e.sequence);
store.append(id, version, new_events).await?;
```

**ERROR: `StoreError::Conflict` not handled in `CommandHandler`**

If `append` returns `Conflict`, the handler must retry (reload → fold → decide → append) or surface the conflict to the caller. Propagating `StoreError::Conflict` as a 500 Internal Server Error is wrong — it's a 409 Conflict.

---

## Output Format

```yaml
es_invariant_review:
  files_reviewed:
    - path: crates/order-domain/Cargo.toml
      violations:
        - line: 12
          severity: critical
          category: fcis_boundary
          code: 'tokio = { version = "1", features = ["full"] }'
          issue: "tokio in functional core Cargo.toml — order-domain must have zero async runtime deps"
          fix: "Remove tokio from [dependencies]; move any async work to order-service"

    - path: crates/order-domain/src/aggregate.rs
      violations:
        - line: 45
          severity: critical
          category: decide_purity
          code: "tracing::info!(\"deciding place order for {:?}\", state);"
          issue: "Logging side effect inside decide() — functional core must be silent"
          fix: "Remove tracing call; log in CommandHandler after decide() returns"

        - line: 112
          severity: error
          category: evolve_totality
          code: "_ => unreachable!(\"unexpected event variant\")"
          issue: "evolve() must handle every event variant — unreachable!() will panic on event replay"
          fix: "Add explicit match arm for every OrderEvent variant, even if the arm is a no-op"

    - path: crates/order-types/src/events.rs
      violations:
        - line: 18
          severity: error
          category: event_schema_safety
          code: "OrderPlaced { customer_id: CustomerId, items: Vec<LineItem>, total: Decimal }"
          issue: "total field added without serde(default) — breaks deserialization of old stored events"
          fix: "Add #[serde(default)] to total, or make it Option<Decimal>"

    - path: crates/order-service/src/handler.rs
      violations:
        - line: 67
          severity: error
          category: optimistic_concurrency
          code: "self.store.append(id, None, new_events).await?"
          issue: "expected_version is always None — concurrent writes will not be detected"
          fix: "Capture version from load() result: let version = envelopes.last().map(|e| e.sequence)"

summary:
  files_reviewed: 6
  critical: 2
  errors: 2
  warnings: 0
  fcis_violations: 2
  decide_violations: 1
  evolve_violations: 1
  event_schema_violations: 1
  concurrency_violations: 1
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:es-invariant-reviewer",
  prompt="Review Event Sourcing invariants in changed files. Workspace: <path>"
)
```
