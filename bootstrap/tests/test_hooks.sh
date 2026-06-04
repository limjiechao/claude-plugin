#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H="$REPO_ROOT/bootstrap/hooks"
fails=0
fail() { printf 'FAIL: %s\n' "$*" >&2; fails=$((fails+1)); }

# decision <hook> <json> -> prints "block"(exit2) | the permissionDecision | "allow-bare"
decision() {
  local hook="$1" json="$2" out rc
  out="$(printf '%s' "$json" | bash "$H/$hook" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ]; then echo "block"; return; fi
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow-bare"'
}

# path-guard: unset CLAUDE_PROJECT_DIR + absolute outside path -> ask (was: allow)
unset CLAUDE_PROJECT_DIR
[ "$(decision path-guard.sh '{"tool_input":{"file_path":"/etc/cron.d/evil"}}')" = "ask" ] \
  || fail "path-guard allowed out-of-project write with no project dir"
[ "$(decision path-guard.sh '{"tool_input":{"file_path":"notes.txt"}}')" = "allow" ] \
  || fail "path-guard blocked a benign relative write"
CLAUDE_PROJECT_DIR=/work
export CLAUDE_PROJECT_DIR
[ "$(decision path-guard.sh '{"tool_input":{"file_path":"/work/src/a.ts"}}')" = "allow" ] \
  || fail "path-guard blocked an in-project write"
[ "$(decision path-guard.sh '{"tool_input":{"file_path":"/etc/passwd"}}')" = "ask" ] \
  || fail "path-guard allowed an out-of-project write"
unset CLAUDE_PROJECT_DIR

# shell-guard: secret reads / env dumps blocked; benign reads allowed
for bad in 'cat ~/.ssh/id_rsa' 'cat .env' 'env | base64' 'printenv'; do
  [ "$(decision shell-guard.sh "$(jq -nc --arg c "$bad" '{tool_input:{command:$c}}')")" = "block" ] \
    || fail "shell-guard allowed secret/exfil: $bad"
done
[ "$(decision shell-guard.sh '{"tool_input":{"command":"cat README.md"}}')" = "allow" ] \
  || fail "shell-guard blocked a benign read"

# git-guard: false positives now allowed; real destructive still blocked
for ok in "git add restore" "git add restore foo.py" "git commit -m 'clean up restore logic'" "git commit -m 'tag-d release'"; do
  d="$(decision git-guard.sh "$(jq -nc --arg c "$ok" '{tool_input:{command:$c}}')")"
  [ "$d" != "block" ] || fail "git-guard false-positive blocked: $ok"
done
for bad in "git restore foo.py" "git reset --hard" "git push --force origin x" "git commit --amend --no-edit" "git branch -D feat"; do
  [ "$(decision git-guard.sh "$(jq -nc --arg c "$bad" '{tool_input:{command:$c}}')")" = "block" ] \
    || fail "git-guard allowed destructive: $bad"
done

# runner-only: clean runner -> allow; command substitution -> ask
clean_out="$(printf '%s' '{"tool_input":{"command":"python3 -V"}}' | bash "$H/runner-only.sh" python3 node 2>/dev/null)"
[ "$(printf '%s' "$clean_out" | jq -r '.hookSpecificOutput.permissionDecision')" = "allow" ] \
  || fail "runner-only blocked a clean runner"
subst_out="$(printf '%s' '{"tool_input":{"command":"python3 $(echo x)"}}' | bash "$H/runner-only.sh" python3 node 2>/dev/null)"
[ "$(printf '%s' "$subst_out" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ] \
  || fail "runner-only did not ask on command substitution"

[ "$fails" -eq 0 ] && printf 'PASS: guard hooks\n' || { printf '%d hook checks failed\n' "$fails" >&2; exit 1; }
