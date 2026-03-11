# Rust Pattern Documenter

## When to Use
Run after completing a story or implementation session. Captures reusable Rust patterns discovered during implementation that future stories can reference.

## Instructions

Review the code changed in the current session (via git diff or file reads) and identify reusable Rust patterns worth documenting.

### What to Document

**Document a pattern when**:
- A non-obvious Rust idiom was used to solve a common problem
- A trait composition approach is reusable across crates
- An error handling chain pattern solved a complex propagation problem
- An async coordination pattern (channels, select!, notify) addressed a specific concurrency need
- A generic bound trick made an API more ergonomic
- A `From`/`Into` chain solved a type conversion problem elegantly

**Do NOT document**:
- Trivial patterns already in every Rust tutorial
- One-off hacks specific to this story's exact context
- Patterns that are clearly wrong but happened to work

### Pattern Document Format

Save discovered patterns to `docs/patterns/rust/<category>/<pattern-name>.md`:

```markdown
# Pattern: <Name>

## Problem
One paragraph describing the problem this pattern solves.

## Solution
Brief description of the approach.

## Code Example
```rust
// Minimal working example
```

## When to Use
- List of conditions under which this pattern applies

## When NOT to Use
- List of conditions where this pattern would be wrong

## Tradeoffs
- Pro: ...
- Con: ...

## Related Patterns
- Links to other pattern docs
```

### Output Format

```yaml
patterns_discovered:
  - name: "Layered Error Conversion with thiserror + anyhow boundary"
    category: error_handling
    file: docs/patterns/rust/error_handling/layered_error_conversion.md
    summary: "Library crates use thiserror typed errors; binary entry point wraps with anyhow for context chaining"
    discovered_in: "auth-service story RUST-56"

  - name: "Arc<dyn Trait> DI with test doubles"
    category: dependency_injection
    file: docs/patterns/rust/di/arc_dyn_trait_test_double.md
    summary: "Service tests inject a mock Arc<dyn Repository> via mockall without hitting the database"
    discovered_in: "auth-service story RUST-57"

nothing_new: false
```

If no new patterns were discovered, emit `nothing_new: true` and a brief explanation.

## Tools
- Read
- Grep
- Glob
- Write

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:compound:rust-pattern-documenter",
  prompt="Review this session's code changes and document reusable patterns. Workspace: <path>. Changed files: <list>"
)
```
