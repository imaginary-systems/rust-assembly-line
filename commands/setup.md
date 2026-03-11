# /ral:setup — Install Hooks and Quality Gates

## Overview

Installs the Rust Assembly Line quality gate hooks into the current project. Creates pre-PR check hooks and work session tracking.

## Usage

```
/ral:setup
/ral:setup --force    # Overwrite existing hooks
```

## What Gets Installed

### 1. `.claude/hooks/pre-pr-check.sh`

Intercepts `gh pr create` and runs all quality gates. Blocks PR creation if any gate fails.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Only run for gh pr create commands
if [[ "${CLAUDE_TOOL_INPUT:-}" != *"gh pr create"* ]]; then
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║   RAL Pre-PR Quality Gates           ║"
echo "╚══════════════════════════════════════╝"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
cd "$PROJECT_DIR"

FAILED=0

# Gate 1: Format check
echo "→ cargo fmt --check..."
if ! cargo fmt --check 2>&1; then
  echo "✗ FAIL: Format check failed. Run: cargo fmt"
  FAILED=1
else
  echo "✓ PASS: Format"
fi

# Gate 2: Clippy (warnings as errors)
echo "→ cargo clippy -- -D warnings..."
if ! cargo clippy --workspace -- -D warnings 2>&1; then
  echo "✗ FAIL: Clippy warnings found. Fix all warnings before creating PR."
  FAILED=1
else
  echo "✓ PASS: Clippy"
fi

# Gate 3: Tests
echo "→ cargo test --workspace..."
if ! cargo test --workspace 2>&1; then
  echo "✗ FAIL: Tests failed."
  FAILED=1
else
  echo "✓ PASS: Tests"
fi

# Gate 4: Coverage (requires cargo llvm-cov)
if command -v cargo-llvm-cov &>/dev/null; then
  echo "→ cargo llvm-cov (min 80%)..."
  if ! cargo llvm-cov --workspace --fail-under-lines 80 2>&1; then
    echo "✗ FAIL: Coverage below 80%. Add tests before creating PR."
    FAILED=1
  else
    echo "✓ PASS: Coverage"
  fi
else
  echo "⚠ SKIP: cargo-llvm-cov not installed (run: cargo install cargo-llvm-cov)"
fi

# Gate 5: Doc check
echo "→ cargo doc --workspace --no-deps..."
if ! cargo doc --workspace --no-deps 2>&1; then
  echo "✗ FAIL: Documentation build failed. Fix doc errors."
  FAILED=1
else
  echo "✓ PASS: Docs"
fi

if [ $FAILED -ne 0 ]; then
  echo ""
  echo "╔══════════════════════════════════════╗"
  echo "║ BLOCKED: Fix quality gate failures   ║"
  echo "╚══════════════════════════════════════╝"
  exit 2  # Exit code 2 blocks the tool call
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║ ✓ All quality gates passed           ║"
echo "╚══════════════════════════════════════╝"
exit 0
```

### 2. `.claude/hooks/work-stop-check.sh`

Runs when the session stops. If a work-in-progress story has no PR yet, reminds to continue.

```bash
#!/usr/bin/env bash

SESSION_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/session/work-goal"

if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

BRANCH=$(grep '^branch=' "$SESSION_FILE" | cut -d= -f2)
ISSUE=$(grep '^issue=' "$SESSION_FILE" | cut -d= -f2)

if [ -z "$BRANCH" ] || [ -z "$ISSUE" ]; then
  exit 0
fi

# Check if PR exists for this branch
if gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null | grep -q '[0-9]'; then
  exit 0  # PR exists, work is done
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  ⚠ Work in Progress: $ISSUE"
echo "║  Branch: $BRANCH"
echo "║  No PR created yet."
echo "║  Run: /ral:work --continue"
echo "╚══════════════════════════════════════════════╝"
exit 0
```

### 3. `.claude/settings.json`

Registers the hooks:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-pr-check.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/work-stop-check.sh"
      }
    ]
  }
}
```

### 4. `.gitignore` additions

```
# Claude Code session files (not for version control)
.claude/session/
```

## Output

```
RAL Setup complete.

Installed:
  ✓ .claude/hooks/pre-pr-check.sh     (chmod +x applied)
  ✓ .claude/hooks/work-stop-check.sh  (chmod +x applied)
  ✓ .claude/settings.json             (hooks registered)
  ✓ .gitignore                        (session files excluded)

Quality gates active:
  cargo fmt --check
  cargo clippy -- -D warnings
  cargo test --workspace
  cargo llvm-cov (80% min)
  cargo doc --no-deps

To verify hooks are working: try running `gh pr create` with failing clippy.

Recommended: install cargo-llvm-cov for coverage gating:
  cargo install cargo-llvm-cov
  rustup component add llvm-tools-preview
```
