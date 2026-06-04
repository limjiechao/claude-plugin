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
   *authored yourself* — skills (+ optional personal MCP). (**Layer A**)
2. **A bootstrap layer** that *declares* everything you installed *from others*
   (third-party plugins + skills), your *portable settings*, and your *subagents +
   guard hooks*, and rebuilds them on demand. (**Layer B**)

You maintain **only this repo**; your local `~/.claude` is a regenerated working copy
of the config layer. **Golden rule: edit the repo, not `~/.claude`** — then run one
command to propagate. The full conceptual model (two layers, three buckets, and
*why*) lives in [`docs/architecture.md`](./docs/architecture.md).

## Quickstart

### Set up on a new machine or cloud session

```bash
# 1. Add the marketplace (your own authored content) — in Claude Code:
/plugin marketplace add jiechao/claude-plugin
/plugin install jiechao-toolkit

# 2. Reconstruct third-party plugins/skills + agents/hooks + portable settings:
git clone git@github.com:jiechao/claude-plugin.git
./claude-plugin/bootstrap/apply.sh
```

`apply.sh` is idempotent and backs up `settings.json` before merging — safe to run at
the start of every session. Local detail: [`docs/local-setup.md`](./docs/local-setup.md).
Auto-applying it in cloud sessions: [`docs/cloud-setup.md`](./docs/cloud-setup.md).

### The two scripts — one rule, two directions

| Script | Direction | Reach for it when… |
|---|---|---|
| **`bootstrap/apply.sh`** | repo → `~/.claude` | rebuilding the live config from the repo (cloud + Claude-only machines) |
| **`scripts/capture.sh`** | `~/.claude` → repo | pulling live changes back up (prototyping, or multi-vendor machines) |

Which to run — and when **not** to run `apply.sh` locally — is spelled out in
[`docs/local-setup.md`](./docs/local-setup.md#which-script-and-when--applysh-vs-capturesh).

## Documentation map — start here

This README is the doorman. Read the docs in this order; each has exactly one job:

1. **[`CLAUDE.md`](./CLAUDE.md)** — operating contract for AI agents in this repo
   (humans: also the precise spec of how it behaves).
2. **[`docs/architecture.md`](./docs/architecture.md)** — the *why*: two-layer design,
   three-bucket model, design rationale, current inventory.
3. **[`docs/local-setup.md`](./docs/local-setup.md)** — install/rebuild on a local
   machine; the `apply.sh` vs `capture.sh` decision.
4. **[`docs/cloud-setup.md`](./docs/cloud-setup.md)** — auto-apply this repo in Claude
   cloud sessions (Setup script, session hook).
5. **[`docs/testing.md`](./docs/testing.md)** — unit-test commands for bootstrap
   changes.
6. **[`docs/updating-plugin.md`](./docs/updating-plugin.md)** — how to add any tool type
   later (skill, agent, hook, MCP, third-party).
7. **[`docs/superpowers/specs/…-design.md`](./docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md)**
   — the approved design record (archival).

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
│   └── apply.sh                      # repo → ~/.claude (idempotent rebuild)
├── scripts/capture.sh                # ~/.claude → repo (keep the repo truthful)
├── docs/                             # detailed documentation (see map above)
└── CLAUDE.md                         # agent operating contract
```
