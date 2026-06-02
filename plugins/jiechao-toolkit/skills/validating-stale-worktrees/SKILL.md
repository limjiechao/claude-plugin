---
name: validating-stale-worktrees
description: >-
  Use this when you encounter "fatal: cannot remove a locked working tree",
  "Cannot delete branch X checked out at", or any situation where git worktrees /
  branches from agent sessions, feature work, or completed PRs refuse to delete.
  Also use when the user wants to clean up worktrees after rebasing /
  squash-merging / fixup commits — even when commit SHAs no longer match, this
  skill proves whether each branch's work has actually been absorbed into the
  integration branch (main / master / develop) by comparing patch-ids, subjects,
  files-touched, and shortstats. It then drafts the exact removal sequence and
  asks permission before running anything destructive. Trigger this skill
  aggressively whenever a worktree won't go away — the gotchas (lock files
  needing double `-f`, the strict ordering of worktree-remove before
  branch-delete) trip people up every time.
---

# Validating stale worktrees before cleanup

## The recurring problem

A repository accumulates worktrees from past agent sessions, feature work, or PRs that have since merged. The user wants to clean them up but hits a wall:

- `git worktree remove .claude/worktrees/foo` → `fatal: cannot remove a locked working tree`
- `git worktree remove --force ...` → `fatal: cannot remove a locked working tree, lock reason: ...` *(single `--force` doesn't override locks)*
- `git branch -D worktree-foo` → `Cannot delete branch 'worktree-foo' checked out at '...'`
- After rebase/squash-merge, `git cherry main worktree-foo` shows `+` commits that **look** unmerged but actually landed under different SHAs.

The user (reasonably) doesn't want to run `rm -rf` on a worktree if it might still hold unmerged work. So they ask: *are these safe to remove?*

This skill answers that question rigorously, then issues the cleanup commands.

## When to fire

Fire on any of these signals:

- Error text: `cannot remove a locked working tree`, `Cannot delete branch ... checked out at`, `worktree is locked`
- Phrasing: "stale worktrees", "clean up worktrees", "remove these worktrees", "agent worktrees won't delete", "branches from old agent sessions", "after rebasing / squash-merging"
- Directory mentions matching `.claude/worktrees/agent-*`, `.git/worktrees/`, `*.worktrees`
- Any reference to `git worktree`, `worktree remove`, `worktree lock`, `worktree prune` paired with a problem

When in doubt, fire — the underlying analysis is cheap and the cleanup gotchas are non-obvious.

## Why the naive approach fails

Two surprising behaviours combine to make this annoying:

1. **`git worktree remove --force` (single `-f`) does NOT override locks.** It only overrides dirty trees. You need either `-f -f` (double force) or an explicit `git worktree unlock <path>` first. The error message ("use `remove -f -f` to override or unlock first") tells you, but only after you've already typed the wrong command.

2. **`git branch -D` refuses to delete a branch that's checked out by *any* worktree, with no flag override.** The deletion has to wait until the worktree itself is unregistered. This is by design: deleting a checked-out branch would leave that worktree's HEAD pointing at a phantom.

→ Correct order is *always*: **unlock (or `-f -f`) → remove worktree → prune → branch -D**.

Plus a third gotcha worth knowing:

3. **`git cherry main <branch>` is rebase-aware but not squash-aware.** It uses patch-ids, so a commit rebased onto a new base still matches its twin. But a squash that combines three commits into one will show all three as `+` (unmatched) even though their content is in main. So you can't trust `+` lines alone — they're a *starting point* for investigation, not a verdict.

## The validation procedure

Work through this in order. The goal is to either (a) prove every "+" commit on every branch has a content-equivalent twin on the integration branch, so the worktrees are safe to remove, or (b) identify the specific commit(s) that are genuinely orphaned so the user can decide what to do.

### Step 1 — Inventory

```sh
git worktree list
```

Note which worktrees the user wants cleaned up, which are locked, and what branch each holds. The lock reason lives at `.git/worktrees/<name>/locked` — read it to see whether the locking process is alive:

```sh
for wt in <worktree-names>; do
  echo "=== $wt ==="
  cat .git/worktrees/$wt/locked 2>/dev/null || echo "(no lock)"
done
```

If the lock references a pid, check `ps -p <pid>` — a dead pid means the lock is stale and safe to clear once content validation passes.

### Step 2 — Confirm working trees are clean

A clean tree is non-negotiable. Uncommitted work in a worktree is a hard stop.

```sh
for wt in <worktree-names>; do
  echo "=== $wt ==="
  git -C .claude/worktrees/$wt status --porcelain
done
```

Any non-empty output → flag that worktree and refuse to touch it until the user handles the dirty files.

### Step 3 — Determine the integration branch

Usually `main`, sometimes `master` or `develop`. If unclear, ask the user or detect:

```sh
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null  # often refs/remotes/origin/main
```

Use the local copy of that branch as the comparison target. Throughout this skill the placeholder is `<base>` (substitute `main` or whatever the user uses).

### Step 4 — List orphan commits per branch

```sh
for wt in <worktree-names>; do
  echo "=== $wt ==="
  git cherry <base> "worktree-$wt" -v | grep '^+' | while read sign sha rest; do
    echo "  $sha $(git log --format='%s' -1 $sha)"
  done
done
```

Each `+` line is a commit whose patch-id is not present on `<base>`. **This is the starting list, not the conclusion.**

### Step 5 — For each orphan, find the twin on the integration branch

This is the heart of the skill. The trick is that rebase / fixup / squash changes the SHA but typically preserves the commit subject. Search `<base>` for matching subjects and referenced issue/PR numbers:

```sh
git log <base> --oneline --grep="<exact-or-near-exact-subject>"
git log <base> --oneline --grep="#<issue-number>"
```

For each orphan, you should expect one of three outcomes:

- **Subject-identical commit exists on `<base>`** → likely landed via rebase or cherry-pick. Move to Step 6 to verify content.
- **A commit on `<base>` references the same issue/PR number with a similar subject** → likely landed via squash-merge, which rewrites the subject (`feat(x): ... (#123)` style). Move to Step 6.
- **Nothing found** → genuinely orphan. This worktree is **not** safe to delete blindly; report it.

### Step 6 — Verify the twin is content-equivalent

For each orphan-and-twin pair, compare four signals. The more that agree, the higher the confidence the work has truly landed:

```sh
# 1. Files-touched (sorted)
diff \
  <(git show --pretty='' --name-only <branch-sha> | sort) \
  <(git show --pretty='' --name-only <main-sha>   | sort)

# 2. Shortstat (files / insertions / deletions)
git show --pretty='' --shortstat <branch-sha>
git show --pretty='' --shortstat <main-sha>

# 3. Patch-id (stable hash of the patch content)
git show <branch-sha> | git patch-id --stable | awk '{print $1}'
git show <main-sha>   | git patch-id --stable | awk '{print $1}'

# 4. Raw +/- line delta between the two patches
diff \
  <(git show <branch-sha> | grep -E '^[+-]' | grep -v '^[+-]\{3\}') \
  <(git show <main-sha>   | grep -E '^[+-]' | grep -v '^[+-]\{3\}') | wc -l
```

Interpret the results:

| Signal pattern | Verdict |
|---|---|
| Files identical, shortstat identical, patch-ids match | **Landed verbatim.** Highest confidence. |
| Files identical, shortstat identical, patch-ids differ, raw delta ≤ ~10 lines | **Landed via rebase.** Differences are context-line shifts. |
| Files identical, shortstat close (±5 lines), patch-ids differ, raw delta 10–50 lines | **Landed with minor refinements.** Common when reviewer asked for small tweaks before merge. Acceptable. |
| Files identical, shortstat very different (or one commit missing whole files) | **Partially landed or significantly modified.** Report the delta; let the user decide. |
| Files differ significantly OR no twin found | **Orphan.** Do NOT remove this worktree until resolved. |

### Step 7 — Cross-branch deduplication

When the same change has been rebased into multiple agent branches, you'll see the *exact same patch-id* across branches. That's a useful sanity signal — confirms it's the same logical change appearing in multiple worktrees. Mention this in the report so the user can see the pattern.

### Step 8 — Produce the per-worktree verdict table

Summarise each worktree as **CLEAR** (every orphan accounted for) or **HOLD** (orphans missing or partial). A table makes this easy to scan:

```
| worktree | orphan commits | accounted for? |
|---|---|---|
| agent-foo | 3 | YES (all 3 landed on main as ...) |
| agent-bar | 2 | NO — commit abc1234 has no twin |
```

## Issuing the cleanup commands

### When all worktrees are CLEAR

Present the commands in the correct order, explain each step, and **ask for permission** before running anything destructive. Don't just run it because the validation passed — the user explicitly framed cleanup as a permission gate.

Template:

```sh
cd <repo-root>

# Step 1 — unlock + remove each worktree (single block; -f -f handles both
# the stale lock and any residual state)
for wt in <worktree-names>; do
  git worktree remove -f -f ".claude/worktrees/$wt"
done

# Step 2 — clear any leftover admin entries under .git/worktrees/
git worktree prune

# Step 3 — now the branches are no longer "checked out anywhere",
# so plain -D works
git branch -D \
  worktree-<wt1> \
  worktree-<wt2> \
  ...
```

Explain in plain words what will happen:

- *"`git worktree remove -f -f` deletes the worktree directory AND unregisters it from `.git/worktrees/`, overriding the stale lock files. No commits are touched — branches are still there afterward."*
- *"`git worktree prune` is a safety net that clears any orphaned admin entries (e.g. if the directory was manually removed before the worktree was unregistered)."*
- *"`git branch -D` then deletes the branch refs. Because we've already proved every commit on each branch has a twin on `<base>`, no work is lost."*

Then ask: *"Shall I run this, or do you want to run it yourself?"*

### When one or more worktrees are HOLD

Do NOT issue a bulk command. Report the specific orphan commits and what they touch, then offer next steps:

1. **Cherry-pick the missing work into a feature branch** (then this skill can re-run and confirm the worktree is now clear).
2. **Open the worktree manually and inspect** (`cd <path> && git log <base>..HEAD`).
3. **Decide the work is intentionally being dropped** — in which case the user can override with `git worktree remove -f -f` knowing what they're losing.

Be explicit: don't soft-pedal "probably stale" verdicts. If the data says HOLD, say HOLD.

## Edge cases

- **A worktree's branch tip is far behind `<base>`.** Common when the branch was made weeks ago. The cherry analysis still works — `git cherry <base> <branch>` ignores commits that are on both sides.
- **A worktree's `.git/worktrees/<name>/locked` file is missing but `git worktree list` says "locked".** Means there's a stale lock state somewhere else; `git worktree unlock <path>` resolves it.
- **The branch name doesn't follow the `worktree-<name>` convention.** Read the branch name from `git worktree list` rather than assuming.
- **`git worktree remove` fails after `-f -f` with a different error.** Usually means filesystem permission issues or the directory has files held open by another process. Investigate `lsof +D <path>` on macOS/Linux.
- **The integration branch was rewritten** (force-pushed `<base>`). All bets are off — neither patch-id nor subject matching is reliable. Tell the user to re-fetch and re-establish a stable baseline before running this skill.
- **No remote / detached HEAD repo.** The procedure still works; just compare against whatever local branch the user treats as the integration target.

## Why each step matters

- **Patch-id alone is insufficient** because squash/fixup combine multiple patches into one, defeating patch-id matching. Subject and files-touched comparison catches those cases.
- **Subject alone is insufficient** because two commits can share a subject by coincidence, or a rebased commit can diverge in content. Comparing shortstat and patch text confirms the change is actually the same.
- **Asking permission before destruction** is the user's explicit ask in the framing of this skill. The validation step proves *that* removal is safe; the permission step respects *who decides* to remove.

## Quick reference — command cheatsheet

| Situation | Command |
|---|---|
| Inspect locks | `cat .git/worktrees/<wt>/locked` |
| Find live process holding the lock | `ps -p <pid>` |
| List orphan commits | `git cherry <base> <branch> -v \| grep '^+'` |
| Find twin by subject | `git log <base> --oneline --grep="<subject>"` |
| Compare patches | `git patch-id --stable < <(git show <sha>)` |
| Unlock then remove | `git worktree unlock <path> && git worktree remove --force <path>` |
| Force-unlock + remove in one shot | `git worktree remove -f -f <path>` |
| Clear orphan admin entries | `git worktree prune` |
| Delete branches | `git branch -D <branch1> <branch2> ...` (only after worktree is gone) |
