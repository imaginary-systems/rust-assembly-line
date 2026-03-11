# Type Strictness Reviewer

## When to Use
Run on every PR. Enforces strong typing, bans type erasure, validates generic bounds, and ensures Rust's type system is used to enforce invariants rather than bypassed.

## Instructions

Audit all changed `.rs` files for type strictness violations and opportunities to use the type system more effectively.

### CRITICAL Violations

**Type Erasure in Public APIs**
- `pub fn foo() -> Box<dyn Any>` — never return `dyn Any` from public API
- Transmuting between unrelated types without documentation of the safety invariant
- Using `std::any::TypeId` as a runtime type system substitute in library code

**Primitive Obsession in Public API**
- `pub fn create_user(id: u64, org_id: u64)` — callers can swap arguments silently
  → must use newtype wrappers: `UserId(u64)`, `OrgId(u64)`
- `pub fn transfer(from: String, to: String, amount: f64)` — three stringly-typed args
  → use `AccountId`, `AccountId`, `Decimal`
- `bool` parameters in public functions with non-obvious meaning: `fn process(data: &[u8], verify: bool, async_mode: bool)` → use a builder or flags enum

**Unsafe Type Assumptions**
- Casting with `as` for integer narrowing without explicit bounds check
- Casting pointer-sized types (`usize`) to smaller fixed sizes

### ERROR Violations

**Missing Invariant Enforcement**
- Newtype with `pub` inner field: `pub struct UserId(pub Uuid)` — callers can construct invalid values
  → `pub struct UserId(Uuid)` with `impl UserId { pub fn new(id: Uuid) -> Self }`
- `String` field that holds validated data (email, URL) without validation at construction
  → use a validated newtype: `Email(String)` with `Email::parse(s: &str) -> Result<Email, _>`

**Generic Bound Issues**
- `T: Clone + Debug + Serialize + Deserialize<'_> + Send + Sync + 'static + Default + PartialEq + ...`
  with 8+ bounds → extract a supertrait or reconsider the design
- Missing `+ Send + Sync` bounds on generics used across thread boundaries
- `where T: Fn(A) -> B` when a named trait would be clearer

**Option Misuse**
- `Option<bool>` — use a proper tri-state enum instead
- `Option<Vec<T>>` — use `Vec<T>` (empty vec is the absent case)
- `Option<String>` for a value that should never be None at the point of use — unwrap it earlier

### WARNING Violations

- `f32`/`f64` in monetary calculations — use `rust_decimal::Decimal` or a fixed-point type
- `i32` for IDs that could overflow — use `i64` or `Uuid`
- `Vec<u8>` for structured binary data — consider a newtype with semantic meaning
- `HashMap<String, ...>` where keys should be an enum — use `EnumMap` or match on enum

### Output Format

```yaml
type_strictness_review:
  files_reviewed:
    - path: crates/auth-api/src/handlers.rs
      violations:
        - line: 34
          severity: critical
          code: "pub async fn create_user(user_id: u64, org_id: u64)"
          issue: "Primitive u64 for both IDs — caller can accidentally swap arguments"
          fix: "pub async fn create_user(user_id: UserId, org_id: OrgId)"

        - line: 78
          severity: error
          code: "pub struct Email(pub String)"
          issue: "Public inner field allows constructing invalid Email without validation"
          fix: "Make inner field private; add Email::parse(s: &str) -> Result<Email, EmailError>"

        - line: 156
          severity: warning
          code: "let balance: f64 = row.get(\"balance\");"
          issue: "f64 for monetary balance — floating point cannot represent all currency values"
          fix: "Use rust_decimal::Decimal or store as i64 cents"

summary:
  files_reviewed: 3
  critical: 1
  errors: 1
  warnings: 1
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:type-strictness-reviewer",
  prompt="Review type strictness in changed files. Workspace: <path>"
)
```
