#!/usr/bin/env bash
# PreToolUse hook for the `git` agent.
# Allows local git workflow (status/log/diff/add/commit/rebase/branch create/
# checkout/stash/merge/cherry-pick). Blocks history/branch destruction.
set -euo pipefail
cmd="$(jq -r '.tool_input.command // ""')"

# Must be a git command (allow leading `cd … &&` and env assignments loosely).
if ! grep -Eq '(^|&&|;|\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]|$)' <<<"$cmd"; then
  echo "git agent: only git commands are permitted (got: $cmd)" >&2
  exit 2
fi

# Destructive patterns — block regardless of flag order.
deny_patterns=(
  'push[^&;|]*(--force|-f|--force-with-lease)'   # force push
  'push[^&;|]*--delete'                          # remote ref delete
  'push[^&;|]*[[:space:]]:'                      # push :branch (delete refspec)
  'branch[^&;|]*(-d|-D|--delete)'                # branch delete
  'reset[^&;|]*--hard'                           # drops commits from branch
  'tag[^&;|]*(-d|--delete)'                      # tag delete
  'update-ref[^&;|]*-d'                          # raw ref delete
  'reflog[^&;|]*(delete|expire)'                 # reflog destruction
  'filter-branch|filter-repo'                    # history rewrite
  'gc[^&;|]*--prune'                             # prune unreachable objects
  'clean[^&;|]*-[a-zA-Z]*f'                      # delete untracked files
)
for p in "${deny_patterns[@]}"; do
  if grep -Eq "git[^&;|]*${p}" <<<"$cmd"; then
    echo "git agent: blocked — '$cmd' matches forbidden pattern /$p/ (no force, no delete, no history rewrite)" >&2
    exit 2
  fi
done

# Plain push (force/delete variants already blocked above) — require explicit
# user confirmation rather than a silent allow. `ask` forces a prompt even
# under `permissionMode: dontAsk`.
if grep -Eq 'git[^&;|]*[[:space:]]push([[:space:]]|$)' <<<"$cmd"; then
  jq -n --arg r "git-guard: 'git push' requires explicit confirmation" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# Allowed: emit an explicit allow decision so the command runs even under
# `permissionMode: dontAsk` (a bare `exit 0` would fall through and be denied).
jq -n --arg r "git-guard: local git op permitted" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: $r
  }
}'
exit 0
