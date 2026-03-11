# Unsafe Code Reviewer

## When to Use
Run on every PR. Audits all `unsafe` blocks, raw pointer operations, FFI, and `#[allow(unsafe_code)]` annotations. Every unsafe block must be justified.

## Instructions

Locate and audit every use of `unsafe` in changed and surrounding code.

### Mandatory Requirements

**Every `unsafe` block MUST have a `// SAFETY:` comment** explaining:
1. Why the unsafe operation is necessary (why safe code cannot achieve this)
2. What invariants guarantee the operation is sound
3. What would break if the invariant is violated

```rust
// GOOD
// SAFETY: ptr is guaranteed non-null and properly aligned by the allocator contract
// established in new(), and no other thread holds a mutable reference at this point
// because we hold the mutex guard `_lock`.
let val = unsafe { *ptr };

// BAD — ZERO justification
let val = unsafe { *ptr };
```

### CRITICAL Safety Violations

- **Dereferencing a raw pointer without null check** — unless the invariant explains why null is impossible
- **Transmuting between types of different sizes** — undefined behavior
- **Calling an FFI function without documenting the C ABI requirements**
- **`std::mem::forget` causing a resource leak** in a way that breaks invariants
- **Creating a `&mut` reference from a raw pointer when another reference exists** — aliasing
- **`unsafe impl Send` or `unsafe impl Sync` without proof** of thread safety
- **`slice::from_raw_parts` with incorrect length or non-aligned pointer**

### ERROR Violations

- **`unsafe` block larger than necessary** — wrap only the single unsafe operation, not surrounding safe code
- **`#[allow(unsafe_code)]` at crate level** without a module-level justification
- **Raw pointer arithmetic without bounds checking** — document bounds proof in SAFETY comment
- **FFI string handling** — `CStr::from_ptr` without null-termination guarantee

### WARNING Violations

- **`unsafe` where safe alternatives exist** (e.g., using raw pointer when `Vec::get_unchecked` with bounds check would work)
- **`transmute` used for type punning** — use `bytemuck` or `zerocopy` instead
- **Missing `#[must_use]` on unsafe constructor functions**

### Audit Output

For each `unsafe` block found:
1. Show the code
2. Check for SAFETY comment — CRITICAL if missing
3. Evaluate the reasoning — ERROR if reasoning is flawed or incomplete
4. Check for minimal scope — WARNING if broader than needed

### Output Format

```yaml
unsafe_review:
  files_reviewed:
    - path: crates/buffer/src/lib.rs
      unsafe_blocks:
        - line: 78
          code: |
            unsafe {
                std::ptr::copy_nonoverlapping(src.as_ptr(), dst.as_mut_ptr(), len);
            }
          has_safety_comment: true
          safety_comment: "SAFETY: src and dst are guaranteed non-overlapping by construction in split_at_mut"
          assessment: sound
          verdict: pass

        - line: 134
          code: "unsafe { &mut *self.ptr }"
          has_safety_comment: false
          assessment: unknown
          verdict: critical
          fix: "Add SAFETY comment explaining: (1) ptr is non-null, (2) no other &mut exists, (3) lifetime is valid"

  unsafe_impls:
    - line: 22
      code: "unsafe impl Send for RawBuffer {}"
      has_safety_comment: false
      verdict: critical
      fix: "Document why RawBuffer is safe to send across threads (e.g., internal ptr managed exclusively by owner)"

summary:
  unsafe_blocks_found: 2
  unsafe_impls_found: 1
  critical: 2
  errors: 0
  warnings: 0
  verdict: blocked
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:code-review:unsafe-code-reviewer",
  prompt="Audit all unsafe code in changed files. Workspace: <path>"
)
```
