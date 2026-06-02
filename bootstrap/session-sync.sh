#!/usr/bin/env bash
# Lightweight per-session refresh for Claude cloud sessions.
# Runs the FULL bootstrap only when there are fresh commits (or it never ran in
# this environment). On the common path (nothing changed) it costs a single cheap
# remote ref query and exits — no clone/install.
#
# Wire it via a SessionStart hook (see docs/cloud-setup.md). It assumes the repo
# was cloned by the cloud Setup script (default: $HOME/claude-plugin).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLIED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.jiechao-toolkit.sha"

# No git repo here → nothing to sync.
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Cheap: peek the remote branch head WITHOUT downloading objects.
# `|| true` so an unreachable/absent remote falls back to local instead of aborting under set -e.
remote_sha="$(git -C "$REPO" ls-remote origin -h refs/heads/main 2>/dev/null | cut -f1 || true)"
[ -n "$remote_sha" ] || remote_sha="$(git -C "$REPO" rev-parse HEAD)"   # offline → use local
applied_sha="$(cat "$APPLIED" 2>/dev/null || true)"

# Already current → skip the expensive install.
[ "$remote_sha" = "$applied_sha" ] && exit 0

# Fresh commits (or never applied in this environment): sync + reinstall, record SHA.
git -C "$REPO" fetch --quiet origin main && git -C "$REPO" merge --ff-only origin/main || true
"$REPO/bootstrap/install.sh" && git -C "$REPO" rev-parse HEAD > "$APPLIED"
