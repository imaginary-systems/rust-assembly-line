# Workspace Impact Reviewer

## When to Use
Run during plan review to identify all crates affected by the planned changes, assess semver impact, and flag any dependency changes needed.

## Instructions

Read the workspace `Cargo.toml` files and the planned crate changes to produce a full impact assessment.

### Analysis Steps

1. **Map existing crates** — read all `Cargo.toml` files in the workspace.
2. **Identify changed crates** — from the ADR and crate architecture design, list which crates are new, modified, or unchanged.
3. **Trace downstream consumers** — for each modified crate, find all crates that depend on it.
4. **Assess semver impact** — classify each change as patch, minor, or major (breaking).
5. **Identify new Cargo dependencies** — list any new external crates needed and flag for review.
6. **Check MSRV compatibility** — verify new dependencies are compatible with the workspace MSRV.

### Semver Rules

**Patch-level (non-breaking)**
- Adding a new `pub fn` to an impl block (not a trait)
- Adding a new field to a struct marked `#[non_exhaustive]`
- Adding a new enum variant marked `#[non_exhaustive]`
- Internal refactoring with identical public API

**Minor-level (additive, backward-compatible)**
- Adding a new public type
- Adding a new method to a trait with a default implementation
- Adding a new feature flag

**Major-level (breaking)**
- Removing or renaming a public type, function, or field
- Adding a method to a trait without a default implementation
- Changing a function signature (parameter types, return type)
- Adding a required field to a non-exhaustive struct (downstream code must update construction)
- Changing error variants in a non-exhaustive-free enum

### New Dependency Review Criteria

Flag any new external dependency that:
- Has not been updated in 12+ months (potential abandonment)
- Has a `0.x` version (unstable API, can break on minor version bump)
- Pulls in a large transitive dependency tree (`cargo tree` depth > 5)
- Introduces `unsafe` code (check with `cargo geiger`)
- Duplicates functionality already available in the workspace

### Output Format

```yaml
workspace_impact:
  new_crates:
    - name: auth-integration
      path: crates/auth-integration
      purpose: "OAuth2 provider client"
      new_external_deps:
        - name: oauth2
          version: "4.4"
          risk: low
          notes: "Widely used, actively maintained"

  modified_crates:
    - name: auth-types
      change_type: minor
      changes:
        - "Added UserRole enum (additive)"
        - "Added role field to User struct (BREAKING if non_exhaustive not set)"
      downstream_consumers:
        - auth-service
        - auth-api
        - auth-cli
      semver_impact: major
      action_required: "Add #[non_exhaustive] to User struct before adding field, OR update all construction sites"

  unchanged_crates:
    - auth-worker (no dependency on changed types)

flagged_dependencies:
  - crate: some-lib
    version: "0.3"
    flag: "Unstable API (0.x) — breaking changes possible on minor version bump"
    recommendation: "Pin to exact version: some-lib = \"=0.3.2\""

msrv_check:
  workspace_msrv: "1.75"
  new_deps_min_rust:
    - dep: oauth2
      min_rust: "1.65"
      compatible: true
  result: pass

summary:
  new_crates: 1
  modified_crates: 1
  breaking_changes: 1
  flagged_new_deps: 1
  recommendation: "REVIEW — one breaking change requires mitigation before merging"
```

## Tools
- Read
- Glob
- Grep
- Bash

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:plan-review:workspace-impact-reviewer",
  prompt="Assess workspace impact for this planned feature. Workspace root: <path>"
)
```
