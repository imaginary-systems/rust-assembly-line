#!/usr/bin/env bash
# RAL Pre-PR Quality Gate
# Intercepts `gh pr create` and runs Rust quality gates.
# Exit code 2 blocks the tool call; exit code 0 allows it.
set -euo pipefail

# Only run for gh pr create commands
if [[ "${CLAUDE_TOOL_INPUT:-}" != *"gh pr create"* ]]; then
  exit 0
fi

echo "╔══════════════════════════════════════════╗"
echo "║   RAL Pre-PR Quality Gates               ║"
echo "╚══════════════════════════════════════════╝"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
cd "$PROJECT_DIR"

FAILED=0

# Gate 1: Format check
echo ""
echo "→ [1/5] cargo fmt --check"
if ! cargo fmt --check 2>&1; then
  echo "✗ FAIL: Unformatted code. Run: cargo fmt"
  FAILED=1
else
  echo "✓ PASS"
fi

# Gate 2: Clippy (all warnings as errors)
echo ""
echo "→ [2/5] cargo clippy --workspace -- -D warnings"
if ! cargo clippy --workspace -- -D warnings 2>&1; then
  echo "✗ FAIL: Clippy warnings must be zero. Fix all warnings."
  FAILED=1
else
  echo "✓ PASS"
fi

# Gate 3: Tests
echo ""
echo "→ [3/5] cargo test --workspace"
if ! cargo test --workspace 2>&1; then
  echo "✗ FAIL: Tests failed. All tests must pass."
  FAILED=1
else
  echo "✓ PASS"
fi

# Gate 4: Coverage (requires cargo-llvm-cov)
echo ""
echo "→ [4/5] cargo llvm-cov (minimum 80% line coverage)"
if command -v cargo-llvm-cov &>/dev/null; then
  if ! cargo llvm-cov --workspace --fail-under-lines 80 2>&1; then
    echo "✗ FAIL: Line coverage below 80%. Add missing tests."
    FAILED=1
  else
    echo "✓ PASS"
  fi
else
  echo "⚠ SKIP: cargo-llvm-cov not installed"
  echo "  Install with: cargo install cargo-llvm-cov && rustup component add llvm-tools-preview"
fi

# Gate 5: Documentation build
echo ""
echo "→ [5/5] cargo doc --workspace --no-deps"
if ! cargo doc --workspace --no-deps 2>&1; then
  echo "✗ FAIL: Documentation build failed. Fix doc errors."
  FAILED=1
else
  echo "✓ PASS"
fi

echo ""
if [ $FAILED -ne 0 ]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✗ BLOCKED: Fix failures before PR       ║"
  echo "╚══════════════════════════════════════════╝"
  exit 2
fi

echo "╔══════════════════════════════════════════╗"
echo "║  ✓ All quality gates passed              ║"
echo "╚══════════════════════════════════════════╝"
exit 0
