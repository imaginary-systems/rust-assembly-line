# Performance Oracle

## When to Use
Run on every PR touching hot paths, data processing, serialization, or database queries. Identifies performance regressions, algorithmic inefficiencies, and unnecessary allocations.

## Instructions

Review changed Rust files for performance issues.

### CRITICAL Performance Issues

**Algorithmic Complexity**
- O(n²) or worse in code that could receive unbounded input
  - Nested loops over the same collection without explanation
  - `Vec::contains` or `Vec::iter().find` in a loop → use `HashSet` for O(1) lookups
  - Sorting inside a function called in a loop → sort once outside
- Loading entire tables into memory: `repo.find_all().await?` → use pagination or streaming

**Unbounded Allocations**
- Collecting an entire large stream into `Vec<T>` before processing
- Building large `String` with repeated `+=` or `push_str` in a loop → use `String::with_capacity` or a `Vec<String>` + `join`
- `format!()` inside a tight loop → use `write!` on a pre-allocated buffer

### ERROR Performance Issues

**Unnecessary Cloning**
- `.clone()` in a hot path where a borrow would work
- Cloning large structs to pass to async tasks when `Arc<T>` would avoid the copy
- `.to_string()` in serialization hot paths

**Locking**
- Holding a `Mutex` or `RwLock` while doing I/O or network calls
- Using `Mutex<HashMap<K, V>>` for high-read workloads → use `DashMap` or `RwLock<HashMap>`
- Fine-grained lock contention: one lock per item instead of sharding

**Serialization**
- `serde_json::to_string` on large payloads in request handlers without streaming
- Deserializing entire request body before validating size limits
- `serde_json::Value` (dynamic) when a typed struct could be used (typed is 2–10x faster)

**Database**
- N+1 query pattern: querying in a loop instead of using `JOIN` or batch fetch
- `SELECT *` when only specific columns are needed
- Missing index on a column used in `WHERE` clause (flag from query patterns in code)
- Not using `RETURNING` clause when an insert is followed by a select

### WARNING Performance Issues

- `Arc::clone` is cheap but not free — in a very tight loop, consider restructuring
- `HashMap::entry()` API preferred over `contains_key` + `insert` pattern
- `BTreeMap` when iteration order doesn't matter — `HashMap` is faster for pure lookups
- Regular expression compilation inside a function body → use `once_cell::sync::Lazy<Regex>`
- `base64::encode` / `decode` allocates — use `Engine::encode_string` with pre-allocated buffer for hot paths

### Output Format

```yaml
performance_review:
  files_reviewed:
    - path: crates/auth-service/src/service.rs
      issues:
        - line: 45
          severity: critical
          category: algorithmic_complexity
          code: "for user in users { if permissions.contains(&user.id) { ... } }"
          issue: "Vec::contains is O(n) — with n users and n permissions this is O(n²)"
          fix: "let permission_set: HashSet<UserId> = permissions.into_iter().collect(); then use permission_set.contains(&user.id)"
          estimated_impact: "O(n²) → O(n)"

        - line: 112
          severity: error
          category: unnecessary_clone
          code: "process_batch(items.clone()).await?;"
          issue: "Cloning entire Vec before async call — pass Arc<Vec<Item>> or pass by reference if process_batch can take &[Item]"
          fix: "If process_batch can take &[Item]: process_batch(&items).await? — saves clone of potentially large Vec"

        - line: 178
          severity: error
          category: n_plus_one
          code: "for user_id in user_ids { let user = repo.find_by_id(user_id).await?; }"
          issue: "N+1 query — one database round trip per user"
          fix: "Add UserRepository::find_by_ids(ids: &[UserId]) batch method"

        - line: 234
          severity: warning
          category: regex_compilation
          code: "let re = Regex::new(EMAIL_PATTERN).unwrap();"
          issue: "Regex compiled on every call to this function"
          fix: "static EMAIL_RE: Lazy<Regex> = Lazy::new(|| Regex::new(EMAIL_PATTERN).unwrap());"

summary:
  files_reviewed: 3
  critical: 1
  errors: 2
  warnings: 1
  verdict: needs_changes
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:performance-oracle",
  prompt="Review performance of changed files. Workspace: <path>"
)
```
