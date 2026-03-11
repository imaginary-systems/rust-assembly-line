# /ral:compound — Capture Learnings from Completed Work

## Overview

Reviews a completed work session and runs three compound agents in parallel to document reusable Rust patterns, lifetime solutions, and crate integration recipes.

## Usage

```
/ral:compound
/ral:compound --story-id <ISSUE_ID>
/ral:compound --session    # Review current session's changes
```

## Arguments

- `--story-id <ID>` — Capture learnings from a specific Linear story's implementation
- `--session` — Capture learnings from the current active session (reads git diff HEAD)

## Workflow

### Step 1 — Gather Context

Collect the implementation context:
```bash
git diff main --stat     # Changed files summary
git diff main            # Full diff for agent review
git log main..HEAD --oneline  # Commits in this branch
```

### Step 2 — Run Compound Agents (parallel)

Launch all three simultaneously:

```
Agent A: rust-assembly-line:compound:rust-pattern-documenter
  Input: changed files, git diff
  Output: new pattern docs in docs/patterns/rust/

Agent B: rust-assembly-line:compound:lifetime-solution-documenter
  Input: changed files, git diff
  Output: new solution docs in docs/solutions/lifetimes/

Agent C: rust-assembly-line:compound:crate-integration-documenter
  Input: changed Cargo.toml files, new external crates
  Output: new integration docs in docs/integrations/
```

### Step 3 — Index Updates

After all agents complete, update the documentation index:

```bash
# Update docs/patterns/INDEX.md
# Update docs/solutions/INDEX.md
# Update docs/integrations/INDEX.md
```

Each index entry format:
```markdown
- **[Pattern Name](./path/to/doc.md)** — One-sentence summary — discovered in RUST-56
```

### Step 4 — Report

```
Compound learnings captured for: RUST-56

Patterns documented:    2
  - Layered error conversion (thiserror + anyhow boundary)
  - Arc<dyn Trait> DI with mockall test doubles

Lifetime solutions:     1
  - Async task non-static reference → switch to Arc<Pool>

Crate integrations:     1
  - sqlx v0.7 with test isolation via sqlx::test macro

Docs written to:
  docs/patterns/rust/error_handling/layered_error_conversion.md
  docs/patterns/rust/di/arc_dyn_trait_test_double.md
  docs/solutions/lifetimes/async_task_non_static_ref.md
  docs/integrations/sqlx.md
```

## Output Markers

```
[RAL:COMPOUND:START] {"storyId": "RUST-56", "agents": 3}
[RAL:COMPOUND:COMPLETE] {"patterns": 2, "lifetimes": 1, "integrations": 1, "docs_written": 4}
```

## When to Run

Run `/ral:compound` after:
- A story is completed and the PR is merged
- A particularly hard debugging session
- Implementing a new external service integration
- Solving a non-trivial borrow checker or async lifetime issue

Running it after every PR ensures the project builds institutional knowledge over time.
