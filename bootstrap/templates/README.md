# Templates

Drop-in config for **other repos** so their Claude **cloud sessions** pick up this
source-of-truth automatically. Full explanation: [`../../docs/cloud-setup.md`](../../docs/cloud-setup.md).

This repo is **public**, so none of this needs a token or credential.

## `settings.json`

Copy to a target repo as `.claude/settings.json` (merge into an existing one if
present). It's prefilled for `limjiechao/claude-plugin` and bundles two independent,
optional conveniences:

- **`extraKnownMarketplaces` + `enabledPlugins`** — the platform auto-installs the
  `jiechao-toolkit` plugin (your skills) at session start. Skills only.
- **`hooks.SessionStart`** — runs `session-sync.sh`, which re-applies the **full**
  bootstrap only when there are fresh commits (otherwise a cheap `git ls-remote` and
  done). Clones the repo on first run.

Keep only the parts you want. If you configure the cloud **Setup script**
(recommended baseline — see the guide), you may not need this file at all.
