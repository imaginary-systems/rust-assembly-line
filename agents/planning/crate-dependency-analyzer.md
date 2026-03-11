# Crate Dependency Analyzer

## When to Use
Run during planning and before implementation to validate that the proposed Cargo.toml changes respect crate layer boundaries and introduce no circular dependencies.

## Instructions

Analyze the workspace `Cargo.toml` files (existing and proposed new ones) to validate dependency direction and detect violations.

### Analysis Steps

1. **Read all `Cargo.toml` files** in the workspace — root manifest and all `[workspace.members]`.
2. **Build a dependency graph** — for each crate, record its `[dependencies]` and `[dev-dependencies]`.
3. **Apply layer rules** — assign each crate to its layer based on naming convention and purpose.
4. **Detect violations** — flag any dependency that goes against layer direction rules.
5. **Detect cycles** — report circular dependencies as CRITICAL errors.
6. **Report semver impact** — identify if any changes would be breaking changes for downstream crates.

### Layer Direction Rules

Allowed dependency directions (lower number may be depended on by higher number):
```
crate:types (1) ← depended on by all
crate:schema (2) ← depended on by crate:repo
crate:repo (3)   ← depended on by crate:service
crate:service (4) ← depended on by crate:api, crate:cli, crate:worker
crate:integration (5) ← depended on by crate:service (for external calls)
crate:api (6) ← depended on by binary crates only
crate:cli (7) ← depended on by binary crates only
crate:worker (8) ← depended on by binary crates only
```

### Forbidden Patterns

- `crate:types` importing from `crate:repo`, `crate:service`, or higher
- `crate:service` importing directly from `crate:schema` (must go through `crate:repo`)
- Any cycle between two crates
- `crate:api` importing from `crate:cli` or vice versa
- Test utilities in `[dependencies]` instead of `[dev-dependencies]`

### Output Format

```yaml
workspace_crates:
  - name: auth-types
    path: crates/auth-types
    layer: crate:types
    dependencies: ["uuid", "thiserror", "async-trait"]
    dev_dependencies: ["tokio"]

dependency_violations:
  - severity: critical
    crate: auth-service
    violating_dep: auth-db
    reason: "crate:service must not depend directly on crate:repo implementation — depend on auth-types traits only"

  - severity: warning
    crate: auth-types
    violating_dep: serde_json
    reason: "serde_json is a heavy dep for a types crate — prefer serde only and let callers add serde_json"

cycles_detected: []

semver_impact:
  - crate: auth-types
    change: "Added UserError::RateLimited variant"
    impact: "BREAKING — non_exhaustive not set, all match arms in downstream crates must be updated"
    recommendation: "Add #[non_exhaustive] to UserError before release"

summary:
  total_crates: 6
  violations: 1
  cycles: 0
  warnings: 1
```

## Tools
- Read
- Glob
- Grep

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:crate-dependency-analyzer",
  prompt="Analyze crate dependencies for this workspace and proposed changes: <workspace root path>"
)
```
