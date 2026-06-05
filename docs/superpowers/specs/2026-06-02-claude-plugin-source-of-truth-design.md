# Design: `claude-plugin` — Portable Single Source of Truth for Personal Claude Tooling

**Date:** 2026-06-02
**Status:** Approved design, pending implementation plan
**Owner:** jiechao

> **⚠️ Archival note (added 2026-06-05):** This document records the original
> design intent; the implementation diverged in naming. Read these substitutions
> when following any command or path below:
> `bootstrap/install.sh` → `bootstrap/apply.sh`,
> `scripts/export.sh` → `scripts/capture.sh`,
> `docs/adding-tools.md` → `docs/updating-plugin.md`,
> `docs/install.md` → `docs/local-setup.md`.
> Also: the owner's subagents and guard hooks ship in `bootstrap/agents/` and
> `bootstrap/hooks/` (Layer B), **not** inside the plugin. For current behavior
> see `CLAUDE.md` and `docs/architecture.md`.

## Problem

Personal Claude Code tooling (skills, subagents, hooks, settings, and installed
third-party plugins/skills) currently lives only in the local personal workspace
(`~/.claude`, `~/.agents`). It is not portable: it cannot be reliably reused
across repositories (monorepo or polyrepo), across machines, or in Claude **cloud
sessions**. There is no single source of truth and no repeatable way to
reconstruct the environment.

## Goal

One public GitHub repository, `claude-plugin`, that is:

- The **only** thing the user hand-maintains for their Claude config/tooling layer.
- Installable on any machine and in any Claude cloud session.
- A Claude **marketplace** (for the user's own authored content) **plus** a
  **bootstrap layer** (for everything third-party and for portable settings).

## Decisions (locked)

| Decision | Choice |
|---|---|
| Repo visibility | **Public** GitHub repo (no secrets; references third-party, doesn't vendor) |
| Third-party skills & plugins | **Reference & re-install** (declare by source; never fork) |
| Structure | **One** consolidated plugin (`jiechao-toolkit`) for own content |
| Settings scope | **Full portable settings** — permissions + `statusLine` + `statusline.sh` + notification prefs + `skipAutoPermissionPrompt` |
| statusLine | **Must be centralized** in the repo |
| Cloud target | Claude **cloud sessions** (public repo → plain clone in the Setup script) |

## Mental model: three buckets

1. **Maintained (the repo only):** own skills, subagents, hooks, the third-party
   plugin/skill manifest, portable settings.
2. **Generated / disposable (rebuilt from the repo into `~/.claude`):** installed
   plugin cache, third-party skills copied into `~/.claude/skills`, settings merged
   into `~/.claude/settings.json`. Safe to delete; `install.sh` reconstructs it.
3. **Must stay (runtime/account state, never in the repo):** `settings.json` file
   itself (merged into, not replaced), `history.jsonl`, `projects/`, `sessions/`,
   `daemon*`, `telemetry/`, `ide/`, `shell-snapshots/`, `file-history/`, `plans/`,
   `tasks/`, auth/credentials.

## Repository layout

```
claude-plugin/                       # public GitHub repo == Claude marketplace
├── .claude-plugin/
│   └── marketplace.json             # declares the marketplace + the plugin(s)
├── plugins/
│   └── jiechao-toolkit/             # Layer A: the user's own content (copied in)
│       ├── .claude-plugin/plugin.json
│       ├── skills/                  # ~10 authored skills
│       ├── agents/                  # 6 subagents (hook paths → ${CLAUDE_PLUGIN_ROOT})
│       └── hooks/                   # git-guard, path-guard, runner-only, shell-guard
├── bootstrap/                       # Layer B: third-party + settings (declared)
│   ├── manifest.json                # marketplaces + plugins to install
│   ├── skills.lock.json             # 33 third-party skills (source repo + skillPath)
│   ├── settings.snippet.json        # portable settings to merge
│   ├── statusline.sh                # centralized statusline script
│   └── install.sh                   # idempotent installer + settings merge
├── scripts/
│   └── export.sh                    # re-sync repo FROM live ~/.claude (keep truthful)
├── README.md
└── .gitignore
```

## Component design

### Layer A — `jiechao-toolkit` plugin (own content)

- **`marketplace.json`** — schema `https://anthropic.com/claude-code/marketplace.schema.json`;
  `name: claude-plugin`; one `plugins[]` entry sourced from `./plugins/jiechao-toolkit`.
- **`plugin.json`** — name `jiechao-toolkit`, version, description.
- **`skills/`** — the 9 locally authored skills copied verbatim:
  `ansi-color-piping`, `cross-platform-tests`, `ink-useinput-bind`,
  `no-barrel-files`, `package-public-api`, `ssr-client-divergence`,
  `tailwind-css-v4-usage`, `validating-stale-worktrees`, `vertical-code-structure`.
  - **Resolved:** `cross-platform-tests-workspace` was skill-iteration scratch (no
    SKILL.md) → excluded. Eval fixtures (`skills/*/evals/`) are gitignored (they
    carry machine paths and are not runtime resources).
- **Subagents/hooks are NOT in the plugin** — see constraint below; they are
  delivered via Layer B.
- **Install:** `claude plugin marketplace add <repo-or-local-path>` →
  `claude plugin install jiechao-toolkit@claude-plugin`.

> **Constraint (discovered during implementation):** plugin-bundled subagents ignore
> the `hooks`, `mcpServers`, and `permissionMode` frontmatter fields for security
> reasons ([sub-agents.md](https://code.claude.com/docs/en/sub-agents.md)). Five of
> the six agents depend on those fields. Therefore agents + their guard hooks are
> delivered by `install.sh` into `~/.claude/agents` and `~/.claude/hooks` (user
> scope, where the fields are honored), NOT bundled in the plugin. Agent hook paths
> are stored with a `@@HOOKS_DIR@@` token, rewritten to `$HOME/.claude/hooks` at
> install time (`${CLAUDE_PLUGIN_ROOT}` is not expanded in agent frontmatter).

### Layer B — bootstrap (third-party + settings)

- **`manifest.json`** — declares marketplaces (`claude-plugins-official`) and the
  11 plugins to install (`frontend-design`, `superpowers`, `code-review`,
  `skill-creator`, `claude-code-setup`, `code-simplifier`, `claude-md-management`,
  `feature-dev`, `typescript-lsp`, `ralph-loop`, `commit-commands`).
- **`skills.lock.json`** — the 34 third-party skills (33 GitHub + 1 well-known) with
  `source` repo + `skillPath`, snapshotted from `~/.agents/.skill-lock.json`.
- **`agents/`** — the 6 subagents, hook paths stored as `@@HOOKS_DIR@@/<guard>.sh`.
- **`hooks/`** — the 4 guard scripts (git-guard, path-guard, runner-only, shell-guard).
- **`settings.snippet.json`** — portable settings to merge: `permissions.allow`,
  `permissions.deny`, `statusLine`, `inputNeededNotifEnabled`,
  `agentPushNotifEnabled`, `skipAutoPermissionPrompt`. (`enabledPlugins` handled
  by the plugin install step.)
- **`statusline.sh`** — centralized; `install.sh` copies it to
  `~/.claude/statusline.sh` so `statusLine.command` resolves.
- **`install.sh`** — `set -euo pipefail`, **idempotent** (`SKIP_PLUGINS`/`SKIP_SKILLS`):
  1. add own marketplace (local path) + install `jiechao-toolkit`; add declared
     marketplaces + install the 11 plugins, via the `claude plugin` CLI (skip if present);
  2. for each `skills.lock.json` entry, git-clone (shallow) or well-known-fetch and
     copy the skill folder into `~/.claude/skills/` — **no dependency on any specific
     skill-manager binary**, so it works in a bare cloud sandbox;
  3. copy agents into `~/.claude/agents` (rewrite `@@HOOKS_DIR@@` → `$HOME/.claude/hooks`)
     and hooks into `~/.claude/hooks`;
  4. **back up** `~/.claude/settings.json`, then deep-merge `settings.snippet.json`
     (never replace the file) and repoint `statusLine`;
  5. copy `statusline.sh` into place.

### Sync direction — `scripts/export.sh`

Keeps the repo a *living* source of truth, not a one-time dump. Re-copies live
`~/.claude/skills` (own only), `~/.claude/agents`, `~/.claude/hooks` into the repo,
and regenerates `skills.lock.json` + `manifest.json` from current state. User runs
it after changing tooling locally, then commits.

## Cloud session usage

A Claude cloud session can clone the **public** repo with no auth. Entry points:

1. `/plugin marketplace add jiechao/claude-plugin` then
   `/plugin install jiechao-toolkit` for own content; and
2. run `bootstrap/install.sh` to reconstruct third-party plugins/skills + portable
   settings.

Because cloud sessions are ephemeral, `install.sh` is safe to run at session start
every time (idempotent, backs up before merge).

## Error handling & safety

- `install.sh`: `set -euo pipefail`; idempotent (skip already-installed); timestamped
  backup of `settings.json` before any merge; clear logging of each step.
- Never replace `settings.json` or touch runtime/account files.
- Deep-merge semantics for settings (arrays for permissions deduped; scalars
  overwritten by repo values).

## Testing

- Validate `marketplace.json` / `plugin.json` against the Claude plugin schema.
- Dry-run `install.sh` against a scratch `HOME` so the real config is never touched
  during development.
- Smoke test from a fresh install: one skill loads, the `git` agent loads, a guard
  hook fires, statusline renders.
- Verify idempotency: running `install.sh` twice produces no errors and no drift.

## Out of scope (YAGNI)

- MCP servers (none currently configured in file-based config).
- Re-bundling third-party plugin/skill source (reference-and-reinstall instead).
- Migrating account/runtime state.

## Documentation (delivered)

Written for both humans (peruse) and LLM agents (operate):

- `README.md` — human entry point: what it is, mental model, quickstart, layout.
- `CLAUDE.md` — agent operating contract (auto-loaded by Claude Code in this repo):
  prime directive, invariants, decision rules, validation.
- `docs/architecture.md` — two-layer / three-bucket design and rationale.
- `docs/adding-tools.md` — per-type playbooks for adding any tool in future
  (third-party and personal), both repo-first and local-first directions.
- `docs/install.md` — install/rebuild on a machine or cloud session; disposable
  model; smoke test; updating; `export.sh` sync.

## Open items to confirm during implementation

1. Dedupe `cross-platform-tests` vs `cross-platform-tests-workspace`.
2. Final plugin name (`jiechao-toolkit` placeholder; trivially renamable).
3. Exact GitHub repo slug for `marketplace add` (e.g. `jiechao/claude-plugin`).
