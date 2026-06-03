#!/usr/bin/env bash
# PreToolUse hook for Git commands.
# Global-safe: non-Git Bash commands pass through to the normal permission flow.
# Allows normal local workflow and explicit feature-branch pushes. Blocks
# protected-branch pushes, force/delete pushes, and history/working-tree
# destruction.
set -euo pipefail
cmd="$(jq -r '.tool_input.command // ""')"

# Ignore non-Git commands so this can be installed as a global Bash hook.
if ! grep -Eq '(^|&&|;|\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]|$)' <<<"$cmd"; then
  exit 0
fi

# Destructive patterns — block regardless of flag order.
deny_patterns=(
  'push[^&;|]*(--force|-f|--force-with-lease)'   # force push
  'push[^&;|]*--delete'                          # remote ref delete
  'push[^&;|]*[[:space:]]:'                      # push :branch (delete refspec)
  'branch[^&;|]*(-d|-D|--delete)'                # branch delete
  'reset[^&;|]*--hard'                           # drops commits from branch
  'reset[^&;|]*--merge'                          # can discard conflicted work
  'reset[^&;|]*--keep'                           # can discard conflicted work
  'checkout[^&;|]*[[:space:]]--[[:space:]]'       # discard tracked file changes
  'checkout[^&;|]*[[:space:]]-[a-zA-Z]*f'         # force checkout
  'restore([[:space:]]|$)'                        # discard tracked file changes
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

# Protected branch pushes are never allowed from Claude Code. This catches the
# common explicit forms; ambiguous `git push` falls through to an ask below.
protected_push_patterns=(
  'push[^&;|]*[[:space:]]origin[[:space:]]+([^[:space:]]+:)?(refs/heads/)?main([[:space:]]|$)'
  'push[^&;|]*[[:space:]]origin[[:space:]]+([^[:space:]]+:)?(refs/heads/)?master([[:space:]]|$)'
)
for p in "${protected_push_patterns[@]}"; do
  if grep -Eq "git[^&;|]*${p}" <<<"$cmd"; then
    echo "git-guard: blocked — Claude Code may not push to origin main/master ($cmd)" >&2
    exit 2
  fi
done

# Ambiguous pushes may target the current upstream, which could be protected.
# Force an explicit prompt; explicit feature-branch pushes are allowed below.
if grep -Eq 'git[^&;|]*[[:space:]]push([[:space:]]|$)' <<<"$cmd"; then
  if grep -Eq 'git[^&;|]*[[:space:]]push([[:space:]]+(-u|--set-upstream))?[[:space:]]+origin[[:space:]]+[^[:space:]-][^[:space:]]*([[:space:]]|$)' <<<"$cmd"; then
    jq -n --arg r "git-guard: explicit feature-branch push permitted" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: $r
      }
    }'
    exit 0
  else
    jq -n --arg r "git-guard: ambiguous git push requires explicit confirmation" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $r
      }
    }'
    exit 0
  fi
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
