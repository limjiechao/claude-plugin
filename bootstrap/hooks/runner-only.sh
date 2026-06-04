#!/usr/bin/env bash
# PreToolUse hook for runner agents (python, node).
# Allowed runner executables are passed as args. Runners listed after a literal
# `--ask` separator are still permitted but trigger a confirmation prompt
# instead of a silent allow, e.g.:
#   runner-only.sh node npm npx pnpm      # all silent-allowed
#   runner-only.sh python3 --ask pip3     # python3 silent-allowed, pip3 prompts
# Validation is two-level:
#   Level 1 — the command is split into statements on && || ;  Each statement's
#             pipeline HEAD (first stage) must lead with an allowed runner.
#   Level 2 — within a statement, stages after a pipe (|) may lead with either a
#             runner or a read-only filter (grep, awk, sed, tail, head, …), so
#             legitimate pipes like `pnpm test | tail` are permitted.
# Note: $(...) and backtick command substitution is an inherent bypass this hook
# cannot fully inspect (the substituted command never appears as a pipeline
# head). Rather than silently allow it under dontAsk, its presence now triggers
# an `ask` decision for explicit confirmation.
set -euo pipefail
allowed_str="$*"
allowed=()
ask_runners=()
mode=allowed
for a in "$@"; do
  if [ "$a" = "--ask" ]; then mode=ask_runners; continue; fi
  if [ "$mode" = allowed ]; then allowed+=("$a"); else ask_runners+=("$a"); fi
done
cmd="$(jq -r '.tool_input.command // ""')"

# Command substitution is an inherent bypass (the substituted command never
# appears as a pipeline head). We can't inspect it, so require confirmation
# rather than silently allowing under dontAsk.
subst_ask=false
if printf '%s' "$cmd" | grep -Eq '\$\(|`'; then subst_ask=true; fi

# `in_list <needle> <items...>` — true if needle matches an item. The `:+`
# expansions keep this safe under `set -u` with empty arrays (macOS bash 3.2).
in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

# Filters permitted ONLY downstream of a pipe (never as a statement head).
filters=(grep egrep fgrep awk sed tail head cat jq sort uniq wc tr cut tee \
         less more column fold nl rev)

is_runner()     { in_list "$1" ${allowed[@]:+"${allowed[@]}"}; }
is_ask_runner() { in_list "$1" ${ask_runners[@]:+"${ask_runners[@]}"}; }
is_filter()     { in_list "$1" "${filters[@]}"; }
first_token()   { echo "$1" | sed -E 's/^[[:space:]]*//' | awk '{print $1}'; }

needs_ask=false
IFS=$'\n'
# Level 1 — split into statements on && || ;  (NOT on |)
for statement in $(echo "$cmd" | sed -E 's/(&&|\|\||;)/\n/g'); do
  [ -z "$(echo "$statement" | tr -d '[:space:]')" ] && continue
  stage_index=0
  # Level 2 — split the statement into pipeline stages on |
  for stage in $(echo "$statement" | sed -E 's/\|/\n/g'); do
    first="$(first_token "$stage")"
    [ -z "$first" ] && continue
    if [ "$stage_index" -eq 0 ]; then
      # Pipeline HEAD — must be a runner (silent or ask); filters NOT allowed here.
      if   is_runner "$first";     then :
      elif is_ask_runner "$first"; then needs_ask=true
      else
        echo "runner agent: blocked — '$first' is not an allowed runner (allowed: $allowed_str)" >&2
        exit 2
      fi
    else
      # Downstream stage — runner OR filter is acceptable.
      if   is_runner "$first";     then :
      elif is_ask_runner "$first"; then needs_ask=true
      elif is_filter "$first";     then :
      else
        echo "runner agent: blocked — '$first' is not an allowed runner or filter" >&2
        exit 2
      fi
    fi
    stage_index=$((stage_index + 1))
  done
done

if $needs_ask || $subst_ask; then
  # A prompt-list runner (e.g. pip3) or command substitution is present —
  # require explicit confirmation.
  jq -n --arg r "runner-only: command uses a runner that requires confirmation" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# Every segment is a silent-allowed runner: emit an explicit allow decision so
# the command runs under `permissionMode: dontAsk`. A bare `exit 0` carries no
# decision and falls through to the normal flow, which auto-denies under dontAsk.
jq -n --arg r "runner-only: all segments are allowed runners ($allowed_str)" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: $r
  }
}'
exit 0
