#!/usr/bin/env bash
# Re-sync this repo FROM the live ~/.claude (local-first workflow).
# Pulls owner-authored skills, agents, hooks; regenerates skills.lock + settings snippet.
# After running, review `git diff` and commit.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
log(){ printf '\033[1;32m[capture]\033[0m %s\n' "$*"; }

OWN_SKILLS=(ansi-color-piping cross-platform-tests ink-useinput-bind no-barrel-files \
            package-public-api ssr-client-divergence tailwind-css-v4-usage \
            validating-stale-worktrees vertical-code-structure)

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
for a in edit git node python research shell; do
  [ -f "$CLAUDE_DIR/agents/$a.md" ] || continue
  sed "s#$CLAUDE_DIR/hooks#@@HOOKS_DIR@@#g; s#/Users/[^/]*/.claude/hooks#@@HOOKS_DIR@@#g" \
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
  SET_PATH="$SET" OUT="$REPO_ROOT/bootstrap/settings.snippet.json" python3 - <<'PY'
import json,os
s=json.load(open(os.environ["SET_PATH"]))
keep=["permissions","statusLine","inputNeededNotifEnabled","agentPushNotifEnabled","skipAutoPermissionPrompt"]
json.dump({k:s[k] for k in keep if k in s}, open(os.environ["OUT"],"w"), indent=2)
PY
fi
[ -f "$CLAUDE_DIR/statusline.sh" ] && cp "$CLAUDE_DIR/statusline.sh" "$REPO_ROOT/bootstrap/statusline.sh"
log "REGENERATED third-party skills lock + settings snippet + statusline."

log "Review 'git diff' and commit."