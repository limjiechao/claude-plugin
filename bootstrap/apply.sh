#!/usr/bin/env bash
# Idempotent bootstrap: rebuilds the config layer into ~/.claude from this repo.
# Safe to run repeatedly, including at the start of an ephemeral cloud session.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$REPO_ROOT/bootstrap"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"
log(){ printf '\033[1;34m[apply]\033[0m %s\n' "$*"; }

command -v jq >/dev/null       || { echo "jq required"; exit 1; }
command -v python3 >/dev/null  || { echo "python3 required"; exit 1; }
command -v git >/dev/null      || { echo "git required"; exit 1; }

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR" "$AGENTS_DIR"

# Opt-outs (useful for re-merging settings only, or testing): SKIP_PLUGINS=1 SKIP_SKILLS=1
SKIP_PLUGINS="${SKIP_PLUGINS:-0}"
SKIP_SKILLS="${SKIP_SKILLS:-0}"

# 1) Own plugin: add this repo as a marketplace (local path → no GitHub slug needed) + install/update.
if [ "$SKIP_PLUGINS" != 1 ] && command -v claude >/dev/null; then
  log "registering own marketplace (local path)"
  claude plugin marketplace add "$REPO_ROOT" 2>/dev/null || log "  marketplace already known"
  if claude plugin details "jiechao-toolkit@claude-plugin" >/dev/null 2>&1; then
    log "updating jiechao-toolkit"
    claude plugin update "jiechao-toolkit@claude-plugin" 2>/dev/null || log "  update FAILED"
  else
    log "installing jiechao-toolkit"
    claude plugin install "jiechao-toolkit@claude-plugin" 2>/dev/null || log "  install FAILED"
  fi

  # 2) Third-party marketplaces + plugins from manifest.json.
  while IFS=$'\t' read -r name src; do
    log "marketplace: $name"
    claude plugin marketplace add "$src" 2>/dev/null || log "  already known"
  done < <(jq -r '.marketplaces[] | [.name,.source] | @tsv' "$BOOT/manifest.json")

  while read -r plugin; do
    [ -n "$plugin" ] || continue
    log "plugin: $plugin"
    claude plugin install "$plugin" 2>/dev/null || log "  already installed"
  done < <(jq -r '.plugins[]' "$BOOT/manifest.json")
elif [ "$SKIP_PLUGINS" = 1 ]; then
  log "SKIP_PLUGINS=1 — skipping marketplace/plugin install"
else
  log "WARN: 'claude' CLI not found — skipping plugin install (skills/agents/hooks/settings still applied)"
fi

# 3) Third-party skills from skills.lock.json (github clone or well-known fetch).
if [ "$SKIP_SKILLS" = 1 ]; then
  log "SKIP_SKILLS=1 — skipping third-party skill fetch"
else
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
jq -r '.skills | to_entries[] | [.key, .value.sourceType, (.value.sourceUrl // ""), (.value.skillPath // "")] | @tsv' \
   "$BOOT/skills.lock.json" | while IFS=$'\t' read -r key stype url spath; do
  dest="$SKILLS_DIR/$key"
  if [ "$stype" = "github" ]; then
    [ -n "$url" ] || { log "skip $key (no url)"; continue; }
    rm -rf "$TMP/$key"
    git clone --depth 1 "$url" "$TMP/$key" >/dev/null 2>&1 || { log "clone FAILED $key"; continue; }
    srcdir="$TMP/$key/$(dirname "$spath")"
    [ -d "$srcdir" ] || srcdir="$TMP/$key"
    rm -rf "$dest"; mkdir -p "$dest"
    ( cd "$srcdir" && tar cf - --exclude='.git' --exclude='.DS_Store' . ) | ( cd "$dest" && tar xf - )
    log "skill (git): $key"
  elif [ "$stype" = "well-known" ]; then
    [ -n "$url" ] || { log "skip $key (no url)"; continue; }
    mkdir -p "$dest"
    curl -fsSL "$url" -o "$dest/SKILL.md" && log "skill (well-known): $key" || log "fetch FAILED $key"
  else
    log "skip $key (unknown sourceType: $stype)"
  fi
done
fi

# 4) Agents: copy from repo, rewriting the @@HOOKS_DIR@@ token to the real hooks dir.
for a in "$BOOT"/agents/*.md; do
  sed "s#@@HOOKS_DIR@@#$HOOKS_DIR#g" "$a" > "$AGENTS_DIR/$(basename "$a")"
done
log "agents installed → $AGENTS_DIR"

# 5) Hooks: copy guard scripts.
for h in "$BOOT"/hooks/*.sh; do
  cp "$h" "$HOOKS_DIR/$(basename "$h")"; chmod +x "$HOOKS_DIR/$(basename "$h")"
done
log "hooks installed → $HOOKS_DIR"

# 6) Statusline: copy.
cp "$BOOT/statusline.sh" "$CLAUDE_DIR/statusline.sh"; chmod +x "$CLAUDE_DIR/statusline.sh"

# 7) Settings: back up, then deep-merge the snippet (repoint statusLine to absolute path).
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)" && log "backed up settings.json"
SNIPPET="$BOOT/settings.snippet.json" SETTINGS_PATH="$SETTINGS" CLAUDE_DIR="$CLAUDE_DIR" HOOKS_DIR="$HOOKS_DIR" python3 - <<'PY'
import json, os
settings_path=os.environ["SETTINGS_PATH"]; claude_dir=os.environ["CLAUDE_DIR"]; hooks_dir=os.environ["HOOKS_DIR"]
base=json.load(open(settings_path)) if os.path.exists(settings_path) else {}
snip=json.load(open(os.environ["SNIPPET"]))
def replace_tokens(value):
    if isinstance(value, str):
        return value.replace("@@HOOKS_DIR@@", hooks_dir).replace("@@CLAUDE_DIR@@", claude_dir)
    if isinstance(value, list):
        return [replace_tokens(item) for item in value]
    if isinstance(value, dict):
        return {key: replace_tokens(item) for key, item in value.items()}
    return value
def merge_lists(existing, incoming):
    seen=set()
    merged=[]
    for item in existing + incoming:
        key=json.dumps(item, sort_keys=True)
        if key not in seen:
            seen.add(key)
            merged.append(item)
    return merged
def deep_merge(a,b):
    for k,v in b.items():
        if isinstance(v,dict) and isinstance(a.get(k),dict): deep_merge(a[k],v)
        elif isinstance(v,list) and isinstance(a.get(k),list):
            a[k]=merge_lists(a[k],v)   # dedupe-preserving union
        else: a[k]=v
    return a
snip=replace_tokens(snip)
merged=deep_merge(base, snip)
merged["statusLine"]={"type":"command","command":f"bash {claude_dir}/statusline.sh"}
json.dump(merged, open(settings_path,"w"), indent=2)
print("settings merged ->", settings_path)
PY

log "done. Restart Claude Code to load plugins."
