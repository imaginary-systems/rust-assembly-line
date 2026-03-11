# /ral:plan — Transform an ADR into Linear Stories

## Overview

Takes a validated ADR and runs the full planning pipeline: extract entities and flows, design crate architecture, generate stories, link dependencies, and create them in Linear.

## Usage

```
/ral:plan <adr-path>
/ral:plan <adr-path> --project-id <LINEAR_PROJECT_ID>
/ral:plan <adr-path> --dry-run
/ral:plan <adr-path> --skip-linear    # Generate stories without creating Linear issues
```

## Arguments

- `<adr-path>` — Path to a validated ADR file
- `--project-id <ID>` — Linear project ID to create stories in (overrides workspace config)
- `--dry-run` — Run the full pipeline but print stories instead of creating them in Linear
- `--skip-linear` — Output YAML story manifest to `docs/stories/<feature-name>-stories.yaml`

## Pipeline

Run the following agents **in sequence** (each depends on previous output):

### Step 1 — Validate ADR (blocking)
```
Agent: rust-assembly-line:planning:adr-structure-validator
Input: adr-path
```
If INVALID, stop and show feedback. Do not proceed.

### Step 2 — Extract Entities & Flows (parallel)
```
Agent A: rust-assembly-line:planning:entity-extractor
Agent B: rust-assembly-line:planning:flow-extractor
Input: validated ADR content
```
Run both in parallel. Collect both outputs before proceeding.

### Step 3 — Design Architecture (parallel with step 2)
```
Agent: rust-assembly-line:planning:rust-architect
Input: ADR content
```
Can run in parallel with step 2. Produces crate structure and trait interface designs.

### Step 4 — Plan Review (parallel)
```
Agent A: rust-assembly-line:plan-review:rust-feasibility-reviewer
Agent B: rust-assembly-line:plan-review:type-complexity-assessor
Agent C: rust-assembly-line:plan-review:workspace-impact-reviewer
Agent D: rust-assembly-line:plan-review:trait-design-planner
Input: entities, flows, architecture
```
Run all four in parallel. If any produces CRITICAL or ERROR findings, stop and report them. Author must update the ADR before proceeding.

### Step 5 — Generate Stories
```
Agent: rust-assembly-line:planning:story-generator
Input: entities + flows + architecture (from steps 2-3)
```

### Step 6 — Link Dependencies (parallel with story generation)
```
Agent: rust-assembly-line:planning:dependency-linker
Input: generated stories
```

### Step 7 — Plan Test Strategy
```
Agent: rust-assembly-line:planning:test-strategy-planner
Input: stories + crate structure
```

### Step 8 — Analyze Dependency Impact
```
Agent: rust-assembly-line:planning:crate-dependency-analyzer
Input: proposed Cargo.toml changes from architecture
```

### Step 9 — Create in Linear (if not --dry-run)
For each story in dependency order:
1. Create the Linear issue with title, description, and labels
2. Set `blocks` and `blocked_by` relationships
3. Set the crate layer label

## Layer Tag → Linear Label Mapping

| Crate Layer | Linear Label |
|------------|--------------|
| `crate:types` | `Layer: Types` |
| `crate:schema` | `Layer: Schema` |
| `crate:repo` | `Layer: Repo` |
| `crate:service` | `Layer: Service` |
| `crate:integration` | `Layer: Integration` |
| `crate:api` | `Layer: API` |
| `crate:cli` | `Layer: CLI` |
| `crate:worker` | `Layer: Worker` |

## Output

```
Planning complete for: <feature-name>

Stories created: 14
  crate:types   ████  4 stories
  crate:schema  ██    2 stories
  crate:repo    ██    2 stories
  crate:service ███   3 stories
  crate:api     ██    2 stories
  crate:worker  █     1 story

Critical path: 8 stories serial, 6 parallelizable
Linear project: https://linear.app/...

[RAL:PLAN:COMPLETE] {"stories": 14, "project": "RUST-42", "critical_path": 8}
```

## Next Step

Run `/ral:work [project-name]` to begin implementing the first unblocked story.
