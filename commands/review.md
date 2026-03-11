# /ral:review — Multi-Agent Rust Code Review

## Overview

Runs all 12 specialized Rust code review agents in parallel on the current branch or a specific PR. Aggregates findings and optionally auto-fixes issues.

## Usage

```
/ral:review
/ral:review --pr <PR_NUMBER>
/ral:review --fix
/ral:review --agents ownership,async,errors
/ral:review --crate <crate-name>
```

## Arguments

- `--pr <NUMBER>` — Review a specific GitHub PR (defaults to current branch)
- `--fix` — Attempt to auto-fix WARNING and SUGGESTION level findings
- `--agents <LIST>` — Comma-separated list of agent names to run (default: all)
- `--crate <name>` — Limit review to files in a specific crate

## Agents

All agents run in parallel:

| Agent | Focus |
|-------|-------|
| `ownership` | `ownership-borrow-reviewer` — clones, lifetimes, references |
| `unsafe` | `unsafe-code-reviewer` — SAFETY comments, soundness |
| `async` | `async-tokio-reviewer` — blocking in async, MutexGuard across await |
| `errors` | `error-handling-reviewer` — unwrap/expect, typed errors |
| `clippy` | `clippy-compliance-reviewer` — clippy lint compliance |
| `types` | `type-strictness-reviewer` — newtypes, primitive obsession |
| `security` | `security-sentinel` — SQL injection, secrets, auth |
| `perf` | `performance-oracle` — allocations, N+1, complexity |
| `arch` | `architecture-strategist` — layer boundaries, DI |
| `patterns` | `pattern-recognition-specialist` — anti-patterns, naming |
| `tests` | `test-coverage-reviewer` — coverage, test quality |
| `api` | `api-design-reviewer` — docs, semver, HTTP conventions |

## Workflow

### Step 1 — Gather Changed Files

```bash
# For current branch
git diff main --name-only --diff-filter=ACMR | grep '\.rs$'

# For a PR
gh pr diff <NUMBER> --name-only | grep '\.rs$'
```

### Step 2 — Run All Agents in Parallel

Launch all 12 agents simultaneously, passing:
- The list of changed `.rs` files
- The workspace root path
- The PR diff (if available)

### Step 3 — Aggregate Results

Collect all agent outputs and categorize findings:

```
CRITICAL — Must fix before merge (blocks PR)
ERROR    — Should fix before merge (blocks PR)
WARNING  — Should fix (advisory, can be waived)
SUGGESTION — Nice to have (never blocks)
```

### Step 4 — Auto-Fix (if --fix)

For each WARNING/SUGGESTION finding:
1. Determine if it is mechanically fixable (clippy suggestion, naming, simple refactor)
2. Apply the fix
3. Re-run `cargo check` to verify fix compiles
4. Mark as "fixed" in the report

Cannot auto-fix: CRITICAL security issues, design violations, missing test coverage.

### Step 5 — Report

```
╔══════════════════════════════════════════════════════╗
║           RAL Code Review Report                     ║
╠══════════════════════════════════════════════════════╣
║ Branch: feat/RUST-56-add-auth                        ║
║ Files reviewed: 8                                    ║
║ Agents: 12/12 complete                               ║
╠══════════════════════════════════════════════════════╣
║ CRITICAL  0  ✓                                       ║
║ ERROR     1  ✗  (blocks merge)                       ║
║ WARNING   3  ⚠  (2 auto-fixed, 1 remaining)          ║
║ SUGGESTION 4  ℹ  (advisory)                          ║
╠══════════════════════════════════════════════════════╣
║ Blocking Issues:                                     ║
║ ERROR  error-handling  service.rs:45                 ║
║   unwrap() on line 45 — use ? operator               ║
╚══════════════════════════════════════════════════════╝
```

## Merge Gate Logic

```
IF critical > 0 OR errors > 0:
  → BLOCKED — do not merge
  → List all blocking issues with file:line and fix instructions

ELIF warnings > 0:
  → ADVISORY — can merge with team approval
  → List warnings

ELSE:
  → APPROVED — all clear
```

## Output Markers

```
[RAL:REVIEW:START] {"agents": 12, "files": 8}
[RAL:REVIEW:AGENT] {"agent": "security-sentinel", "status": "complete", "critical": 0, "errors": 0}
[RAL:REVIEW:COMPLETE] {"critical": 0, "errors": 1, "warnings": 3, "fixed": 2, "verdict": "blocked"}
```
