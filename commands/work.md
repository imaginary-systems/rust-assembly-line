# /ral:work — Implement the Next Unblocked Story

## Overview

Picks the next unblocked story from Linear and implements it following Rust quality standards. Works in an isolated git worktree, runs quality gates, and creates a PR when complete.

## Usage

```
/ral:work [project-name]
/ral:work [project-name] --issue <ISSUE_ID>
/ral:work --continue
```

## Arguments

- `[project-name]` — Linear project name or prefix (e.g., `RUST`, `AUTH`)
- `--issue <ID>` — Work on a specific issue instead of picking the next unblocked one
- `--continue` — Resume an in-progress work session (reads `.claude/session/work-goal`)

## MANDATORY: Use Git Worktree

**NEVER** work directly on the main branch or in the main repository directory.
**ALWAYS** create an isolated worktree using the git-worktree skill.

## Ralph Wiggum Loop

Implement the story by following acceptance criteria one by one, exactly as written. Do not interpret, expand, or skip criteria.

### Phase 1 — Select Story

1. Query Linear for unblocked stories in the project with status "Todo"
2. Sort by: crate layer priority (lowest number first), then creation date
3. Present the selected story to the user and confirm before proceeding
4. Set Linear status to "In Progress"

### Phase 2 — Setup Worktree

```bash
# Branch naming: feat/<ISSUE_ID>-<slug>
BRANCH="feat/RUST-56-add-user-auth"
WORKTREE="../$(basename $(pwd))--feat-RUST-56-add-user-auth"
git worktree add "$WORKTREE" -b "$BRANCH"
```

Save session state to `.claude/session/work-goal`:
```
branch=feat/RUST-56-add-user-auth
worktree=../repo--feat-RUST-56-add-user-auth
issue=RUST-56
crate=auth-service
```

**All subsequent work happens inside the worktree directory.**

### Phase 3 — Implement

For each acceptance criterion in the story (in order):

1. Read the criterion
2. Read relevant existing code (don't write blind)
3. Implement the minimum code to satisfy it
4. Run `cargo check --workspace` — fix all errors before moving on
5. Write tests for this criterion
6. Run `cargo test -p <affected-crate>` — all tests must pass
7. Mark criterion as complete: `[RAL:WORK:PROGRESS] {"criterion": N, "total": M, "status": "complete"}`

**Between criteria**: run `cargo clippy -- -D warnings` and fix all warnings before proceeding.

### Phase 4 — Quality Gates

After all acceptance criteria are complete, run the full quality gate suite:

```bash
# Format check
cargo fmt --check
# If fails: cargo fmt && git add -A

# Clippy (all warnings as errors)
cargo clippy --workspace -- -D warnings
# If fails: fix each warning

# Tests with coverage
cargo llvm-cov --workspace --lcov --output-path coverage.lcov
cargo llvm-cov report --fail-under-lines 80
# If fails: add missing tests

# Documentation check
cargo doc --workspace --no-deps
# If fails: fix doc errors

# Build check (ensure no broken features)
cargo build --workspace
```

All gates must pass before creating a PR.

### Phase 5 — Code Review

Run multi-agent review on the changes:

```
/ral:review --fix
```

This runs all code review agents in parallel. If CRITICAL or ERROR findings remain after auto-fix, resolve them manually.

### Phase 6 — Create PR

```bash
gh pr create \
  --title "feat(RUST-56): Add user authentication to auth-service" \
  --body "$(cat .claude/session/pr-body.md)"
```

PR body template:
```markdown
## Summary
- Implements RUST-56: <story title>
- Adds <N> new functions to <crate>
- <brief description of what changed>

## Crate Layer
`crate:service` — auth-service

## Quality Gates
- [x] `cargo fmt --check` passes
- [x] `cargo clippy -- -D warnings` passes
- [x] `cargo test --workspace` passes
- [x] Coverage >= 80%
- [x] `cargo doc --no-deps` builds cleanly
- [x] Multi-agent code review: 0 critical, 0 errors

## Linear
Closes RUST-56
```

### Phase 7 — Cleanup

1. Update Linear issue status to "In Review"
2. Clean up session file: `rm .claude/session/work-goal`
3. Emit: `[RAL:WORK:COMPLETE] {"storyId": "RUST-56", "prUrl": "https://..."}`

## Structured Markers

```
[RAL:WORK:START] {"storyId": "RUST-56", "branch": "feat/RUST-56-add-auth", "crate": "auth-service"}
[RAL:WORK:PROGRESS] {"criterion": 1, "total": 5, "status": "complete"}
[RAL:WORK:GATE] {"gate": "clippy", "status": "pass"}
[RAL:WORK:GATE] {"gate": "tests", "status": "pass", "coverage": "87%"}
[RAL:WORK:COMPLETE] {"storyId": "RUST-56", "prUrl": "https://github.com/.../pull/42"}
```

## Rust-Specific Implementation Rules

During implementation, enforce these at every step:

- **No `unwrap()` or `expect()`** in non-test code — will block gate
- **No `blocking I/O in async`** — async-tokio-reviewer will catch this
- **Typed errors only** — use `thiserror` for library crates
- **Clippy clean throughout** — don't let warnings accumulate
- **Tests written alongside code** — not at the end
- **Every `unsafe` block has a SAFETY comment** — non-negotiable
