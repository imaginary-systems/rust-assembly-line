# Lifetime Solution Documenter

## When to Use
Run after resolving complex lifetime or borrow checker errors during implementation. Documents the solution so future sessions can reference it instead of fighting the borrow checker from scratch.

## Instructions

Review the code changes and identify any lifetime or borrow checker issues that were solved non-trivially. Document the problem, the failed approaches, and the working solution.

### What to Document

**Document a lifetime solution when**:
- It took more than one attempt to satisfy the borrow checker
- The solution is not immediately obvious from the error message
- The solution involves lifetime annotations that aren't explained by the Rust Book basics
- The solution uses `Pin<T>`, self-referential structs, or complex async lifetimes
- The solution involves `'static` bounds and required architectural changes
- The solution uses higher-ranked trait bounds (HRTBs: `for<'a>`)

**Specific scenarios to document**:
- Returning a reference from a function that also takes a reference (lifetime variance)
- Async function with non-`'static` captures
- Trait object lifetime bounds: `dyn Trait + 'a`
- `impl Trait` vs `dyn Trait` lifetime interaction
- Mutex guard across await points and the refactoring required
- Structs with borrowed fields and their constraints

### Solution Document Format

Save to `docs/solutions/lifetimes/<problem-slug>.md`:

```markdown
# Lifetime Solution: <Short description>

## The Problem
Describe the code structure that triggered the error and the exact error message (or a paraphrase).

## Failed Approaches
1. **Approach 1**: What was tried and why it failed
2. **Approach 2**: What was tried and why it failed

## Working Solution
```rust
// The code that finally compiled, with annotations explaining the key decisions
```

## Why This Works
Explain the lifetime reasoning — why does the borrow checker accept this?

## Key Insight
One-sentence summary of the core insight.

## Applicable When
- List conditions where this solution applies

## References
- Rust Nomicon chapter if applicable
- RFC if the behavior changed in a specific Rust version
```

### Output Format

```yaml
lifetime_solutions_documented:
  - problem: "Storing database connection reference in async task without 'static"
    solution_file: docs/solutions/lifetimes/async_task_non_static_ref.md
    key_insight: "Async tasks require 'static — use Arc<Pool> instead of &'a Pool"
    severity_of_original_problem: "Required architectural change (switch from &Pool to Arc<Pool>)"

  - problem: "HRTBs needed for closure that borrows from multiple lifetimes"
    solution_file: docs/solutions/lifetimes/hrtb_multi_lifetime_closure.md
    key_insight: "for<'a> Fn(&'a T) -> &'a U allows the closure to work with any lifetime"

nothing_new: false
```

## Tools
- Read
- Grep
- Glob
- Write

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:compound:lifetime-solution-documenter",
  prompt="Document any lifetime or borrow checker solutions from this session. Workspace: <path>"
)
```
