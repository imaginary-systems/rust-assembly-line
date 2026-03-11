# Type Complexity Assessor

## When to Use
Run during plan review to flag overly complex generic or lifetime designs that would make code hard to maintain, extend, or understand.

## Instructions

Review the entity manifest and trait interface designs for excessive type complexity.

### Complexity Red Flags

**Lifetime Proliferation**
- Struct with 3+ lifetime parameters → usually a design smell; prefer owned types
- Lifetime bounds like `'a: 'b: 'c` in function signatures → flag as hard to maintain
- `impl<'a, 'b: 'a, T: Trait<'a>> Foo<'a, 'b, T>` → flag: "consider redesigning with Arc<T>"

**Generic Parameter Explosion**
- Function with 5+ generic type parameters → flag for simplification
- Trait with 4+ associated types → flag: "consider splitting into smaller traits"
- `where` clause spanning more than 6 lines → flag for review

**Trait Object Confusion**
- Mixing `impl Trait` returns and `dyn Trait` for the same abstraction → flag: "pick one approach consistently"
- `Box<dyn Fn(A, B, C, D) -> Result<E, F>>` → flag: "consider defining a named trait instead"

**Phantom Type Overuse**
- `PhantomData` in 3+ structs for the same abstraction → may indicate over-engineering
- State machines with 10+ phantom state types → flag: "consider enum-based state machine instead"

**Newtype Overuse**
- Newtypes wrapping newtypes (`NewA(NewB(Uuid))`) → flag: "flatten the newtype chain"
- Newtypes with no invariant enforcement (no validation in constructor) → flag: "add validation or use type alias"

**Trait Hierarchy Depth**
- Supertrait chains 4+ deep (`A: B + C`, where `B: D + E`, etc.) → flag as hard to implement
- Blanket impls that conflict with each other → flag as coherence issues

### Complexity Score

Rate each type on a scale:
- **Simple (1-2)**: Plain struct/enum, 0-1 generic parameter, no lifetimes
- **Moderate (3-4)**: 1-2 generics, 1 lifetime, reasonable where clauses
- **Complex (5-6)**: Multiple generics, multiple lifetimes, complex bounds
- **Very Complex (7-8)**: Requires diagram to understand, GATs, HRTBs
- **Extreme (9-10)**: Lifetime soup, associated type chains, multiple PhantomData

### Output Format

```yaml
complexity_assessment:
  - type: "StreamProcessor<'a, T, E, S>"
    score: 7
    issues:
      - "3 generic parameters plus 1 lifetime — consider splitting into simpler pieces"
      - "S: Stream<Item = Result<T, E>> + Unpin + Send + 'a — consider a type alias for this bound"
    recommendation: "Extract StreamBound type alias: type StreamBound<'a, T, E> = dyn Stream<Item=Result<T,E>> + Unpin + Send + 'a"

  - type: "Repository<D: Database + Send + Sync + Clone + 'static>"
    score: 4
    issues:
      - "Clone bound on Database trait is unusual — repositories shouldn't need to clone their DB handle"
    recommendation: "Remove Clone bound; use Arc<dyn Database> if sharing is needed"

overall_assessment:
  max_complexity: 7
  average_complexity: 3.2
  blocking_issues: 1
  recommendation: "REVIEW — one high-complexity type needs simplification before implementation"
```

## Tools
- Read

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:plan-review:type-complexity-assessor",
  prompt="Assess type complexity for these Rust type definitions: <entity manifest yaml>"
)
```
