# Updating & adding tools

The maintenance guide. Every new tool — yours or someone else's — lands in **this
repo**, then propagates. Never hand-add to `~/.claude` as the source of truth.

## The one rule, two directions

Everything lands in **this repo first**; the live `~/.claude` is a working copy that
gets *refreshed* from it. Which direction you move depends on **which side owns the
truth** — the full decision (and when **not** to run `apply.sh` locally) lives in
[`local-setup.md`](./local-setup.md#which-script-and-when--applysh-vs-capturesh):

- **Repo-first (preferred) — repo is authoritative.** Create the file in this repo →
  push → **refresh down** into `~/.claude`:
  - **Layer A (your own plugin):** `/plugin update jiechao-toolkit`
  - **Layer B (third-party + settings):** `./bootstrap/apply.sh`
- **Local-first (prototyping, or a multi-vendor machine) — your machine is
  authoritative.** Add it in `~/.claude` → run `scripts/capture.sh` to **read it up**
  into the repo → commit/push. The repo just mirrors your live state.

> ⚠️ On a machine that runs other AI agents and shares one skill store, only ever go
> **up** with `capture.sh` — running `apply.sh` there overwrites that shared store
> with the repo's snapshot, destroying your local source of truth. See the decision
> table in [`local-setup.md`](./local-setup.md#which-script-and-when--applysh-vs-capturesh).

> Tip: while developing Layer A locally, add the marketplace from the **local path**
> (`/plugin marketplace add ./` from the repo root) so your edits are live without a
> push. Switch to the GitHub slug for other machines and cloud.

---

## (1) Third-party — content from someone else

> Principle: **reference, never vendor.** You add a pointer; `apply.sh` fetches it.

### 1a. A third-party plugin (from a marketplace)

1. Add an entry to `bootstrap/manifest.json` under `plugins` (and add its
   marketplace under `marketplaces` if it's new):

   ```jsonc
   {
     "marketplaces": [
       { "name": "claude-plugins-official", "source": "anthropics/claude-plugins-official" }
       // add a new marketplace here if the plugin comes from one
     ],
     "plugins": [
       "superpowers@claude-plugins-official",
       "your-new-plugin@its-marketplace"      // <-- add
     ]
   }
   ```

2. Install it: `./bootstrap/apply.sh` (or, ad hoc in Claude Code,
   `/plugin install your-new-plugin@its-marketplace`).
3. `git commit -am "add your-new-plugin"` and push.

### 1b. A third-party skill (from a GitHub repo)

Two ways:

**Declare-then-install (repo-first):** add an entry to `bootstrap/skills.lock.json`:

```jsonc
{
  "skills": {
    "some-skill": {
      "source": "owner/repo",
      "sourceType": "github",
      "sourceUrl": "https://github.com/owner/repo.git",
      "skillPath": "skills/some-skill/SKILL.md"   // path to the skill within that repo
    }
  }
}
```

Then `./bootstrap/apply.sh` (clones the repo, copies the skill folder into
`~/.claude/skills/some-skill/`), then commit.

**Install-then-capture (local-first):** install the skill however you discovered it
(e.g. the find-skills workflow), then run `./scripts/capture.sh`, which regenerates
`skills.lock.json` from your live state. Review the diff, commit.

> ⚠️ `capture.sh` only captures skill folders that are **real directories** under
> `~/.claude/skills`; a **symlinked** skill is treated as third-party and **skipped**,
> so it won't land in `skills.lock.json`. If you centralize skills and symlink them in,
> use the declare-then-install path above instead. (Same caveat as in
> [`local-setup.md`](./local-setup.md#keeping-the-repo-truthful--scriptscapturesh).)

### 1c. A third-party MCP server

Third-party MCP almost always ships *inside a plugin* (e.g. `github`, `linear`,
`playwright` in `claude-plugins-official/external_plugins`). So: **add that plugin**
(see 1a). A standalone MCP server (raw `command`/`url`, no plugin) needs a
`bootstrap/mcp.json` + a merge step in `apply.sh` — not present yet; add it the
first time you need one, then document it here.

### 1d. A third-party subagent

Standalone third-party agents are rare; they normally come bundled in a plugin —
so adding the plugin (1a) brings the agent. If you genuinely have a loose agent
file you want to track, treat it like your own (see 2b) but note its upstream in a
comment so you can update it.

---

## (2) Personal — content you authored

> **Skills** (and optional personal MCP) live **inside the plugin**
> (`plugins/jiechao-toolkit/`). **Subagents and hooks** live in **`bootstrap/`** and
> are delivered by `apply.sh` into `~/.claude` — because plugin-bundled subagents
> ignore the `hooks`/`permissionMode`/`mcpServers` fields (see
> [architecture.md](./architecture.md)).

### 2a. A personal skill

1. Create `plugins/jiechao-toolkit/skills/<name>/SKILL.md` with valid frontmatter:

   ```markdown
   ---
   name: <name>
   description: >-
     One or two sentences describing exactly when this skill should trigger.
   ---

   # <Title>
   ...skill body...
   ```

2. Push, then `/plugin update jiechao-toolkit`.

### 2b. A personal subagent

1. Create `bootstrap/agents/<name>.md`:

   ```markdown
   ---
   name: <name>
   description: >-
     When to use this agent.
   tools: Bash, Read
   model: inherit
   permissionMode: dontAsk      # honored because apply.sh puts this in ~/.claude/agents
   # If it needs a guard hook, reference it with the @@HOOKS_DIR@@ token (NOT an absolute path):
   hooks:
     PreToolUse:
       - matcher: Bash
         hooks:
           - type: command
             command: "@@HOOKS_DIR@@/<guard>.sh"
   ---
   ```

2. **Invariant:** an agent's hook path uses the `@@HOOKS_DIR@@` token (rewritten by
   `apply.sh` to `$HOME/.claude/hooks`), never `/Users/...` and never
   `${CLAUDE_PLUGIN_ROOT}` (agents aren't shipped via the plugin).
3. Run `./bootstrap/apply.sh` (copies it to `~/.claude/agents`). Commit + push.

### 2c. A personal hook

1. Add the script: `bootstrap/hooks/<name>.sh` (`chmod +x`).
2. Reference it from a subagent (2b) as `@@HOOKS_DIR@@/<name>.sh`.
3. Run `./bootstrap/apply.sh` (copies it to `~/.claude/hooks`). Commit + push.

### 2d. A personal MCP server

Personal MCP can live **right in the plugin**. Add/extend
`plugins/jiechao-toolkit/.mcp.json`:

```jsonc
{
  "mcpServers": {
    "my-server": { "command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/my-server.js"] }
  }
}
```

Bundle any server code under the plugin (e.g. `plugins/jiechao-toolkit/mcp/`).
Push, then `/plugin update jiechao-toolkit`.

### 2e. Settings, permissions, or statusline

1. Edit `bootstrap/settings.snippet.json` (permissions allow/deny, notification
   prefs, `skipAutoPermissionPrompt`, `statusLine`) or `bootstrap/statusline.sh`.
2. `./bootstrap/apply.sh` re-merges into `~/.claude/settings.json` (backed up
   first) and re-copies the statusline script.
3. Commit.

---

## Quick reference

| You're adding… | Edit | Refresh | Layer |
|---|---|---|---|
| Personal skill | `plugins/jiechao-toolkit/skills/<name>/SKILL.md` | `/plugin update jiechao-toolkit` | A |
| Personal subagent | `bootstrap/agents/<name>.md` (use `@@HOOKS_DIR@@`) | `./bootstrap/apply.sh` | B |
| Personal hook | `bootstrap/hooks/<name>.sh` | `./bootstrap/apply.sh` | B |
| Personal MCP | `plugins/jiechao-toolkit/.mcp.json` | `/plugin update jiechao-toolkit` | A |
| Settings/statusline | `bootstrap/settings.snippet.json` / `statusline.sh` | `./bootstrap/apply.sh` | B |
| Third-party plugin | `bootstrap/manifest.json` | `./bootstrap/apply.sh` | B |
| Third-party skill | `bootstrap/skills.lock.json` | `./bootstrap/apply.sh` | B |
| Third-party MCP | add its plugin in `manifest.json` | `./bootstrap/apply.sh` | B |

## Don'ts

- ❌ Don't hand-edit a skill/agent in `~/.claude` and consider it done — it will be
  overwritten on the next rebuild. Mirror it into the repo (or run `capture.sh`).
- ❌ Don't copy third-party skill/plugin *source* into the repo — reference it.
- ❌ Don't use absolute `/Users/...` paths in any committed file (agent hook paths
  use the `@@HOOKS_DIR@@` token).
- ❌ Don't put subagents/hooks in the plugin — they go in `bootstrap/` (plugin
  subagents ignore `hooks`/`permissionMode`).
- ❌ Don't replace `~/.claude/settings.json` — only merge via `apply.sh`.
