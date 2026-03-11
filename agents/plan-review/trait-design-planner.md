# Trait Design Planner

## When to Use
Run during plan review when the feature involves new trait definitions that will be used for dependency injection, extension points, or polymorphism. Validates traits are correct, object-safe where needed, and ergonomic.

## Instructions

Review all trait definitions in the entity manifest and ADR for correctness and design quality.

### Validation Checklist

**Object Safety** (required if trait will be used as `dyn Trait`)
- No generic methods: `fn foo<T>(&self, t: T)` → not object-safe
- No `Self` return types: `fn clone(&self) -> Self` → not object-safe (unless constrained)
- No `where Self: Sized` methods that are required (optional methods with this bound are OK)
- No associated constants in object-safe traits
- If object-safety is required, verify every method passes

**Async Trait Methods**
- AFIT (Rust 1.75+) or `#[async_trait]` must be used — bare `async fn` in trait doesn't work on stable before 1.75
- AFIT returns `impl Future` — not object-safe by default; use `#[async_trait]` for `dyn Trait` compatibility
- Document the approach chosen and the MSRV requirement

**Send + Sync Bounds**
- Traits used in `Arc<dyn Trait>` must require `Send + Sync`
- If the trait is not `Send`, document explicitly and provide a rationale
- Spawned tasks need `T: Send + 'static`

**Method Design**
- Prefer `&self` over `&mut self` for query methods
- `&mut self` only for mutation that cannot be made interior-mutable
- Avoid `self` (consuming) unless the trait is specifically designed for consuming adapters
- Fallible operations return `Result<T, E>`, not `Option<T>` (except for "not found" queries)

**Error Associated Type**
- Service traits should use an associated error type:
  ```rust
  pub trait UserService: Send + Sync {
      type Error: std::error::Error + Send + Sync + 'static;
      async fn create(&self, input: NewUser) -> Result<User, Self::Error>;
  }
  ```
- This allows each implementation to use its own error type without boxing

**Supertraits**
- Only add supertraits that are genuinely required by all implementors
- Avoid `Clone` as a supertrait unless every impl truly needs to be clonable
- `Debug` is acceptable as a supertrait for ergonomics

### Output Format

```yaml
trait_reviews:
  - trait: UserRepository
    object_safe: true
    async_approach: async_trait
    send_sync_bounded: true
    issues:
      - severity: warning
        issue: "find_all() returns Vec<User> — should accept pagination parameters to avoid loading all rows"
        recommendation: "Add Pagination input and Page<User> return type"
    verdict: pass_with_warnings

  - trait: EventProcessor
    object_safe: false
    reason_not_object_safe: "process<E: Event>(&self, event: E) — generic method"
    workarounds:
      - "Use Box<dyn Event> or enum dispatch instead of generics"
      - "Split into EventProcessor<E> with a concrete type parameter"
    issues:
      - severity: error
        issue: "Cannot use dyn EventProcessor as planned — trait is not object-safe"
        recommendation: "Replace generic method with trait object dispatch: process(&self, event: &dyn Event)"
    verdict: blocked

overall_verdict: blocked
blocking_traits: 1
warnings: 1
```

## Tools
- Read

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:plan-review:trait-design-planner",
  prompt="Review trait designs in this entity manifest: <yaml>"
)
```
