# Install & rebuild

How to reconstruct your full Claude tooling layer on a new machine or in a Claude
**cloud session** — and how the disposable/regenerated model works in practice.

## Prerequisites

- Claude Code installed.
- Git access to the repo (`limjiechao/claude-plugin`) — it's **public**, so a plain
  `git clone` works on any machine and in any cloud session, no auth needed.

## Full install (new machine or fresh cloud session)

Two parts, matching the two layers.

### Part 1 — Layer A: your own plugin

In Claude Code:

```
/plugin marketplace add jiechao/claude-plugin
/plugin install jiechao-toolkit
```

This makes your authored skills, subagents, and hooks available.

### Part 2 — Layer B: third-party + portable settings

```bash
git clone git@github.com:jiechao/claude-plugin.git
./claude-plugin/bootstrap/install.sh
```

`install.sh` will:
1. add the own marketplace (this repo, by local path) + install `jiechao-toolkit`,
   then add the declared marketplaces and install the 11 third-party plugins — all
   via the non-interactive `claude plugin` CLI (skips any already installed);
2. clone (or well-known-fetch) + copy each third-party skill from `skills.lock.json`
   into `~/.claude/skills/`;
3. copy the **subagents** into `~/.claude/agents/` (rewriting `@@HOOKS_DIR@@` to the
   real hooks dir) and the **guard hooks** into `~/.claude/hooks/`;
4. back up `~/.claude/settings.json` (timestamped) and deep-merge
   `settings.snippet.json` (permissions, notification prefs,
   `skipAutoPermissionPrompt`, `statusLine`);
5. copy `statusline.sh` to `~/.claude/statusline.sh`.

It is **idempotent** — safe to run repeatedly. Opt-outs:
`SKIP_PLUGINS=1 ./bootstrap/install.sh` (re-do skills/agents/hooks/settings only),
`SKIP_SKILLS=1 ./bootstrap/install.sh` (skip the third-party skill fetch).

## Cloud sessions specifically

Because cloud sessions are ephemeral, treat `install.sh` as session setup: run it at
the start of each session (or wire it into your session bootstrap). It will not
clobber anything — it backs up settings and skips already-installed items.

For the full, automatic story — cloud Setup script, declarative
`.claude/settings.json`, and the fresh-commits-only `session-sync.sh` hook — see the
canonical guide: **[`cloud-setup.md`](./cloud-setup.md)**.

## The disposable model (what you can safely delete)

After you've verified a clean install works, the **Generated** bucket is
throwaway — `install.sh` recreates it. That includes:

- third-party skill copies under `~/.claude/skills/`
- the old hand-managed skill store at `~/.agents/skills` (+ `.skill-lock.json`)
- the plugin cache under `~/.claude/plugins/cache/`

**Never delete the Runtime/account bucket** (`history.jsonl`, `projects/`,
`sessions/`, `daemon*`, `telemetry/`, `ide/`, `shell-snapshots/`, `file-history/`,
`plans/`, `tasks/`, auth/credentials) and **never delete `settings.json`** — it is
merged into, not regenerated.

See `docs/architecture.md` for the full three-bucket model.

## Verifying a clean install (smoke test)

1. A bundled skill loads (it appears in the skill list / can be invoked).
2. The `git` subagent loads and its guard hook resolves (no path error).
3. A guard hook actually fires on a denied command.
4. The statusline renders.
5. Running `install.sh` a second time reports "already installed" / no changes.

## Updating

- **Your own content:** push to the repo, then `/plugin update jiechao-toolkit`
  on each machine.
- **Third-party set or settings:** edit `bootstrap/*`, then re-run `install.sh`.
- **Pull latest from another machine:** `git pull` then re-run `install.sh`.

## Keeping the repo truthful — `scripts/export.sh`

If you ever change tooling directly in `~/.claude` (e.g. quick local prototyping),
run:

```bash
./scripts/export.sh
```

It re-copies your *own* `skills/`, `agents/`, `hooks/` from `~/.claude` into Layer A
and regenerates `manifest.json` / `skills.lock.json` from current local state.
Review the diff and commit so the repo stays canonical.
