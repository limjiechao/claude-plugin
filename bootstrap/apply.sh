#!/usr/bin/env bash
# Idempotent bootstrap: rebuilds the config layer into ~/.claude from this repo.
# Safe to run repeatedly, including at the start of an ephemeral cloud session.
#
# Env:
#   SKIP_PLUGINS=1 / SKIP_SKILLS=1   opt-outs (re-merge settings only, testing)
#   REFRESH_PLUGIN_CACHE=1           force a clean plugin-cache rebuild from source
#                                    (set by session-sync.sh when upstream changed;
#                                     works around the CLI trusting a stale cache).
set -euo pipefail
shopt -s nullglob   # empty globs expand to nothing, not to a literal '*.md'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$REPO_ROOT/bootstrap"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"
MARKETPLACE="claude-plugin"
PLUGIN="jiechao-toolkit"
log(){ printf '\033[1;34m[apply]\033[0m %s\n' "$*"; }

command -v jq >/dev/null       || { echo "jq required"; exit 1; }
command -v python3 >/dev/null  || { echo "python3 required"; exit 1; }
command -v git >/dev/null      || { echo "git required"; exit 1; }

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR" "$AGENTS_DIR"

SKIP_PLUGINS="${SKIP_PLUGINS:-0}"
SKIP_SKILLS="${SKIP_SKILLS:-0}"
REFRESH_PLUGIN_CACHE="${REFRESH_PLUGIN_CACHE:-0}"

# 1) Own plugin + third-party marketplaces/plugins from manifest.json.
if [ "$SKIP_PLUGINS" != 1 ] && command -v claude >/dev/null; then

  # When upstream genuinely changed, the versioned plugin cache can shadow the
  # new source: `plugin update` may report "already at latest" and load stale
  # content (anthropics/claude-code#37670). Bust the cache so install rebuilds
  # from $REPO_ROOT. Scoped to OUR marketplace only — don't nuke third-party.
  if [ "$REFRESH_PLUGIN_CACHE" = 1 ]; then
    log "REFRESH_PLUGIN_CACHE=1 — clearing own plugin cache to force rebuild"
    rm -rf "$CLAUDE_DIR/plugins/cache/$MARKETPLACE" 2>/dev/null || true
  fi

  log "registering own marketplace (local path)"
  claude plugin marketplace add "$REPO_ROOT" 2>/dev/null || log "  marketplace already known"
  log "refreshing own marketplace"
  claude plugin marketplace update "$MARKETPLACE" || log "  marketplace refresh FAILED"

  # After a cache bust the plugin is gone, so prefer install; otherwise update.
  if claude plugin details "$PLUGIN@$MARKETPLACE" >/dev/null 2>&1; then
    log "updating $PLUGIN"
    claude plugin update "$PLUGIN@$MARKETPLACE" || log "  update FAILED"
  else
    log "installing $PLUGIN"
    claude plugin install "$PLUGIN@$MARKETPLACE" || log "  install FAILED"
  fi

  # Verify the cache actually reflects source. The CLI's exit code can't be
  # trusted here (#37670), so diff ground truth and warn loudly on drift.
  cachedir="$CLAUDE_DIR/plugins/cache/$MARKETPLACE/$PLUGIN"
  if [ -d "$cachedir" ]; then
    latest="$(ls -1t "$cachedir" 2>/dev/null | head -n1)"
    if [ -n "$latest" ] && ! diff -rq "$REPO_ROOT" "$cachedir/$latest" \
         --exclude=.git --exclude=node_modules >/dev/null 2>&1; then
      log "  WARN: cached plugin ($latest) DIFFERS from source — cache may be stale."
      log "        inspect: diff -rq \"$REPO_ROOT\" \"$cachedir/$latest\" --exclude=.git"
      log "        if intentional drift, ignore; otherwise rerun with REFRESH_PLUGIN_CACHE=1"
    fi
  fi

  # Third-party marketplaces + plugins from manifest.json.
  while IFS=$'\t' read -r name src; do
    log "marketplace: $name"
    claude plugin marketplace add "$src" 2>/dev/null || log "  already known"
  done < <(jq -r '.marketplaces[] | [.name,.source] | @tsv' "$BOOT/manifest.json")

  while read -r plugin; do
    [ -n "$plugin" ] || continue
    log "plugin: $plugin"
    claude plugin install "$plugin" 2>/dev/null || log "  already installed (or FAILED)"
  done < <(jq -r '.plugins[]' "$BOOT/manifest.json")

elif [ "$SKIP_PLUGINS" = 1 ]; then
  log "SKIP_PLUGINS=1 — skipping marketplace/plugin install"
else
  log "WARN: 'claude' CLI not found — skipping plugin install (skills/agents/hooks/settings still applied)"
fi

# 3) Third-party skills from skills.lock.json.
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
      if rm -rf "$dest" && mkdir -p "$dest" \
         && tar -C "$srcdir" -cf - --exclude='.git' --exclude='.DS_Store' . \
            | tar -C "$dest" -xf -; then
        log "skill (git): $key"
      else
        log "copy FAILED $key"; continue
      fi
    elif [ "$stype" = "well-known" ]; then
      [ -n "$url" ] || { log "skip $key (no url)"; continue; }
      mkdir -p "$dest"
      curl -fsSL "$url" -o "$dest/SKILL.md" && log "skill (well-known): $key" || log "fetch FAILED $key"
    else
      log "skip $key (unknown sourceType: $stype)"
    fi
  done
fi

# 4) Agents: copy, rewriting @@HOOKS_DIR@@ to the real hooks dir.
for a in "$BOOT"/agents/*.md; do
  sed "s#@@HOOKS_DIR@@#$HOOKS_DIR#g" "$a" > "$AGENTS_DIR/$(basename "$a")"
done
log "agents installed → $AGENTS_DIR"

# 5) Hooks.
for h in "$BOOT"/hooks/*.sh; do
  cp "$h" "$HOOKS_DIR/$(basename "$h")"; chmod +x "$HOOKS_DIR/$(basename "$h")"
done
log "hooks installed → $HOOKS_DIR"

# 6) Statusline.
cp "$BOOT/statusline.sh" "$CLAUDE_DIR/statusline.sh"; chmod +x "$CLAUDE_DIR/statusline.sh"

# 7) Settings: back up (pruned), then reconcile the snippet so the managed layer
#    reflects adds, EDITS, and REMOVES — not just a one-way union.
SETTINGS="$CLAUDE_DIR/settings.json"
LASTSNIP="$CLAUDE_DIR/.jiechao-last-snippet.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)" && log "backed up settings.json"
  ls -1t "$SETTINGS".bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f
fi
SNIPPET="$BOOT/settings.snippet.json" SETTINGS_PATH="$SETTINGS" LASTSNIP="$LASTSNIP" \
CLAUDE_DIR="$CLAUDE_DIR" HOOKS_DIR="$HOOKS_DIR" python3 - <<'PY'
import json, os
settings_path=os.environ["SETTINGS_PATH"]
claude_dir=os.environ["CLAUDE_DIR"]; hooks_dir=os.environ["HOOKS_DIR"]
lastsnip_path=os.environ["LASTSNIP"]

base = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
new_snip = json.load(open(os.environ["SNIPPET"]))
old_snip = json.load(open(lastsnip_path)) if os.path.exists(lastsnip_path) else {}

def replace_tokens(v):
    if isinstance(v, str):
        return v.replace("@@HOOKS_DIR@@", hooks_dir).replace("@@CLAUDE_DIR@@", claude_dir)
    if isinstance(v, list):  return [replace_tokens(x) for x in v]
    if isinstance(v, dict):  return {k: replace_tokens(x) for k, x in v.items()}
    return v

new_snip = replace_tokens(new_snip)
old_snip = replace_tokens(old_snip)

def key(item): return json.dumps(item, sort_keys=True)

def reconcile_list(existing, old_entries, new_entries):
    stale = {key(x) for x in old_entries} - {key(x) for x in new_entries}
    kept  = [x for x in existing if key(x) not in stale]
    seen, out = set(), []
    for x in kept + new_entries:
        k = key(x)
        if k not in seen:
            seen.add(k); out.append(x)
    return out

def reconcile(base_node, old_node, new_node):
    for k, v in new_node.items():
        ov = old_node.get(k) if isinstance(old_node, dict) else None
        if isinstance(v, dict) and isinstance(base_node.get(k), dict):
            reconcile(base_node[k], ov if isinstance(ov, dict) else {}, v)
        elif isinstance(v, list) and isinstance(base_node.get(k), list):
            base_node[k] = reconcile_list(base_node[k], ov if isinstance(ov, list) else [], v)
        else:
            base_node[k] = v
    return base_node

merged = reconcile(base, old_snip, new_snip)
merged["statusLine"] = {"type": "command", "command": f"bash {claude_dir}/statusline.sh"}

json.dump(merged, open(settings_path, "w"), indent=2)
json.dump(json.load(open(os.environ["SNIPPET"])), open(lastsnip_path, "w"), indent=2)
print("settings reconciled ->", settings_path)
PY

log "done. Restart Claude Code to load plugins."