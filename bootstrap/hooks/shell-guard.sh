#!/usr/bin/env bash
# PreToolUse hook for the `shell` agent.
# The shell agent may read and write freely; this blocks catastrophic or
# system-altering commands AND secret reads / env dumps (kept in parity with the
# settings deny-list, because this hook's explicit `allow` would otherwise
# override those settings rules).
set -euo pipefail
cmd="$(jq -r '.tool_input.command // ""')"

deny_patterns=(
  'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)'  # rm -rf / -fr
  '(^|[^a-zA-Z])sudo([^a-zA-Z]|$)'                                # privilege escalation
  '(curl|wget)[^|]*\|[[:space:]]*(sh|bash|zsh)'                   # pipe-to-shell
  '(^|[^a-zA-Z])dd[[:space:]]'                                    # raw disk writes
  'mkfs|fdisk|diskutil[[:space:]]+erase'                          # filesystem destruction
  '>[[:space:]]*/dev/(sd|disk|rdisk)'                             # write to block device
  'chmod[[:space:]]+-R[[:space:]]+777'                            # recursive world-write
  ':\(\)\s*\{\s*:\s*\|\s*:'                                       # fork bomb
  'find[^&;|]*-(delete|exec[[:space:]]+rm)'                       # bulk delete via find
  'git[^&;|]*push[^&;|]*(--force|-f)'                             # force push (defense in depth)

  # Protect guard infrastructure & secrets (literal ~ and $HOME — portable, no hardcoded home).
  'rm[[:space:]]+[^|&;]*(~|\$HOME)/\.(claude|ssh)'                            # rm of ~/.claude or ~/.ssh
  '(>|>>)[[:space:]]*[^|&;]*(~|\$HOME)/\.(claude|ssh|zshrc|bashrc|gitconfig)' # clobber/append into sensitive paths
  '(mv|cp|tee)[[:space:]]+[^|&;]*(~|\$HOME)/\.(claude|ssh|zshrc)'             # mv/cp/tee over sensitive paths

  # High-value destructive gaps (balanced — plain kill/curl/launchctl still work).
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*[[:space:]]'                                           # rm -r <dir> (recursive)
  '(^|[^a-zA-Z])(pkill|killall)([[:space:]]|$)'                                             # name-based mass kill
  'kill[[:space:]]+-(9|KILL)([[:space:]]|$)'                                                # SIGKILL (plain kill <pid> ok)
  'crontab[[:space:]]+[^|&;]*-r'                                                            # wipe crontab
  'launchctl[[:space:]]+(load|unload|bootstrap|bootout|enable|disable|remove|setenv)'       # mutating launchctl only
  '(curl|wget)[[:space:]]+[^|&;]*(-T|--upload-file)'                                        # file upload (exfiltration)
  '(curl|wget)[^|&;]*--data[^[:space:]]*[[:space:]]*@'                                      # POST data-from-file (long flag)
  '(curl|wget)[^|&;]*[[:space:]]-d[[:space:]]*@'                                            # POST data-from-file (short flag)

  # Secret-file reads (settings deny-list parity; this hook's allow would
  # otherwise override those settings rules for the shell agent).
  '(cat|head|tail|less|more|bat|xxd|od|strings)[[:space:]]+[^|&;]*(\.env([^a-zA-Z]|$)|\.pem|id_rsa|id_ed25519|\.ssh/|\.aws/|\.gnupg/|credentials|secrets|\.netrc|_history)'
  # Environment dumps (common exfil source).
  '(^|[;&|][[:space:]]*)(env|printenv|set)([[:space:]]|$)'
)
for p in "${deny_patterns[@]}"; do
  if grep -Eq "$p" <<<"$cmd"; then
    echo "shell agent: blocked — '$cmd' matches forbidden pattern /$p/" >&2
    exit 2
  fi
done

# Passed the denylist: emit an explicit allow decision so the command runs
# under `permissionMode: dontAsk`. A bare `exit 0` carries no decision and
# falls through to the normal permission flow, which auto-denies under dontAsk.
jq -n --arg r "shell-guard: command cleared the denylist" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: $r
  }
}'
exit 0
