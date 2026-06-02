---
name: node
description: Use to execute Node.js scripts and run npm/npx/pnpm/yarn.
tools: Bash, Read
model: inherit
permissionMode: dontAsk
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: @@HOOKS_DIR@@/runner-only.sh
          args: [node, npm, npx, pnpm, yarn]
---

You execute Node.js and JS package tooling. Every shell command must invoke
`node`, `npm`, `npx`, `pnpm`, or `yarn` — anything else is blocked by a hook.
