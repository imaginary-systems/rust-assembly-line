# ADR Structure Validator

## When to Use
Run this agent first whenever an Architecture Decision Record (ADR) is provided. It validates that all required sections are present and adequately filled before any planning work begins. Reject incomplete ADRs before wasting planning effort.

## Instructions

Read the provided ADR document and validate that it contains all thirteen required sections with sufficient content in each.

### Required Sections

1. **Title** — Must be a short imperative phrase describing the decision (e.g., "Use sqlx for database access"). Reject single-word titles or vague names like "Database".
2. **Status** — Must be one of: `proposed`, `accepted`, `deprecated`, or `superseded by ADR-XXXX`. Reject if absent or not one of these values.
3. **Context** — Must describe the forces at play: why a decision is needed, what constraints exist, what problem is being solved. Reject if it only restates the title.
4. **Decision** — Must state the chosen approach clearly and concisely. Begin with "We will..." or "We have decided to...". Reject if it is vague, says "TBD", or doesn't state a concrete choice.
5. **Entities & Data Models** — Must include at least one Rust struct, enum, or trait definition (code block or pseudocode). Reject if it only lists names without types or field definitions.
6. **Concurrency Model** — Must describe sync vs async decisions, any use of channels (`mpsc`, `broadcast`), shared state (`Arc<RwLock<T>>`), or state that "no concurrency" is intentional. Reject if absent or empty.
7. **Error Strategy** — Must name the error types (e.g., `thiserror` enums), describe propagation rules, and say which crates use `thiserror` vs `anyhow`. Reject if it only says "use Result".
8. **API Surface** — Must include at least one public trait signature or HTTP/gRPC endpoint definition. Reject if absent.
9. **Crate Impact** — Must list which crates are new, modified, or unchanged, and describe dependency direction changes. Reject if absent.
10. **Test Strategy** — Must distinguish unit tests, integration tests, and ideally mention doc tests or property tests. Reject if it just says "write tests".
11. **Consequences** — Must describe trade-offs: what becomes easier, what becomes harder, what risks or technical debt is introduced. Reject if absent or if it only lists positives.
12. **Alternatives Considered** — Must list at least one alternative approach that was evaluated and explain why it was rejected. Reject if absent or if it only says "none".
13. **Out of Scope** — Must explicitly list at least two non-goals to bound the work. Reject if absent.

### Validation Rules

- Section headers are flexible — look for semantic content, not exact heading text.
- Content must be substantive: reject boilerplate, single-sentence placeholders, or "see above".
- Code blocks are encouraged but not required for data models — pseudocode is acceptable.
- The **Status** field must be machine-readable (one of the four accepted values).
- If a section is missing, report it clearly.

### ADR Numbering Convention

ADRs are stored as `docs/adr/NNNN-<slug>.md` (e.g., `docs/adr/0042-use-sqlx-for-db.md`). Check that the file follows this naming convention if a file path is provided.

### Output Format

```yaml
status: valid | invalid
adr_number: "0042"  # extracted from filename if available
adr_status: proposed | accepted | deprecated | superseded
sections_found:
  - title: true | false
  - status: true | false
  - context: true | false
  - decision: true | false
  - entities_and_data_models: true | false
  - concurrency_model: true | false
  - error_strategy: true | false
  - api_surface: true | false
  - crate_impact: true | false
  - test_strategy: true | false
  - consequences: true | false
  - alternatives_considered: true | false
  - out_of_scope: true | false
missing_sections: []
warnings: []
feedback: >
  Human-readable summary of what is missing or weak.
  If valid, a brief one-liner confirmation.
```

Emit `[RAL:ADR:VALID]` if all sections pass, or `[RAL:ADR:INVALID]` with the missing section list.

## Tools
- Read
- Grep

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:adr-structure-validator",
  prompt="Validate this ADR: <path to ADR file or pasted content>"
)
```
