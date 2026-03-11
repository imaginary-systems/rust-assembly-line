# /ral:adr — Author and Validate an Architecture Decision Record

## Overview

The ADR (Architecture Decision Record) command helps you create and validate a complete ADR for a Rust feature. ADRs are a lightweight, numbered record of architectural decisions — what was decided, why, what was considered, and what the consequences are. They accumulate over time and are never deleted, only superseded.

## Usage

```
/ral:adr <adr-path>                          # Validate an existing ADR
/ral:adr --new <feature-name>                # Scaffold a new ADR (auto-numbered)
/ral:adr --new <feature-name> --from "<description>"  # Generate from description
/ral:adr --supersede <NNNN> <feature-name>  # Create a new ADR superseding an old one
```

## Arguments

- `<adr-path>` — Path to an existing ADR markdown file to validate
- `--new <feature-name>` — Create a new ADR with the next sequential number under `docs/adr/`
- `--from "<description>"` — One or more sentences describing the decision context (used to pre-fill sections)
- `--supersede <NNNN>` — Mark ADR `NNNN` as superseded and create the replacement

## Naming Convention

ADRs are stored as `docs/adr/NNNN-<slug>.md` with zero-padded four-digit numbers:
- `docs/adr/0001-use-sqlx-for-database-access.md`
- `docs/adr/0002-use-tokio-async-runtime.md`
- `docs/adr/0042-replace-actix-with-axum.md`

The next number is determined by scanning existing files in `docs/adr/`.

## Workflow

### Validating an Existing ADR

1. Read the ADR at `<adr-path>`
2. Run `rust-assembly-line:planning:adr-structure-validator` on its contents
3. If INVALID: display the missing/weak sections with specific feedback
4. If VALID: emit `[RAL:ADR:VALID]` and display a summary of what was found

### Scaffolding a New ADR

1. Scan `docs/adr/` to determine the next sequential number
2. Generate the ADR skeleton at `docs/adr/NNNN-<feature-name>.md` with all 13 required sections
3. If `--from` was provided, pre-fill each section with content derived from the description
4. Run validation on the generated ADR
5. Report which sections need more detail from the author

### Superseding an ADR

1. Read the existing ADR at `docs/adr/NNNN-*.md`
2. Update its **Status** to: `superseded by ADR-MMMM` (where MMMM is the new number)
3. Create the new ADR with a link back to the superseded one in the Context section

## ADR Template

When scaffolding, create the file at `docs/adr/NNNN-<feature-name>.md`:

```markdown
# ADR-NNNN: <Short Imperative Title>

**Status**: proposed
**Date**: <YYYY-MM-DD>
**Author**: <author>
**Supersedes**: —
**Superseded by**: —

---

## Context

<!--
What is the situation forcing this decision?
What constraints, forces, or trade-offs exist?
What problem needs solving?
-->

## Decision

<!--
State the decision clearly. Start with "We will..." or "We have decided to...".
Be concrete — vague decisions are not decisions.
-->

We will ...

## Entities & Data Models

<!--
Rust structs, enums, traits involved in this decision.
Include field names and types. Code blocks preferred.
-->

```rust
// Example:
pub struct Foo {
    pub id: Uuid,
}
```

## Concurrency Model

<!--
Sync vs async? Channels? Shared state? Arc<RwLock<T>>?
State "no concurrency" explicitly if that is the choice.
-->

## Error Strategy

<!--
Which crates use thiserror? Which use anyhow?
Name the error enums. Describe propagation rules.
-->

## API Surface

<!--
Public trait signatures OR HTTP/gRPC endpoint definitions.
These form the contract downstream crates depend on.
-->

## Crate Impact

<!--
List each crate: new, modified, or unchanged.
Describe dependency direction changes.
-->

| Crate | Change | Notes |
|-------|--------|-------|
| `foo-types` | New | Domain types |

## Test Strategy

<!--
Unit tests, integration tests, property tests, doc tests.
Be specific about what tooling and what coverage target.
-->

## Consequences

<!--
Trade-offs of this decision:
- What becomes easier?
- What becomes harder?
- What risks or technical debt does this introduce?
- What constraints does this place on future decisions?
-->

### Positive
-

### Negative
-

### Risks
-

## Alternatives Considered

<!--
List at least one alternative approach that was evaluated.
For each: what it is, why it was rejected.
-->

### Alternative 1: <Name>
**Rejected because**: ...

## Out of Scope

<!--
At least two explicit non-goals to bound the work.
-->

- Not in scope: ...
- Not in scope: ...
```

## Output

- Prints validation results with specific section feedback
- For `--new`: creates the ADR file at `docs/adr/NNNN-<feature-name>.md`
- For `--supersede`: updates the old ADR's Status field
- Emits `[RAL:ADR:VALID] {"path": "...", "number": "0042", "sections": 13}` on success
- Emits `[RAL:ADR:INVALID] {"missing": ["Consequences", "Alternatives Considered"]}` on failure

## ADR Lifecycle

```
proposed → accepted → deprecated
                    ↘ superseded by ADR-NNNN
```

- **proposed** — draft under review
- **accepted** — approved and active
- **deprecated** — no longer relevant but not replaced
- **superseded** — replaced by a newer ADR (link required)

## Next Step

Once the ADR is valid and accepted, run `/ral:plan <adr-path>` to transform it into Linear stories.
