# Architecture

How `claude-plugin` is organized and why. Read this once; it explains every other
doc.

## The problem it solves

Personal Claude tooling normally lives only in `~/.claude` (and `~/.agents`) on one
machine. That is not portable across repos, machines, or **Claude cloud sessions**,
and there is no repeatable way to rebuild it. This repo makes the tooling layer a
single, version-controlled, reproducible source of truth.

## Two layers

A Claude plugin can natively carry **commands, skills, agents, hooks, and MCP
servers** — but it **cannot** carry `settings.json` permission/statusline config,
and you should **not** fork other people's plugins/skills into it. So the repo has
two layers:

### Layer A — `plugins/jiechao-toolkit/` (your own content, *copied in*)

Distributed as a normal Claude plugin through the marketplace declared in
`.claude-plugin/marketplace.json`.

```
plugins/jiechao-toolkit/
├── .claude-plugin/plugin.json   # name, version, description
├── skills/<name>/SKILL.md       # 9 authored skills
└── .mcp.json                    # personal MCP servers (optional)
```

The plugin carries **skills** (and optional personal MCP, which plugins fully
support). It deliberately does **not** carry the subagents or guard hooks — see the
constraint below.

> **Why agents/hooks are NOT in the plugin.** Per the official docs, **plugin-bundled
> subagents ignore the `hooks`, `mcpServers`, and `permissionMode` frontmatter
> fields for security reasons** ([sub-agents.md](https://code.claude.com/docs/en/sub-agents.md)).
> Five of the six agents depend on exactly those fields (e.g. `git` →
> `permissionMode: dontAsk` + a `git-guard.sh` PreToolUse hook). If shipped via the
> plugin, the guardrails would silently stop working. So agents + hooks are
> delivered through **Layer B** into `~/.claude/agents` and `~/.claude/hooks`, where
> those fields are honored. The repo is still the single source of truth; only the
> delivery mechanism differs, because the platform requires it.

### Layer B — `bootstrap/` (third-party + settings, *declared*)

Third-party content is **referenced and re-installed**, never vendored — so you get
upstream updates, avoid forking someone else's code, and keep the repo clean.

```
bootstrap/
├── manifest.json          # marketplaces to add + plugins to install (the 11)
├── skills.lock.json       # third-party skills (34): source repo + skillPath
├── settings.snippet.json  # portable settings to deep-merge
├── statusline.sh          # centralized statusline script
├── agents/<name>.md       # 6 subagents (hook paths tokenized as @@HOOKS_DIR@@)
├── hooks/<name>.sh        # 4 guard scripts (git/path/runner/shell)
└── install.sh             # idempotent installer + settings merge
```

`install.sh` (idempotent; `SKIP_PLUGINS=1` / `SKIP_SKILLS=1` opt-outs):
1. adds the own marketplace (this repo, by local path — no GitHub slug needed) and
   installs `jiechao-toolkit`, then adds declared marketplaces + installs the 11
   plugins, all via the non-interactive `claude plugin` CLI (skips if present);
2. for each entry in `skills.lock.json`, shallow-clones the source repo (or fetches
   a well-known URL) and copies the skill folder into `~/.claude/skills/` — **no
   dependency on any specific skill-manager binary**, so it works in a bare cloud
   sandbox;
3. copies the **agents** into `~/.claude/agents`, rewriting the `@@HOOKS_DIR@@`
   token to the real `$HOME/.claude/hooks` (username/path-portable), and the
   **guard hooks** into `~/.claude/hooks`;
4. timestamped-backs-up `~/.claude/settings.json`, then deep-merges
   `settings.snippet.json` (permission arrays deduped; scalars overwritten) and
   repoints `statusLine` at `~/.claude/statusline.sh`;
5. copies `statusline.sh` to `~/.claude/statusline.sh`.

**Portability rule for agent hook paths:** in the repo, an agent's hook command is
stored as `@@HOOKS_DIR@@/git-guard.sh` (never an absolute `/Users/...` path);
`install.sh` rewrites the token at install time. (`${CLAUDE_PLUGIN_ROOT}` is the
analogous variable, but it is **not** reliably expanded in agent frontmatter and is
moot here since agents are not shipped via the plugin.)

## The three-bucket model

Everything on a machine falls into one of three buckets. This is what makes
"maintain only the repo" precise.

| Bucket | What | Where it lives | Lifecycle |
|---|---|---|---|
| ✅ **Maintained** | own skills (plugin), own agents+hooks (bootstrap), third-party manifest, portable settings | **this repo** | hand-edited, version-controlled |
| ♻️ **Generated** | installed plugin cache, third-party skills, copied agents+hooks, merged `settings.json` keys, `statusline.sh` | `~/.claude/` | disposable; rebuilt by `install.sh` / `/plugin install` |
| ⛔ **Runtime/account** | `history.jsonl`, `projects/`, `sessions/`, `daemon*`, `telemetry/`, `ide/`, `shell-snapshots/`, `file-history/`, `plans/`, `tasks/`, auth/credentials | `~/.claude/` | **never** in repo; **never** deleted |

Implication: you may clear the **Generated** bucket anytime (e.g. stale third-party
skill copies, `~/.agents/skills`) and rebuild it. You must never put the **Runtime**
bucket in the repo or delete it. `settings.json` straddles buckets — the *file*
stays (Runtime: it holds `enabledPlugins`, notification state), but specific keys
are *merged* from the repo (Generated).

## Why these specific choices

| Choice | Reason |
|---|---|
| Public repo | No secrets; references (doesn't vendor) third-party content; cloud sessions clone it with no auth. |
| Reference, not vendor | Upstream updates, no fork rot, no licensing exposure. |
| One plugin (not many) | Simplest single unit to enable/disable; can split later if needed. |
| `install.sh` clones skills directly | Works in a bare cloud sandbox with no pre-installed skill manager. |
| Agents/hooks via bootstrap, not plugin | Plugin subagents ignore `hooks`/`permissionMode`/`mcpServers`; user-scope agents honor them. |
| statusLine centralized | Explicit owner requirement — no per-machine drift. |
| Personal MCP via plugin `.mcp.json`; third-party MCP via plugins | Personal MCP travels with the plugin; third-party MCP already ships inside plugins. |

## Current inventory (snapshot at creation)

- **Own skills (9, in the plugin):** ansi-color-piping, cross-platform-tests,
  ink-useinput-bind, no-barrel-files, package-public-api, ssr-client-divergence,
  tailwind-css-v4-usage, validating-stale-worktrees, vertical-code-structure.
  (`cross-platform-tests-workspace` was iteration scratch — excluded.)
- **Subagents (6, in bootstrap):** edit, git, node, python, research, shell.
- **Hooks (4, in bootstrap):** git-guard, path-guard, runner-only, shell-guard.
- **Third-party plugins (11):** frontend-design, superpowers, code-review,
  skill-creator, claude-code-setup, code-simplifier, claude-md-management,
  feature-dev, typescript-lsp, ralph-loop, commit-commands (all from
  `claude-plugins-official`).
- **Third-party skills (34):** from GitHub repos (vercel-labs, millionco, etc.) +
  1 well-known (react-aria), enumerated in `bootstrap/skills.lock.json`.
- **MCP:** none in file-based config at creation (the Google Drive MCP is
  account-managed by claude.ai and not portable via files).
