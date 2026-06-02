# CLAUDE.md — Operating contract for AI agents

You are working in **`claude-plugin`**, the single source of truth for the owner's
personal Claude Code tooling. This file tells you how to operate here correctly.
Humans: this doubles as the precise spec of how the repo behaves.

## Prime directive

> **Edit this repo. Never hand-edit `~/.claude` as the source of truth.**

`~/.claude` is a *regenerated working copy*. Any tooling change must land in this
repo, then be propagated. If a change exists only in `~/.claude`, it is lost on the
next rebuild.

## What this repo is (two layers)

- **Layer A — `plugins/jiechao-toolkit/`**: content the owner *authored*
  **skills** (+ optional personal MCP). Distributed as a Claude plugin via the
  marketplace in `.claude-plugin/marketplace.json`. **Subagents and hooks are NOT
  here** — plugin subagents ignore `hooks`/`permissionMode`/`mcpServers`.
- **Layer B — `bootstrap/`**: *declarations* of content installed *from others*
  (third-party plugins + skills), *portable settings*, **and the owner's subagents +
  guard hooks** (delivered into `~/.claude` by `install.sh`, where their security
  fields are honored). Reconstructed by `bootstrap/install.sh`. Third-party code is
  **referenced, never vendored**.

## Invariants (do not violate)

1. **No absolute user paths in committed files.** An agent's hook path uses the
   `@@HOOKS_DIR@@` token (`install.sh` rewrites it to `$HOME/.claude/hooks`), e.g.
   `command: "@@HOOKS_DIR@@/git-guard.sh"`, never `/Users/jiechao/...`. Inside the
   plugin (`.mcp.json`/`plugin.json` only), `${CLAUDE_PLUGIN_ROOT}` is the analogous
   variable — but it does NOT work in agent frontmatter.
2. **Never vendor third-party source into the repo.** Add a *reference* in
   `bootstrap/manifest.json` (plugins) or `bootstrap/skills.lock.json` (skills).
3. **Never replace `~/.claude/settings.json`.** Settings are *deep-merged* from
   `bootstrap/settings.snippet.json`, and the file is backed up first.
4. **Never put runtime/account state in the repo** (`history.jsonl`, `projects/`,
   `sessions/`, `daemon*`, `telemetry/`, auth/credentials). See the three-bucket
   model in `docs/architecture.md`.
5. **`install.sh` must stay idempotent** (`set -euo pipefail`, skip already-installed,
   back up before merge). Safe to run repeatedly, including at cloud-session start.
6. **statusLine is centralized here.** It lives in `bootstrap/statusline.sh` +
   `bootstrap/settings.snippet.json`; do not let machines diverge.

## Decision rules — where does a new thing go?

```
Is it something the owner authored?
├── YES
│   ├── skill → Layer A: plugins/jiechao-toolkit/skills/<name>/SKILL.md
│   │            then: push → /plugin update jiechao-toolkit
│   ├── MCP   → Layer A: plugins/jiechao-toolkit/.mcp.json  (use ${CLAUDE_PLUGIN_ROOT})
│   │            then: push → /plugin update jiechao-toolkit
│   ├── agent → Layer B: bootstrap/agents/<name>.md  (hook paths use @@HOOKS_DIR@@)
│   │            then: ./bootstrap/install.sh → commit
│   └── hook  → Layer B: bootstrap/hooks/<name>.sh  (ref as @@HOOKS_DIR@@/<name>.sh)
│                then: ./bootstrap/install.sh → commit
└── NO (installed from someone else) → Layer B: bootstrap/
          plugin  → add to manifest.json
          skill   → add to skills.lock.json  (source repo + skillPath)
          MCP     → ships inside a third-party plugin (add that plugin)
          then: ./bootstrap/install.sh → commit
```

Settings/permissions/statusline changes → edit `bootstrap/settings.snippet.json`
(or `statusline.sh`) → `./bootstrap/install.sh` → commit.

Full procedures with examples: **`docs/adding-tools.md`**.

## Two valid workflows

- **Repo-first (preferred):** create the file in the repo → push → refresh
  (`/plugin update` for Layer A, `install.sh` for Layer B).
- **Local-first (prototyping):** the owner adds it in `~/.claude` → run
  `scripts/export.sh` to pull live state into the repo → commit/push. Always run
  `export.sh` before committing if `~/.claude` was hand-touched, so nothing is lost.

## When asked to "sync" or "I added X locally"

Run `scripts/export.sh`. It re-copies the owner's own skills into the plugin and the
agents/hooks into `bootstrap/` (re-tokenizing hook paths), and regenerates
`skills.lock.json` + `settings.snippet.json` + `statusline.sh` from current local
state. Then review the diff and commit.

## Validation before commit

- `marketplace.json` and `plugin.json` parse and match the Claude plugin schema.
- No absolute user paths introduced (`grep -r '/Users/' --include='*.json' --include='*.md' --include='*.sh'` should only match docs/examples).
- If you touched `install.sh`, dry-run it against a scratch `HOME` — never against
  the real `~/.claude` during development.

## Pointers

- Architecture & buckets → `docs/architecture.md`
- Adding tools (the common task) → `docs/adding-tools.md`
- Install / rebuild → `docs/install.md`
- Auto-apply in Claude cloud sessions → `docs/cloud-setup.md`
- Design record → `docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md`
