#!/usr/bin/env bash
# Re-sync this repo FROM the live ~/.claude (local-first workflow).
# Pulls owner-authored skills, agents, hooks; regenerates skills.lock + settings snippet.
# After running, review `git diff` and commit.
set -euo pipefail
# CAPTURE_REPO_ROOT lets tests redirect output to a scratch repo; defaults to the
# real repo root (this script lives in scripts/).
REPO_ROOT="${CAPTURE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
log(){ printf '\033[1;32m[capture]\033[0m %s\n' "$*"; }

# Owner's skills are DEFINED by the repo plugin dir; capture re-pulls each from
# ~/.claude. Third-party skills also live in ~/.claude but never here, so the
# repo set is the authoritative "mine" list and can never go stale.
OWN_SKILLS=()
for d in "$REPO_ROOT/plugins/jiechao-toolkit/skills"/*/; do
  [ -d "$d" ] || continue
  OWN_SKILLS+=("$(basename "$d")")
done

# 1) Own skills → plugin (skip symlinks = third-party; eval fixtures are gitignored).
log "SYNCING own skills"
for s in "${OWN_SKILLS[@]}"; do
  src="$CLAUDE_DIR/skills/$s"
  if [ ! -d "$src" ]; then log "Skipping $s (not a skill directory)"; continue; fi
  if [ -L "$src" ]; then log "Skipping $s (is a symlink)"; continue; fi
  dest="$REPO_ROOT/plugins/jiechao-toolkit/skills/$s"
  rm -rf "$dest"; mkdir -p "$dest"
  ( cd "$src" && tar cf - --exclude='.git' --exclude='.DS_Store' . ) | ( cd "$dest" && tar xf - )
done
log "SYNCED own skills"

# 2) Agents (tokenize hook paths) + hooks.
log "SYNCING agents + hooks"
mkdir -p "$REPO_ROOT/bootstrap/agents" "$REPO_ROOT/bootstrap/hooks"
for af in "$REPO_ROOT/bootstrap/agents"/*.md; do
  [ -e "$af" ] || continue
  a="$(basename "$af" .md)"
  [ -f "$CLAUDE_DIR/agents/$a.md" ] || continue
  sed "s#$CLAUDE_DIR/hooks#@@HOOKS_DIR@@#g; s#/Users/[^/]*/.claude/hooks#@@HOOKS_DIR@@#g; s#/home/[^/]*/\.claude/hooks#@@HOOKS_DIR@@#g" \
      "$CLAUDE_DIR/agents/$a.md" > "$REPO_ROOT/bootstrap/agents/$a.md"
done
for h in git-guard path-guard runner-only shell-guard; do
  [ -f "$CLAUDE_DIR/hooks/$h.sh" ] && cp "$CLAUDE_DIR/hooks/$h.sh" "$REPO_ROOT/bootstrap/hooks/$h.sh"
done
log "SYNCED agents + hooks"

# 3) Regenerate third-party skills lock + settings snippet + statusline.
log "REGENERATING third-party skills lock + settings snippet + statusline"
[ -f "$HOME/.agents/.skill-lock.json" ] && cp "$HOME/.agents/.skill-lock.json" "$REPO_ROOT/bootstrap/skills.lock.json"
SET="$CLAUDE_DIR/settings.json"
if [ -f "$SET" ]; then
  SET_PATH="$SET" OUT="$REPO_ROOT/bootstrap/settings.snippet.json" CLAUDE_DIR="$CLAUDE_DIR" python3 - <<'PY'
import json, os, re
s = json.load(open(os.environ["SET_PATH"]))
# NOTE: "hooks" MUST be kept — it carries the global git-guard PreToolUse hook.
# Omitting it would silently delete the guard from the repo on the next capture.
keep = ["permissions", "hooks", "statusLine", "inputNeededNotifEnabled",
        "agentPushNotifEnabled", "skipAutoPermissionPrompt"]
out = {k: s[k] for k in keep if k in s}
text = json.dumps(out, indent=2)
cd = os.environ["CLAUDE_DIR"].rstrip("/")
# Re-tokenize expanded hook paths so the committed snippet stays portable.
text = text.replace(cd + "/hooks", "@@HOOKS_DIR@@")
text = re.sub(r"/Users/[^/\"]+/\.claude/hooks", "@@HOOKS_DIR@@", text)
text = re.sub(r"/home/[^/\"]+/\.claude/hooks", "@@HOOKS_DIR@@", text)
open(os.environ["OUT"], "w").write(text)
PY
fi
[ -f "$CLAUDE_DIR/statusline.sh" ] && cp "$CLAUDE_DIR/statusline.sh" "$REPO_ROOT/bootstrap/statusline.sh"
log "REGENERATED third-party skills lock + settings snippet + statusline."

log "Review 'git diff' and commit."