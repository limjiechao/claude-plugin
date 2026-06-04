#!/usr/bin/env bash
# Per-session refresh for Claude cloud sessions.
# Cheap path: one ls-remote ref query, exit if already current.
# Expensive path: mirror the remote (reset --hard, force-push-safe) + reinstall
# with a forced plugin-cache rebuild (the CLI's `plugin update` cannot be trusted
# to refresh a changed source — see anthropics/claude-code#37670).
# Assumes a disposable deploy checkout — NOTHING is authored here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLIED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.jiechao-toolkit.sha"

# Not a git checkout → nothing to sync.
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Resolve the tracked branch instead of hardcoding 'main', so a default-branch
# rename doesn't silently freeze updates forever.
BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's#^origin/##')"
[ -n "$BRANCH" ] || BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

# Cheap: peek the remote head WITHOUT downloading objects.
remote_sha="$(git -C "$REPO" ls-remote origin -h "refs/heads/$BRANCH" 2>/dev/null | cut -f1 || true)"
[ -n "$remote_sha" ] || remote_sha="$(git -C "$REPO" rev-parse HEAD)"   # offline → local
applied_sha="$(cat "$APPLIED" 2>/dev/null || true)"

# Already current → skip the expensive install.
[ "$remote_sha" = "$applied_sha" ] && exit 0

# --- Expensive path: a real refresh is warranted. ---

# Mirror the remote. reset --hard is robust to force-pushes / rewritten history
# (fixups, squashes, rearrangements) where merge --ff-only would fail.
# Deliberately NOT swallowed: if we can't sync, fail loudly rather than silently
# reinstall stale code.
if git -C "$REPO" ls-remote origin >/dev/null 2>&1; then
  git -C "$REPO" fetch --quiet --tags --prune --force origin
  git -C "$REPO" reset --hard "origin/$BRANCH"
fi

# Signal apply.sh that the source genuinely changed → it should bust the plugin
# cache instead of trusting `plugin update`. Record HEAD only on success, so a
# failed install retries next session instead of marking a broken state applied.
REFRESH_PLUGIN_CACHE=1 "$REPO/bootstrap/apply.sh" \
  && git -C "$REPO" rev-parse HEAD > "$APPLIED"