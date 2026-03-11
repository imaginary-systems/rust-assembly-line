# Dependency Linker

## When to Use
Run after the story generator completes. Takes the full story list and establishes blocks/blocked-by relationships using the crate layer priority system.

## Instructions

Apply the crate layer priority rules to create a dependency graph between stories.

### Dependency Rules

**Automatic Layer Dependencies**
For stories about the same entity, lower-priority layers block higher-priority layers:

```
crate:types (1) → blocks → crate:schema (2)
crate:schema (2) → blocks → crate:repo (3)
crate:repo (3)   → blocks → crate:service (4)
crate:service (4) → blocks → crate:api (5), crate:cli (6), crate:worker (7)
crate:integration (5) → blocks → crate:service (4) [external deps only]
```

**Cross-Entity Dependencies**
- If Story B's acceptance criteria reference a type from Story A, Story A blocks Story B.
- If Story B's implementation notes say "depends on X", Story A (the X story) blocks Story B.

**Migration Dependencies**
- Every `crate:repo` story for an entity is blocked by that entity's `crate:schema` story.
- Multiple migrations must be ordered by their sequential nature (migration N blocks migration N+1).

**Integration Dependencies**
- External client stories (`crate:integration`) must be completed before the service stories that call them.

### Cycle Detection
- Report any detected cycles as ERRORS — they indicate a design flaw in the ADR.
- Cycles must be resolved before stories are created in Linear.

### Output Format

```yaml
dependency_graph:
  - story: "Define UserError enum in auth-types"
    id: STORY-1
    crate_layer: crate:types
    blocks:
      - STORY-3  # UserRepository trait (crate:types depends-on chain)
      - STORY-5  # UserService (needs error types)
    blocked_by: []

  - story: "Create users table migration"
    id: STORY-2
    crate_layer: crate:schema
    blocks:
      - STORY-4  # UserRepository sqlx implementation
    blocked_by: []

  - story: "Implement UserRepository trait"
    id: STORY-3
    crate_layer: crate:types
    blocks:
      - STORY-4  # Concrete impl needs the trait
    blocked_by:
      - STORY-1  # Needs UserError

cycles_detected: []
warnings: []
critical_path:
  - STORY-1 → STORY-3 → STORY-4 → STORY-5 → STORY-6 → STORY-7
  estimated_serial_stories: 7
  parallelizable_stories: 3
```

## Tools
- Read

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:dependency-linker",
  prompt="Link dependencies for these stories: <yaml>"
)
```
