# ES Aggregate Architect

## When to Use
Run during planning when a feature uses Event Sourcing. Designs the aggregate boundary, command/event vocabulary, state shape, invariants, and FCIS crate layout from an ADR. Use this instead of (or alongside) `rust-architect` for ES features.

## Instructions

Read the ADR and design the full Event Sourcing aggregate structure, enforcing the Functional Core / Imperative Shell separation at the crate boundary.

### Step 1 — Identify Aggregate Boundaries

An aggregate is a consistency boundary: all invariants it enforces must be checkable from state reconstructed by folding its own events. Use these rules to find the right boundary:

- **Too small**: if `decide()` needs to query another aggregate's state to enforce an invariant, the boundary is wrong — merge them or pass the needed data in the command
- **Too large**: if two clusters of commands never interact with each other's invariants, split into two aggregates
- **Reference by ID only**: aggregates reference each other by ID (`CustomerId`, `ProductId`), never by embedding the other aggregate's state
- **One stream per aggregate instance**: `order-stream-<uuid>` not `all-orders`

### Step 2 — Design the Vocabulary

**Commands** — intentions sent to the aggregate (imperative mood):
- Named for what the user/system wants to do: `PlaceOrder`, `CancelOrder`, not `OrderWasPlaced`
- Carry only the data needed to make the decision — no denormalized data the aggregate already has
- Commands can be rejected — that is not an error, it is a business rule

**Events** — facts that happened (past tense, immutable):
- Named for what occurred: `OrderPlaced`, `OrderCancelled`, not `PlaceOrder`
- Events are NEVER rejected — if it's in the event store, it happened
- Carry sufficient data to reconstruct state without querying other sources
- Once published, an event's schema is a public contract — design carefully

**Invariants** — what `decide()` enforces:
- List every business rule as a named invariant: "cannot cancel a shipped order"
- Each invariant becomes a private guard function in `invariants.rs`
- Document what state condition triggers each error variant

### Step 3 — Design State Shape

The state struct holds exactly what `decide()` needs to enforce invariants. Nothing more.

Rules:
- If a field is only needed for `evolve()` output (e.g., denormalized display name), it may not belong in state — put it in the event payload instead
- Avoid storing derived data that can be computed from other fields — keep state minimal
- Enum fields (e.g., `OrderStatus`) are preferred over boolean flags
- `Option<T>` fields indicate state that exists only after certain events

### Step 4 — Design the FCIS Crate Layout

Produce explicit crate specifications following the FCIS principle:

**Functional Core crates** (zero I/O dependencies):
- `<prefix>-types`: shared contracts (trait, enums, structs, errors)
- `<prefix>-domain`: aggregate implementation (`decide`, `evolve`, `fold`) + tests

**Imperative Shell crates** (I/O allowed):
- `<prefix>-store`: event persistence (`EventStore` trait + implementation)
- `<prefix>-service`: command handling (`CommandHandler`) + projections
- `<prefix>-api`: HTTP/gRPC endpoints

Forbidden cross-boundary imports:
- `<prefix>-domain` must NOT depend on `<prefix>-store`, `<prefix>-service`, or `<prefix>-api`
- `<prefix>-types` must NOT depend on `sqlx`, `tokio`, `axum`, or any runtime crate
- Shell crates may depend on core crates, never the reverse

### Step 5 — Design Projections

For each read model needed:
- Name the projection and its read model struct
- List the events it listens to
- Describe the fold logic (which fields change on which events)
- Specify the storage (in-memory, PostgreSQL table, Redis, etc.)

### Step 6 — Assess Snapshot Need

Snapshots are needed when:
- The event stream for a single aggregate instance could grow to 10,000+ events in normal operation
- Startup time is a concern (loading 10k events takes measurable time even with SQL)
- Recommend a snapshot interval N and the state type to serialize

If snapshots are not needed, explicitly state why.

### Step 7 — Assess Saga Need

A saga is needed when:
- A business process spans multiple aggregates
- A command on aggregate A must trigger a command on aggregate B
- Compensation (rollback-like behavior) is needed across aggregates

Design the saga vocabulary if applicable: the events it listens to, the commands it emits, and the compensation path.

### Output Format

```yaml
aggregate_design:
  name: Order
  id_type: "OrderId(Uuid)"
  aggregate_boundary_rationale: >
    Order is a single consistency unit: all cancellation/shipping rules
    are enforced against order state only. Customer and Product are
    referenced by ID only.

  commands:
    - name: PlaceOrder
      fields:
        - "customer_id: CustomerId"
        - "items: Vec<LineItem>"
      preconditions:
        - "state.status == OrderStatus::Uninitialised"
        - "items is non-empty"
      emits: [OrderPlaced]

    - name: CancelOrder
      fields:
        - "reason: String"
      preconditions:
        - "state.status in [Placed]  (not Shipped or Cancelled)"
      emits: [OrderCancelled]

    - name: ShipOrder
      fields:
        - "tracking_number: String"
      preconditions:
        - "state.status == OrderStatus::Placed"
      emits: [OrderShipped]

  events:
    - name: OrderPlaced
      fields:
        - "customer_id: CustomerId"
        - "items: Vec<LineItem>"
        - "total: Decimal"
      evolve_effect: "status → Placed; items and customer_id populated; total set"

    - name: OrderCancelled
      fields: ["reason: String"]
      evolve_effect: "status → Cancelled"

    - name: OrderShipped
      fields: ["tracking_number: String"]
      evolve_effect: "status → Shipped; tracking_number set"

  state:
    struct: OrderState
    fields:
      - "status: OrderStatus  (default: Uninitialised)"
      - "items: Vec<LineItem>  (default: empty)"
      - "customer_id: Option<CustomerId>  (default: None)"
      - "total: Decimal  (default: 0)"
      - "tracking_number: Option<String>  (default: None)"
    supporting_enums:
      - "OrderStatus: Uninitialised | Placed | Shipped | Cancelled"

  invariants:
    - name: must_be_uninitialised
      error: "OrderError::AlreadyPlaced"
      check: "state.status != OrderStatus::Uninitialised"

    - name: must_be_cancellable
      error: "OrderError::NotCancellable { status: state.status }"
      check: "state.status != OrderStatus::Placed"

    - name: must_be_placed
      error: "OrderError::NotPlaced"
      check: "state.status != OrderStatus::Placed"

crate_layout:
  functional_core:
    - crate: order-types
      layer: es:types
      deps: ["uuid", "chrono", "serde", "thiserror", "rust_decimal"]
      forbidden_deps: ["sqlx", "tokio", "axum"]
      exports:
        - "pub trait Aggregate"
        - "pub struct OrderId(Uuid)"
        - "pub enum OrderCommand"
        - "pub enum OrderEvent"
        - "pub struct OrderState"
        - "pub enum OrderStatus"
        - "pub enum OrderError"
        - "pub struct EventEnvelope<E>"

    - crate: order-domain
      layer: es:domain
      deps: ["order-types"]
      forbidden_deps: ["sqlx", "tokio", "axum", "reqwest"]
      exports:
        - "pub struct Order  (implements Aggregate)"
      notes: "All tests here are pure unit tests using the GWT harness. Zero DB, zero async."

  imperative_shell:
    - crate: order-store
      layer: es:store
      deps: ["order-types", "sqlx", "serde_json", "uuid", "chrono"]

    - crate: order-service
      layer: es:service
      deps: ["order-types", "order-domain", "order-store", "tokio", "tracing"]

    - crate: order-api
      layer: es:api
      deps: ["order-types", "order-service", "axum", "serde_json"]

projections:
  - name: OrderSummary
    reads_events: [OrderPlaced, OrderCancelled, OrderShipped]
    read_model:
      - "id: OrderId"
      - "status: OrderStatus"
      - "customer_id: CustomerId"
      - "total: Decimal"
      - "item_count: usize"
    storage: "postgres table: order_summaries"
    crate: order-service/projections/order_summary.rs

snapshots:
  needed: false
  rationale: "Orders have at most ~10 events in their lifetime — no snapshot needed"

sagas:
  needed: false
  rationale: "No cross-aggregate coordination required for this feature"

fcis_verification:
  core_has_no_io: true
  shell_never_imported_by_core: true
  decide_is_pure: true
  evolve_is_pure: true
  fold_uses_default_impl: true
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:es-aggregate-architect",
  prompt="Design the aggregate structure for this ADR: <path>. Workspace: <path>"
)
```
