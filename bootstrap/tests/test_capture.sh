#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/capture-test.XXXXXX")"
scratch_repo="$tmp/repo"; claude="$tmp/claude"

# Scratch repo defines the owner's skill set (two skills) + one agent.
mkdir -p "$scratch_repo/plugins/jiechao-toolkit/skills/alpha" \
         "$scratch_repo/plugins/jiechao-toolkit/skills/beta" \
         "$scratch_repo/bootstrap/agents" "$scratch_repo/bootstrap/hooks"
printf 'old\n' > "$scratch_repo/plugins/jiechao-toolkit/skills/alpha/SKILL.md"
printf 'name: git\n' > "$scratch_repo/bootstrap/agents/git.md"
printf 'name: node\n' > "$scratch_repo/bootstrap/agents/node.md"

# Live ~/.claude: own skills (real dirs) + a third-party skill (symlink) + agent + settings.
mkdir -p "$claude/skills/alpha" "$claude/skills/beta" "$claude/agents" "$claude/hooks" "$tmp/external"
printf 'new-alpha\n' > "$claude/skills/alpha/SKILL.md"
printf 'new-beta\n'  > "$claude/skills/beta/SKILL.md"
ln -s "$tmp/external" "$claude/skills/thirdparty"
printf 'name: git\nhook: %s/hooks/git-guard.sh\n' "$claude" > "$claude/agents/git.md"
printf 'name: node\nhook: /home/someoneelse/.claude/hooks/runner-only.sh\n' > "$claude/agents/node.md"
cat > "$claude/settings.json" <<JSON
{"permissions":{"allow":["Bash(ls:*)"]},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$claude/hooks/git-guard.sh"}]}]},
 "statusLine":{"type":"command","command":"bash $claude/statusline.sh"},
 "skipAutoPermissionPrompt":true}
JSON

CAPTURE_REPO_ROOT="$scratch_repo" CLAUDE_CONFIG_DIR="$claude" bash "$REPO_ROOT/scripts/capture.sh" >/dev/null

# 1) Both own skills captured with live content; third-party symlink NOT captured.
grep -q new-alpha "$scratch_repo/plugins/jiechao-toolkit/skills/alpha/SKILL.md" || fail "alpha not re-pulled"
[ -f "$scratch_repo/plugins/jiechao-toolkit/skills/beta/SKILL.md" ] || fail "beta not captured"
[ ! -e "$scratch_repo/plugins/jiechao-toolkit/skills/thirdparty" ] || fail "third-party skill captured"

# 2) Agent hook path re-tokenized.
grep -q '@@HOOKS_DIR@@/git-guard.sh' "$scratch_repo/bootstrap/agents/git.md" || fail "agent hook path not tokenized"
grep -q '@@HOOKS_DIR@@/runner-only.sh' "$scratch_repo/bootstrap/agents/node.md" \
  || fail "foreign /home agent hook path not tokenized"

# 3) Snippet keeps hooks AND re-tokenizes the path.
python3 -c "import json;d=json.load(open('$scratch_repo/bootstrap/settings.snippet.json'));assert 'hooks' in d, 'hooks dropped';assert d['hooks']['PreToolUse'][0]['hooks'][0]['command']=='@@HOOKS_DIR@@/git-guard.sh', d" \
  || fail "snippet hooks missing or not tokenized"

printf 'PASS: capture fidelity\n'
