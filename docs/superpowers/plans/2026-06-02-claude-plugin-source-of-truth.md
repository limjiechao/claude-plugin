# claude-plugin Source-of-Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `~/Documents/claude-plugin` — a public git repo that is the single source of truth for the owner's personal Claude tooling (skills, subagents, hooks, settings, third-party plugins/skills), reproducible locally and in Claude cloud sessions.

**Architecture:** Two layers. **Layer A** is a Claude plugin (`jiechao-toolkit`) delivering the owner's 9 authored *skills* via a co-located marketplace. **Layer B** (`bootstrap/`) is a declarative set re-installed by an idempotent `install.sh`: third-party plugins (via `claude plugin` CLI), third-party skills (clone/fetch + copy), the 6 subagents + 4 guard hooks (copied into `~/.claude` because **plugin-bundled subagents ignore `hooks`/`permissionMode`**), and portable settings incl. a centralized statusline (deep-merged).

**Tech Stack:** Claude Code plugins/marketplaces, `claude plugin` CLI, bash, `jq`, `python3` (JSON merge), git.

**Key constraints discovered:**
- Plugin subagents ignore `hooks`, `mcpServers`, `permissionMode` (security). → agents/hooks delivered via `install.sh` into `~/.claude`, NOT the plugin. ([sub-agents.md](https://code.claude.com/docs/en/sub-agents.md))
- `${CLAUDE_PLUGIN_ROOT}` is valid in plugin.json/.mcp.json, NOT marketplace.json plugin entries, NOT reliably in agent frontmatter. Agent hook paths use a `@@HOOKS_DIR@@` token rewritten at install time.
- Co-located plugin `source` is a `./plugins/<name>` path relative to marketplace root.
- Never hand-edit `~/.claude/plugins/{known_marketplaces,installed_plugins}.json`; use the CLI.
- `cross-platform-tests-workspace` is iteration scratch (no SKILL.md) → excluded.

---

## File structure

```
claude-plugin/
├── .gitignore
├── .claude-plugin/marketplace.json          # marketplace: 1 plugin, co-located
├── plugins/jiechao-toolkit/
│   ├── .claude-plugin/plugin.json
│   └── skills/<9 own skills>/…              # copied from ~/.claude/skills
├── bootstrap/
│   ├── manifest.json                        # marketplaces + plugins for CLI install
│   ├── skills.lock.json                     # copy of ~/.agents/.skill-lock.json (34)
│   ├── settings.snippet.json                # portable settings (extracted)
│   ├── statusline.sh                        # copied from ~/.claude/statusline.sh
│   ├── agents/<6>.md                        # copied; hook paths → @@HOOKS_DIR@@
│   ├── hooks/<4>.sh                          # copied verbatim
│   └── install.sh                           # idempotent bootstrapper
├── scripts/export.sh                        # re-sync repo FROM live ~/.claude
├── README.md  CLAUDE.md  docs/…             # already written; corrected in Task 12
```

---

## Task 1: Initialize repo + .gitignore

**Files:** Create: `.gitignore`; init git in `/Users/jiechao/Documents/claude-plugin`.

- [ ] **Step 1: Initialize git**

Run: `cd /Users/jiechao/Documents/claude-plugin && git init -b main`
Expected: `Initialized empty Git repository …`

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
*.log
/tmp/
node_modules/
# scratch HOME used for install dry-runs
/.scratch-home/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore README.md CLAUDE.md docs/
git commit -m "chore: init repo with docs and gitignore"
```
Expected: commit created (docs from prior step are included).

---

## Task 2: Marketplace manifest (Layer A)

**Files:** Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write `.claude-plugin/marketplace.json`**

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "claude-plugin",
  "description": "jiechao personal single source of truth — authored skills",
  "owner": { "name": "jiechao", "email": "jiechao.lim@gmail.com" },
  "metadata": { "pluginRoot": "./plugins" },
  "plugins": [
    {
      "name": "jiechao-toolkit",
      "source": "jiechao-toolkit",
      "description": "Personal authored skills (ansi-color-piping, cross-platform-tests, ink-useinput-bind, no-barrel-files, package-public-api, ssr-client-divergence, tailwind-css-v4-usage, validating-stale-worktrees, vertical-code-structure)",
      "category": "productivity"
    }
  ]
}
```

- [ ] **Step 2: Validate JSON parses**

Run: `python3 -c "import json;json.load(open('.claude-plugin/marketplace.json'));print('ok')"`
Expected: `ok`

---

## Task 3: Plugin manifest (Layer A)

**Files:** Create: `plugins/jiechao-toolkit/.claude-plugin/plugin.json`

- [ ] **Step 1: Write `plugins/jiechao-toolkit/.claude-plugin/plugin.json`**

```json
{
  "$schema": "https://anthropic.com/claude-code/plugin.schema.json",
  "name": "jiechao-toolkit",
  "version": "0.1.0",
  "description": "jiechao personal authored skills",
  "author": { "name": "jiechao", "email": "jiechao.lim@gmail.com" }
}
```

- [ ] **Step 2: Validate**

Run: `python3 -c "import json;json.load(open('plugins/jiechao-toolkit/.claude-plugin/plugin.json'));print('ok')"`
Expected: `ok`

---

## Task 4: Copy the 9 authored skills into the plugin

**Files:** Create: `plugins/jiechao-toolkit/skills/<name>/…` (9 dirs)

- [ ] **Step 1: Copy each skill (excluding the workspace dup), stripping .DS_Store**

```bash
mkdir -p plugins/jiechao-toolkit/skills
for s in ansi-color-piping cross-platform-tests ink-useinput-bind no-barrel-files \
         package-public-api ssr-client-divergence tailwind-css-v4-usage \
         validating-stale-worktrees vertical-code-structure; do
  rsync -a --exclude='.DS_Store' "$HOME/.claude/skills/$s/" "plugins/jiechao-toolkit/skills/$s/"
done
find plugins/jiechao-toolkit/skills -name '.DS_Store' -delete
```

- [ ] **Step 2: Verify all 9 have a SKILL.md**

Run:
```bash
for s in ansi-color-piping cross-platform-tests ink-useinput-bind no-barrel-files \
         package-public-api ssr-client-divergence tailwind-css-v4-usage \
         validating-stale-worktrees vertical-code-structure; do
  test -f "plugins/jiechao-toolkit/skills/$s/SKILL.md" && echo "ok $s" || echo "MISSING $s"
done
```
Expected: 9 lines, all `ok …`, no `MISSING`.

- [ ] **Step 3: Confirm no absolute user paths leaked into skills**

Run: `grep -rl "/Users/jiechao" plugins/jiechao-toolkit/skills || echo "clean"`
Expected: `clean` (if any match, inspect; skills should be path-agnostic).

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin plugins
git commit -m "feat(plugin): jiechao-toolkit marketplace + 9 authored skills"
```

---

## Task 5: Validate the plugin with the CLI

- [ ] **Step 1: Validate the plugin**

Run: `claude plugin validate plugins/jiechao-toolkit`
Expected: validation passes (no errors). If it complains about the marketplace, also run `claude plugin validate .` from repo root.

- [ ] **Step 2: Validate the marketplace**

Run: `claude plugin validate .claude-plugin/marketplace.json` (or `claude plugin validate .`)
Expected: passes. Fix any reported schema issues inline before continuing.

---

## Task 6: Bootstrap — third-party plugin manifest

**Files:** Create: `bootstrap/manifest.json`

- [ ] **Step 1: Write `bootstrap/manifest.json`**

```json
{
  "marketplaces": [
    { "name": "claude-plugins-official", "source": "anthropics/claude-plugins-official" }
  ],
  "plugins": [
    "frontend-design@claude-plugins-official",
    "superpowers@claude-plugins-official",
    "code-review@claude-plugins-official",
    "skill-creator@claude-plugins-official",
    "claude-code-setup@claude-plugins-official",
    "code-simplifier@claude-plugins-official",
    "claude-md-management@claude-plugins-official",
    "feature-dev@claude-plugins-official",
    "typescript-lsp@claude-plugins-official",
    "ralph-loop@claude-plugins-official",
    "commit-commands@claude-plugins-official"
  ]
}
```

- [ ] **Step 2: Validate**

Run: `python3 -c "import json;d=json.load(open('bootstrap/manifest.json'));assert len(d['plugins'])==11;print('ok',len(d['plugins']))"`
Expected: `ok 11`

---

## Task 7: Bootstrap — third-party skills lock + settings snippet + statusline

**Files:** Create: `bootstrap/skills.lock.json`, `bootstrap/settings.snippet.json`, `bootstrap/statusline.sh`

- [ ] **Step 1: Snapshot the skill lock**

```bash
mkdir -p bootstrap
cp "$HOME/.agents/.skill-lock.json" bootstrap/skills.lock.json
python3 -c "import json;d=json.load(open('bootstrap/skills.lock.json'));print('skills:',len(d['skills']))"
```
Expected: `skills: 34`

- [ ] **Step 2: Extract portable settings (no enabledPlugins — CLI manages those)**

```bash
python3 - <<'PY'
import json
s=json.load(open(f"{__import__('os').environ['HOME']}/.claude/settings.json"))
keep=["permissions","statusLine","inputNeededNotifEnabled","agentPushNotifEnabled","skipAutoPermissionPrompt"]
out={k:s[k] for k in keep if k in s}
json.dump(out, open("bootstrap/settings.snippet.json","w"), indent=2)
print("keys:", list(out))
PY
```
Expected: `keys: ['permissions', 'statusLine', 'inputNeededNotifEnabled', 'agentPushNotifEnabled', 'skipAutoPermissionPrompt']`

- [ ] **Step 3: Snapshot the statusline script**

```bash
cp "$HOME/.claude/statusline.sh" bootstrap/statusline.sh
chmod +x bootstrap/statusline.sh
head -1 bootstrap/statusline.sh
```
Expected: a shebang line (e.g. `#!/usr/bin/env bash` or `#!/bin/bash`).

- [ ] **Step 4: Confirm settings.snippet statusLine points at the centralized script**

Run: `python3 -c "import json;print(json.load(open('bootstrap/settings.snippet.json'))['statusLine'])"`
Expected: shows a command referencing `statusline.sh` (install.sh will repoint it to `\$HOME/.claude/statusline.sh`).

---

## Task 8: Bootstrap — copy subagents (tokenized) + guard hooks

**Files:** Create: `bootstrap/agents/<6>.md`, `bootstrap/hooks/<4>.sh`

- [ ] **Step 1: Copy hooks verbatim**

```bash
mkdir -p bootstrap/hooks
for h in git-guard path-guard runner-only shell-guard; do
  cp "$HOME/.claude/hooks/$h.sh" "bootstrap/hooks/$h.sh"
  chmod +x "bootstrap/hooks/$h.sh"
done
ls bootstrap/hooks
```
Expected: `git-guard.sh path-guard.sh runner-only.sh shell-guard.sh`

- [ ] **Step 2: Copy agents, rewriting hook paths to the `@@HOOKS_DIR@@` token**

```bash
mkdir -p bootstrap/agents
for a in edit git node python research shell; do
  sed 's#/Users/jiechao/.claude/hooks#@@HOOKS_DIR@@#g' \
      "$HOME/.claude/agents/$a.md" > "bootstrap/agents/$a.md"
done
```

- [ ] **Step 3: Verify no absolute user path remains, token present where expected**

Run:
```bash
echo "absolute paths (want: none):"; grep -rl "/Users/jiechao" bootstrap/agents || echo none
echo "tokenized agents (want 5: edit git node python shell):"; grep -l "@@HOOKS_DIR@@" bootstrap/agents/*.md
```
Expected: `none`; then 5 files listed (research has no hook).

- [ ] **Step 4: Commit Layer B static assets**

```bash
git add bootstrap
git commit -m "feat(bootstrap): manifest, skills lock, settings snippet, statusline, agents+hooks"
```

---

## Task 9: Write `bootstrap/install.sh`

**Files:** Create: `bootstrap/install.sh`

- [ ] **Step 1: Write the script**

```bash
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
log(){ printf '\033[1;34m[install]\033[0m %s\n' "$*"; }

command -v jq >/dev/null       || { echo "jq required"; exit 1; }
command -v python3 >/dev/null  || { echo "python3 required"; exit 1; }
command -v git >/dev/null      || { echo "git required"; exit 1; }

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR" "$AGENTS_DIR"

# 1) Own plugin: add this repo as a marketplace (local path → no GitHub slug needed) + install.
log "registering own marketplace (local path)"
claude plugin marketplace add "$REPO_ROOT" 2>/dev/null || log "  marketplace already known"
log "installing jiechao-toolkit"
claude plugin install "jiechao-toolkit@claude-plugin" 2>/dev/null || log "  already installed"

# 2) Third-party marketplaces + plugins from manifest.json.
while IFS=$'\t' read -r name src; do
  log "marketplace: $name"
  claude plugin marketplace add "$src" 2>/dev/null || log "  already known"
done < <(jq -r '.marketplaces[] | [.name,.source] | @tsv' "$BOOT/manifest.json")

while read -r plugin; do
  log "plugin: $plugin"
  claude plugin install "$plugin" 2>/dev/null || log "  already installed"
done < <(jq -r '.plugins[]' "$BOOT/manifest.json")

# 3) Third-party skills from skills.lock.json (github clone or well-known fetch).
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
    rsync -a --exclude='.git' --exclude='.DS_Store' "$srcdir/" "$dest/"
    log "skill (git): $key"
  elif [ "$stype" = "well-known" ]; then
    [ -n "$url" ] || { log "skip $key (no url)"; continue; }
    mkdir -p "$dest"
    curl -fsSL "$url" -o "$dest/SKILL.md" && log "skill (well-known): $key" || log "fetch FAILED $key"
  else
    log "skip $key (unknown sourceType: $stype)"
  fi
done

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

# 6) Statusline: copy + repoint settings statusLine command at it.
cp "$BOOT/statusline.sh" "$CLAUDE_DIR/statusline.sh"; chmod +x "$CLAUDE_DIR/statusline.sh"

# 7) Settings: back up, then deep-merge the snippet (repoint statusLine to absolute path).
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)" && log "backed up settings.json"
SNIPPET="$BOOT/settings.snippet.json" SETTINGS_PATH="$SETTINGS" CLAUDE_DIR="$CLAUDE_DIR" python3 - <<'PY'
import json, os
settings_path=os.environ["SETTINGS_PATH"]; claude_dir=os.environ["CLAUDE_DIR"]
base=json.load(open(settings_path)) if os.path.exists(settings_path) else {}
snip=json.load(open(os.environ["SNIPPET"]))
def deep_merge(a,b):
    for k,v in b.items():
        if isinstance(v,dict) and isinstance(a.get(k),dict): deep_merge(a[k],v)
        elif isinstance(v,list) and isinstance(a.get(k),list):
            a[k]=list(dict.fromkeys(a[k]+v))   # dedupe-preserving union
        else: a[k]=v
    return a
merged=deep_merge(base, snip)
merged.setdefault("statusLine",{})
merged["statusLine"]={"type":"command","command":f"bash {claude_dir}/statusline.sh"}
json.dump(merged, open(settings_path,"w"), indent=2)
print("settings merged ->", settings_path)
PY

log "done. Restart Claude Code to load plugins."
```

- [ ] **Step 2: Make executable + shellcheck-parse**

```bash
chmod +x bootstrap/install.sh
bash -n bootstrap/install.sh && echo "syntax ok"
```
Expected: `syntax ok`

---

## Task 10: Dry-run install.sh against a scratch HOME (never touch real ~/.claude)

- [ ] **Step 1: Run with an isolated config dir**

```bash
rm -rf .scratch-home && mkdir -p .scratch-home/.claude
# seed a minimal settings.json so the merge has a base + a real statusline source
echo '{"permissions":{"allow":[],"deny":[]}}' > .scratch-home/.claude/settings.json
CLAUDE_CONFIG_DIR="$PWD/.scratch-home/.claude" HOME="$PWD/.scratch-home" \
  bash bootstrap/install.sh || true
```
Expected: log lines for marketplace/plugins/skills/agents/hooks/settings. Plugin/marketplace steps may warn if `claude` can't write to the scratch HOME — acceptable for the dry run; the file-copy + settings-merge steps must succeed.

- [ ] **Step 2: Verify file-copy results in scratch HOME**

```bash
echo "agents:"; ls .scratch-home/.claude/agents
echo "hooks:";  ls .scratch-home/.claude/hooks
echo "token rewritten (want absolute path, no @@):"; grep -h "command:.*hooks" .scratch-home/.claude/agents/git.md
echo "settings statusLine:"; python3 -c "import json;print(json.load(open('.scratch-home/.claude/settings.json'))['statusLine'])"
echo "permissions merged (want >0 deny):"; python3 -c "import json;print(len(json.load(open('.scratch-home/.claude/settings.json'))['permissions']['deny']))"
```
Expected: 6 agents, 4 hooks; git.md hook command is an absolute `.scratch-home/.claude/hooks/git-guard.sh` path with no `@@HOOKS_DIR@@`; statusLine command references `.scratch-home/.claude/statusline.sh`; deny count > 0.

- [ ] **Step 3: Verify idempotency (second run, no crash)**

```bash
CLAUDE_CONFIG_DIR="$PWD/.scratch-home/.claude" HOME="$PWD/.scratch-home" \
  bash bootstrap/install.sh && echo "second run ok"
```
Expected: `second run ok` (a fresh settings backup is created; no errors).

- [ ] **Step 4: Clean up scratch + commit**

```bash
rm -rf .scratch-home
git add bootstrap/install.sh
git commit -m "feat(bootstrap): idempotent install.sh (plugins, skills, agents, hooks, settings)"
```

---

## Task 11: Write `scripts/export.sh` (repo ← live ~/.claude)

**Files:** Create: `scripts/export.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Re-sync this repo FROM the live ~/.claude (local-first workflow).
# Pulls owner-authored skills, agents, hooks; regenerates skills.lock + settings snippet.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
log(){ printf '\033[1;32m[export]\033[0m %s\n' "$*"; }

OWN_SKILLS=(ansi-color-piping cross-platform-tests ink-useinput-bind no-barrel-files \
            package-public-api ssr-client-divergence tailwind-css-v4-usage \
            validating-stale-worktrees vertical-code-structure)

# 1) Own skills → plugin (skip symlinks = third-party).
for s in "${OWN_SKILLS[@]}"; do
  src="$CLAUDE_DIR/skills/$s"
  [ -d "$src" ] && [ ! -L "$src" ] || { log "skip $s (missing or symlink)"; continue; }
  rm -rf "$REPO_ROOT/plugins/jiechao-toolkit/skills/$s"
  rsync -a --exclude='.DS_Store' "$src/" "$REPO_ROOT/plugins/jiechao-toolkit/skills/$s/"
done
log "synced own skills"

# 2) Agents (tokenize hook paths) + hooks.
for a in edit git node python research shell; do
  [ -f "$CLAUDE_DIR/agents/$a.md" ] || continue
  sed "s#$CLAUDE_DIR/hooks#@@HOOKS_DIR@@#g; s#/Users/[^/]*/.claude/hooks#@@HOOKS_DIR@@#g" \
      "$CLAUDE_DIR/agents/$a.md" > "$REPO_ROOT/bootstrap/agents/$a.md"
done
for h in git-guard path-guard runner-only shell-guard; do
  [ -f "$CLAUDE_DIR/hooks/$h.sh" ] && cp "$CLAUDE_DIR/hooks/$h.sh" "$REPO_ROOT/bootstrap/hooks/$h.sh"
done
log "synced agents + hooks"

# 3) Regenerate third-party skills lock + settings snippet + statusline.
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
log "regenerated lock/settings/statusline. Review 'git diff' and commit."
```

- [ ] **Step 2: Make executable + syntax check + dry verify**

```bash
chmod +x scripts/export.sh
bash -n scripts/export.sh && echo "syntax ok"
./scripts/export.sh
git status --short   # expect little/no diff since repo was just built from the same source
```
Expected: `syntax ok`, export runs clean, `git status` shows no unexpected changes.

- [ ] **Step 3: Commit**

```bash
git add scripts/export.sh
git commit -m "feat(scripts): export.sh to re-sync repo from live ~/.claude"
```

---

## Task 12: Correct the docs to match the implemented architecture

**Files:** Modify: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/adding-tools.md`, `docs/install.md`, and the spec.

- [ ] **Step 1: Fix the agents/hooks delivery description everywhere**

The earlier docs say agents/hooks live in the plugin. Correct them to: **agents + hooks are delivered via `bootstrap/` and `install.sh` into `~/.claude`, because plugin-bundled subagents ignore `hooks`/`permissionMode`/`mcpServers`.** Specifically:
- `docs/architecture.md`: move agents/hooks from "Layer A" to "Layer B"; add the constraint + the `@@HOOKS_DIR@@` token note.
- `docs/adding-tools.md`: in the personal table, a new subagent → `bootstrap/agents/<name>.md` (refresh via `install.sh`, not `/plugin update`); a new hook → `bootstrap/hooks/`; update the quick-reference table and the `${CLAUDE_PLUGIN_ROOT}` guidance (use `@@HOOKS_DIR@@` token for agent hook paths).
- `README.md`: layout block — agents/hooks under `bootstrap/`.
- `CLAUDE.md`: decision tree — personal subagent/hook → Layer B; update invariant #1 (agent hook paths use `@@HOOKS_DIR@@`, rewritten by install.sh) and the install/refresh commands.
- `docs/install.md`: note install.sh now also installs plugins via the `claude plugin` CLI and copies agents/hooks.
- spec (`docs/superpowers/specs/2026-06-02-…-design.md`): add the plugin-subagent constraint under "Component design" and move agents/hooks to Layer B.

- [ ] **Step 2: Verify no doc still claims agents ship inside the plugin**

Run: `grep -rn "jiechao-toolkit/agents\|jiechao-toolkit/hooks" README.md CLAUDE.md docs/ || echo "clean"`
Expected: `clean`.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md docs
git commit -m "docs: correct agents/hooks delivery (bootstrap, not plugin) + constraints"
```

---

## Task 13: End-to-end verification

- [ ] **Step 1: Plugin + marketplace validate clean**

Run: `claude plugin validate .` (and `claude plugin validate plugins/jiechao-toolkit`)
Expected: passes.

- [ ] **Step 2: Real install of the OWN plugin only (low-risk, reversible)**

```bash
claude plugin marketplace add "$PWD"
claude plugin install jiechao-toolkit@claude-plugin
claude plugin list | grep jiechao-toolkit
```
Expected: `jiechao-toolkit` listed as installed. (Restart Claude Code to load; a bundled skill such as `no-barrel-files` should appear.)

- [ ] **Step 3: Confirm guard agents still function as user-scope (already live in ~/.claude)**

Note: the existing `~/.claude/agents` already provides these; `install.sh` only re-materializes them on a fresh machine. No action needed locally beyond confirming `install.sh`'s scratch-HOME dry-run (Task 10) rewired the token correctly.

- [ ] **Step 4: Final commit + summary**

```bash
git add -A && git commit -m "chore: finalize source-of-truth repo" || echo "nothing to commit"
git log --oneline
```

---

## Out of scope (YAGNI)
- Pushing to GitHub / creating the public remote (owner does this; then optionally `claude plugin marketplace add <owner>/claude-plugin` on other machines instead of the local path).
- A standalone `bootstrap/mcp.json` (no file-based MCP currently).
- Auto-running `install.sh` at cloud-session start (documented; wiring is environment-specific).

## Post-build manual step for the owner
Create the public GitHub repo and push:
```bash
git remote add origin git@github.com:<owner>/claude-plugin.git
git push -u origin main
```
Then on any other machine/cloud session: `git clone …` → `./bootstrap/install.sh`.
