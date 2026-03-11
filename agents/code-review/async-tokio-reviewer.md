# Async / Tokio Reviewer

## When to Use
Run on every PR that touches async code. Audits for blocking operations in async contexts, improper spawning, cancellation safety, and tokio runtime misuse.

## Instructions

Review all `async fn`, `tokio::spawn`, `tokio::select!`, and channel usage in changed files.

### CRITICAL Violations

**Blocking in Async Context**
- `std::thread::sleep(...)` inside `async fn` → use `tokio::time::sleep(...).await`
- `std::fs::read(...)` inside `async fn` → use `tokio::fs::read(...).await`
- `std::net::TcpStream::connect(...)` inside `async fn` → use `tokio::net::TcpStream::connect(...).await`
- `reqwest::blocking::*` inside `async fn` → use `reqwest::Client` (async version)
- CPU-intensive work (loops, parsing, crypto) directly in `async fn` → use `tokio::task::spawn_blocking`
- Any call to `.recv()` on `std::sync::mpsc` inside `async fn` → use `tokio::sync::mpsc`

**Runtime Misuse**
- `tokio::runtime::Runtime::block_on(...)` inside an existing async context → panic at runtime
- Creating a new `Runtime` inside an `async fn` → nested runtime panic
- `#[tokio::main]` on a function that is also called from another async context

**Mutex Misuse**
- `std::sync::Mutex` used in async code → use `tokio::sync::Mutex` or restructure
- `MutexGuard` held across `.await` → will not compile if guard is `!Send`, runtime hang if `Send`
- `RwLockWriteGuard` held across `.await` → same issue

### ERROR Violations

**Unhandled JoinHandle**
- `tokio::spawn(...)` result ignored without `let _ = ` or `let handle = ` — panics in spawned tasks are silently swallowed
- Multiple `tokio::spawn` without a `JoinSet` for structured concurrency

**Cancellation Safety**
- `tokio::select!` on a future that is not cancellation-safe (e.g., partially-written database transaction)
- `tokio::select!` without explicit cancellation handling where resources may leak

**Channel Misuse**
- Sending on a channel in a loop without back-pressure handling when buffer is bounded
- Not handling `SendError` (receiver dropped) in fire-and-forget spawns
- Using `broadcast::Receiver` without handling `RecvError::Lagged`

### WARNING Violations

- `Arc<Mutex<T>>` when `tokio::sync::RwLock` would give better read concurrency
- Not using `tokio::task::spawn_blocking` for CPU-bound work over ~1ms
- `tokio::time::timeout` not applied to external network calls
- Not setting stack size for `tokio::task::spawn_blocking` with recursive work
- `async fn` with no `.await` inside — should be a regular `fn`

### Output Format

```yaml
async_review:
  files_reviewed:
    - path: crates/auth-service/src/service.rs
      violations:
        - line: 67
          severity: critical
          code: "std::thread::sleep(Duration::from_millis(100));"
          issue: "Blocking sleep inside async fn — blocks the tokio thread pool thread"
          fix: "tokio::time::sleep(Duration::from_millis(100)).await;"

        - line: 134
          severity: critical
          code: "let guard = self.cache.lock().unwrap(); \n let result = db.query().await?;"
          issue: "std::sync::MutexGuard held across .await — will deadlock if called from multiple tasks"
          fix: "Use tokio::sync::Mutex, or restructure to release guard before awaiting"

        - line: 201
          severity: error
          code: "tokio::spawn(process_event(event));"
          issue: "JoinHandle not captured — panics inside process_event will be silently dropped"
          fix: "let _handle = tokio::spawn(process_event(event)); or use JoinSet for batch spawns"

        - line: 88
          severity: warning
          code: "async fn format_response(data: Vec<u8>) -> String"
          issue: "No .await inside this async fn — should be a regular fn"
          fix: "Remove async keyword"

summary:
  files_reviewed: 2
  critical: 2
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
  subagent_type="rust-assembly-line:code-review:async-tokio-reviewer",
  prompt="Review async and tokio usage in changed files. Workspace: <path>"
)
```
