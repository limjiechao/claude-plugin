# Cloud setup — auto-applying this source of truth in Claude cloud sessions

How to make **Claude cloud sessions** (Claude Code on the web / claude.ai/code
sandboxes, and scheduled/remote agents) come up with your full tooling automatically.
This repo is **public**, so cloud sessions clone it with no auth.

> Sources: [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web.md),
> [hooks](https://code.claude.com/docs/en/hooks).

## Setup script (the whole thing)

In **claude.ai/code → your environment → settings → Setup script**, add:

```bash
set -euo pipefail
REPO="$HOME/claude-plugin"
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" pull --ff-only
else
  git clone https://github.com/limjiechao/claude-plugin.git "$REPO"
fi
"$REPO/bootstrap/apply.sh"
```

That's it — full tooling (plugin + third-party plugins + skills + agents + guard hooks
+ permissions/statusline), identical to local. Because the repo is public, no token,
credential, or per-repo config is required.

## Good to know

- **`~/.claude` doesn't carry over** between cloud environments, which is exactly why the
  Setup script runs `apply.sh` to (re)apply it.
- **The Setup script runs once per environment creation**, then the filesystem is cached
  (~7 days). Later sessions in that environment already have everything; it just won't
  pick up repo *updates* until the cache expires or you re-run. To always get the latest,
  add the optional hook below.
- **No account-global switch** exists for a personal account — cloud config is per
  environment ([managed settings](https://code.claude.com/docs/en/server-managed-settings.md)
  are Teams/Enterprise policy, not per-session bootstrap).

## Optional: declarative plugin (belt-and-suspenders)

Commit `.claude/settings.json` to any repo to have the platform auto-install the plugin
(your skills) at session start, even without a Setup script:

```json
{
  "extraKnownMarketplaces": {
    "claude-plugin": {
      "source": {
        "source": "github",
        "repo": "limjiechao/claude-plugin"
      }
    }
  },
  "enabledPlugins": {
    "jiechao-toolkit@claude-plugin": true
  }
}
```

Covers **skills only** (Layer A); the Setup script remains the way to get the full
tooling.

## Optional: always-latest (fresh-commits-only)

To defeat the once-per-environment caching without paying a full install every session,
add a `SessionStart` hook that runs [`../bootstrap/session-sync.sh`](../bootstrap/session-sync.sh)
(template: [`../bootstrap/templates/settings.json`](../bootstrap/templates/settings.json)):

```json
{ 
  "hooks": {
    "SessionStart": [
      { 
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "[ \"$CLAUDE_CODE_REMOTE\" = true ] || exit 0; REPO=\"$HOME/claude-plugin\"; [ -d \"$REPO/.git\" ] || git clone https://github.com/limjiechao/claude-plugin.git \"$REPO\" || exit 0; \"$REPO/bootstrap/session-sync.sh\" || true" 
          }
        ]
      }
    ]
  } 
}
```

`session-sync.sh` gates the expensive install on a **last-applied-SHA marker**
(`~/.claude/.jiechao-toolkit.sha`):

| Situation | Detected via | Action |
|---|---|---|
| Nothing changed since last apply | `ls-remote` == marker | **exit immediately** (one quick remote query, no install) |
| You pushed new commits | differ | fetch + ff-merge + `apply.sh`, record new SHA |
| Brand-new environment (marker absent) | differ (empty marker) | install once, record SHA |
| Offline / remote unreachable | falls back to local SHA | skip; session still starts |

So the common path (no new commits) costs one `git ls-remote` and skips the install.

## Recommended recipe

- **Every cloud environment:** set the **Setup script**. This alone gives full tooling.
- **Want skills even in environments with no setup script:** also commit the declarative
  `.claude/settings.json`.
- **Push often and can't wait for the ~7-day cache:** add the SessionStart hook.
