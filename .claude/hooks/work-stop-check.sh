#!/usr/bin/env bash
# RAL Work Session Guard
# Runs when Claude Code stops. Reminds the user if there is in-progress work
# with no PR yet, so they know to continue with /ral:work --continue.

SESSION_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/session/work-goal"

if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

BRANCH=""
ISSUE=""
CRATE=""

while IFS='=' read -r key value; do
  case "$key" in
    branch) BRANCH="$value" ;;
    issue)  ISSUE="$value" ;;
    crate)  CRATE="$value" ;;
  esac
done < "$SESSION_FILE"

if [ -z "$BRANCH" ] || [ -z "$ISSUE" ]; then
  exit 0
fi

# Check if a PR exists for this branch
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || true)

if [ -n "$PR_NUMBER" ]; then
  # PR exists — work is done
  echo "ℹ  $ISSUE: PR #$PR_NUMBER exists. Work complete."
  exit 0
fi

# No PR yet — remind the user
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ⚠  Work in progress — no PR created yet            ║"
echo "║                                                      ║"
echo "║  Story:  $ISSUE"
echo "║  Branch: $BRANCH"
if [ -n "$CRATE" ]; then
echo "║  Crate:  $CRATE"
fi
echo "║                                                      ║"
echo "║  To continue: /ral:work --continue                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

exit 0
