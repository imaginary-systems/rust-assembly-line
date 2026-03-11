# Git Worktree Skill

Provides isolated git worktree management for parallel feature development. Used by `/ral:work` to ensure all implementation happens in a clean, isolated copy of the repository.

## Why Worktrees?

Git worktrees allow multiple branches to be checked out simultaneously without the overhead of cloning the repository. Each worktree shares the same `.git` object store, making branching instant.

Benefits:
- Main branch stays clean while implementing features
- Multiple stories can be in-progress simultaneously in different worktrees
- Easy to compare implementations across branches
- Worktree can be deleted cleanly without affecting main repo

## Commands

### Create Worktree

```bash
# Naming convention: <repo-name>--<branch-slug>
REPO=$(basename $(git rev-parse --show-toplevel))
BRANCH="feat/RUST-56-add-user-auth"
SLUG=$(echo "$BRANCH" | tr '/' '-' | tr '_' '-')
WORKTREE="../${REPO}--${SLUG}"

git worktree add "$WORKTREE" -b "$BRANCH"
echo "Worktree created at: $WORKTREE"
echo "Branch: $BRANCH"
```

### List Active Worktrees

```bash
git worktree list
```

### Switch to Worktree

```bash
cd "$WORKTREE"
# All work in this session happens here
```

### Remove Worktree (after PR merged)

```bash
git worktree remove "$WORKTREE"
git branch -d "$BRANCH"
```

### Prune Stale Worktrees

```bash
git worktree prune
```

## Session Tracking

Save worktree state to `.claude/session/work-goal`:

```bash
mkdir -p .claude/session
cat > .claude/session/work-goal <<EOF
branch=$BRANCH
worktree=$WORKTREE
issue=RUST-56
crate=auth-service
EOF
```

Read session state:

```bash
source .claude/session/work-goal
echo "Resuming work on $issue in $worktree"
```

## Worktree Rules

1. **NEVER** commit directly to main/master
2. **ALWAYS** create a new branch for each Linear story
3. **ONE** worktree per story — don't mix multiple stories in one worktree
4. **CLEAN UP** worktrees after PRs are merged
5. **VERIFY** worktree was created before doing any implementation work

## Troubleshooting

**"fatal: '<path>' already exists"**
```bash
# Worktree already exists — either resume it or remove it first
git worktree list
git worktree remove <existing-path>
```

**"fatal: A branch named '<branch>' already exists"**
```bash
# Branch exists — check if there's already a PR
gh pr list --head "$BRANCH"
# If PR exists, use /ral:work --continue
# If not, the branch is orphaned — safe to recreate
git branch -D "$BRANCH"
git worktree add "$WORKTREE" -b "$BRANCH"
```

**Worktree is missing the latest main changes**
```bash
cd "$WORKTREE"
git fetch origin
git rebase origin/main
```
