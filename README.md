# claude-plugin

**Your single source of truth for personal Claude Code tooling** — skills,
subagents, hooks, settings (incl. statusline), and the list of third-party
plugins/skills you rely on. One repo you maintain, reproducible on any
machine and in any Claude **cloud session**.

> If you are an AI agent operating in this repo, read [`CLAUDE.md`](./CLAUDE.md)
> first — it is your operating contract.

---

## What this is

This repo is **two things at once**:

1. **A Claude marketplace + plugin** (`jiechao-toolkit`) holding the content you
   *authored yourself* — skills, subagents, hooks. (Layer A)
2. **A bootstrap layer** that *declares* everything you installed *from others*
   (third-party plugins and skills) plus your *portable settings*, and rebuilds
   them on demand. (Layer B)

You maintain **only this repo**. Your local `~/.claude` becomes a regenerated
working copy of the config layer.

## The 30-second mental model

Three buckets — see [`docs/architecture.md`](./docs/architecture.md) for detail:

| Bucket | Examples | Rule |
|---|---|---|
| ✅ **Maintained** = this repo | your skills, agents, hooks, the third-party manifest, portable settings | The only thing you hand-edit |
| ♻️ **Generated** = rebuilt into `~/.claude` | installed plugin cache, third-party skills, merged `settings.json` | Disposable; `install.sh` recreates it |
| ⛔ **Runtime/account state** | `history.jsonl`, `projects/`, `sessions/`, auth, `daemon*` | Never in this repo; never deleted |

**Golden rule:** edit the repo, not `~/.claude`. Then run one command to propagate.

## Quickstart

### Install on a new machine or cloud session

```bash
# 1. Add the marketplace (your own authored content)
#    In Claude Code:
/plugin marketplace add jiechao/claude-plugin
/plugin install jiechao-toolkit

# 2. Reconstruct third-party plugins/skills + portable settings
git clone git@github.com:jiechao/claude-plugin.git
./claude-plugin/bootstrap/install.sh
```

`install.sh` is idempotent and backs up `settings.json` before merging — safe to
run at the start of every cloud session. Full detail: [`docs/install.md`](./docs/install.md).

### Add a new tool later

See [`docs/adding-tools.md`](./docs/adding-tools.md) for the per-type playbooks.
Short version:

- **Personal skill / MCP** → add under `plugins/jiechao-toolkit/`, push, then
  `/plugin update jiechao-toolkit`.
- **Personal subagent / hook** → add under `bootstrap/agents` or `bootstrap/hooks`,
  run `./bootstrap/install.sh` (plugin subagents can't carry guard hooks).
- **Third-party** plugin/skill → add an entry to `bootstrap/manifest.json` or
  `bootstrap/skills.lock.json`, run `install.sh`, commit.

## Repository layout

```
claude-plugin/
├── .claude-plugin/marketplace.json   # marketplace manifest
├── plugins/jiechao-toolkit/          # Layer A — your own SKILLS (+ optional .mcp.json)
│   ├── .claude-plugin/plugin.json
│   └── skills/
├── bootstrap/                        # Layer B — third-party + agents/hooks + settings
│   ├── manifest.json   skills.lock.json
│   ├── settings.snippet.json   statusline.sh
│   ├── agents/   hooks/              # delivered to ~/.claude (not the plugin)
│   ├── templates/                    # drop-in .claude/settings.json for other repos
│   ├── session-sync.sh               # cloud per-session refresh (fresh commits only)
│   └── install.sh
├── scripts/export.sh                 # sync repo FROM live ~/.claude
├── docs/                             # detailed documentation (this set)
└── CLAUDE.md                         # agent operating contract
```

## Documentation map

- [`CLAUDE.md`](./CLAUDE.md) — operating contract for AI agents working in this repo
- [`docs/architecture.md`](./docs/architecture.md) — the two-layer / three-bucket design
- [`docs/adding-tools.md`](./docs/adding-tools.md) — how to add any tool type in future
- [`docs/install.md`](./docs/install.md) — install/rebuild on a machine or cloud session
- [`docs/cloud-setup.md`](./docs/cloud-setup.md) — auto-apply this repo in Claude cloud sessions
- [`docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md`](./docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md) — the approved design record
