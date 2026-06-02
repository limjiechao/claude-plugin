# Local setup & rebuild

How to reconstruct your full Claude tooling layer on a **local machine** — and how the
disposable/regenerated model works in practice. For auto-applying it in **Claude cloud
sessions**, see [`cloud-setup.md`](./cloud-setup.md).

## Which script, and when? — `apply.sh` vs `capture.sh`

The two scripts move data in **opposite directions**. Choose by *which side owns the
truth* on the environment you're in.

| | `bootstrap/apply.sh` | `scripts/capture.sh` |
|---|---|---|
| **Direction** | repo → `~/.claude` (writes/overwrites the working copy) | `~/.claude` → repo (reads live state up) |
| **Who is authoritative** | the **repo** — it overwrites/merges into `~/.claude` | your **machine** — the repo just mirrors it |
| **Use it for** | cloud sessions; Claude-only local machines | multi-vendor local machines that only want cloud sessions to match |

### Use `apply.sh` when…

- **You're in a Claude cloud session — always.** Cloud `~/.claude` is ephemeral and
  Claude is the only agent there, so the repo *should* be authoritative. This is what
  the cloud Setup script runs (see [`cloud-setup.md`](./cloud-setup.md)).
- **Your local machine runs Claude Code and no other AI agent.** Then `~/.claude` can
  safely be a regenerated working copy of the repo — exactly the model the Prime
  Directive in `CLAUDE.md` assumes.

> ⚠️ **Do not run `apply.sh` locally if you run more than one AI agent (e.g. Claude
> *and* Cursor) and share one global skill store across them.** `apply.sh` copies
> skills, agents, hooks, and merged settings *into* `~/.claude`. If `~/.claude/skills`
> is (or symlinks into) your shared global store, apply.sh overwrites or shadows it
> with the repo's snapshot — **destroying the single source of truth on your machine**:
> the repo silently wins over the store you actually edit from, and your other vendors
> drift. On a multi-vendor machine your *local* store is the source of truth and the
> repo is downstream of it. Use `capture.sh` instead (next).

### Use `capture.sh` when…

- **You run more than one AI agent, centralize your skills in one store on the machine
  and symlink that store into each vendor (Claude, Cursor, …), and you only want Claude
  *cloud* sessions to carry the same skills.**

  Here the **machine — not the repo — is the source of truth.** `capture.sh` reads your
  live `~/.claude` state *up into the repo*; you commit and push; then **cloud** sessions
  (which *do* run `apply.sh`) come up with the same skills. Your local `~/.claude` is
  never overwritten, so the central store you share with Cursor stays intact.

- It's also the right tool any time you hand-edited something in `~/.claude` while
  prototyping and want the repo to catch up before committing (the "local-first"
  workflow in `CLAUDE.md`).

**In one line:** cloud and Claude-only-local → `apply.sh`. Multi-vendor local that
just needs cloud parity → `capture.sh`, **and never `apply.sh` locally.**

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
./claude-plugin/bootstrap/apply.sh
```

`apply.sh` will:
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
`SKIP_PLUGINS=1 ./bootstrap/apply.sh` (re-do skills/agents/hooks/settings only),
`SKIP_SKILLS=1 ./bootstrap/apply.sh` (skip the third-party skill fetch).

## Cloud sessions specifically

Because cloud sessions are ephemeral, treat `apply.sh` as session setup: run it at
the start of each session (or wire it into your session bootstrap). It will not
clobber anything — it backs up settings and skips already-installed items.

For the full, automatic story — cloud Setup script, declarative
`.claude/settings.json`, and the fresh-commits-only `session-sync.sh` hook — see the
canonical guide: **[`cloud-setup.md`](./cloud-setup.md)**.

## The disposable model (what you can safely delete)

After you've verified a clean install works, the **Generated** bucket is
throwaway — `apply.sh` recreates it. That includes:

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
5. Running `apply.sh` a second time reports "already installed" / no changes.

## Updating

- **Your own content:** push to the repo, then `/plugin update jiechao-toolkit`
  on each machine.
- **Third-party set or settings:** edit `bootstrap/*`, then re-run `apply.sh`.
- **Pull latest from another machine:** `git pull`, then re-run `apply.sh`.

(The two `apply.sh` steps above assume a repo-authoritative environment — cloud, or a
Claude-only machine. On a multi-vendor local machine, don't run `apply.sh`; sync the
other way with `capture.sh` — see [Which script, and when?](#which-script-and-when--applysh-vs-capturesh).)

## Keeping the repo truthful — `scripts/capture.sh`

This is the **machine → repo** direction (see [Which script, and when?](#which-script-and-when--applysh-vs-capturesh)
above). Reach for it when your *local* `~/.claude` is the source of truth — a
multi-vendor machine that only needs cloud parity, or after quick local prototyping —
and you want the repo to catch up so a push propagates to cloud sessions.

```bash
./scripts/capture.sh
```

It re-copies your *own* `skills/`, `agents/`, `hooks/` from `~/.claude` into Layer A
(re-tokenizing hook paths as `@@HOOKS_DIR@@`) and regenerates
`skills.lock.json` / `settings.snippet.json` / `statusline.sh` from current local
state. Review the diff and commit so the repo stays canonical, then push — that's what
carries the state to cloud, where `apply.sh` reapplies it.

> **Caveat for symlinked stores.** `capture.sh` treats a **symlinked** skill folder
> under `~/.claude/skills` as third-party and **skips** it (it only copies real
> directories). So if you centralize skills elsewhere and symlink them *into*
> `~/.claude/skills`, point your real store at `~/.claude/skills` (and symlink *out*
> to the other vendors), or `capture.sh` won't pick your own skills up. If your layout
> is the reverse, the capture step that gathers owner-authored skills needs adjusting — flag it.
