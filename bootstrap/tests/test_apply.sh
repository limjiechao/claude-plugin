#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_fixture() {
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/apply-test.XXXXXX")"
  mkdir -p "$tmp/bin" "$tmp/claude"
  printf '%s\n' "$tmp"
}

test_own_plugin_install_failure_exits_nonzero() {
  local tmp log_file status
  tmp="$(make_fixture)"
  log_file="$tmp/apply.log"

  cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "plugin marketplace add"*) exit 0 ;;
  "plugin marketplace update"*) exit 0 ;;
  "plugin details"*) exit 1 ;;
  "plugin install jiechao-toolkit@claude-plugin"*) exit 42 ;;
  "plugin install"*) exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$tmp/bin/claude"

  set +e
  PATH="$tmp/bin:$PATH" CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >"$log_file" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "apply.sh succeeded after own plugin install failed"
  grep -q "install FAILED" "$log_file" || fail "apply.sh did not log own plugin install failure"
}

test_cache_drift_compares_plugin_source_only() {
  local tmp log_file cache_dir version_dir
  tmp="$(make_fixture)"
  log_file="$tmp/apply.log"
  cache_dir="$tmp/claude/plugins/cache/claude-plugin/jiechao-toolkit"
  version_dir="$cache_dir/0.2.2"
  mkdir -p "$version_dir"
  tar -C "$REPO_ROOT/plugins/jiechao-toolkit" -cf - . | tar -C "$version_dir" -xf -

  cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "plugin marketplace add"*) exit 0 ;;
  "plugin marketplace update"*) exit 0 ;;
  "plugin details jiechao-toolkit@claude-plugin"*) exit 0 ;;
  "plugin update jiechao-toolkit@claude-plugin"*) exit 0 ;;
  "plugin install"*) exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$tmp/bin/claude"

  PATH="$tmp/bin:$PATH" CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >"$log_file" 2>&1
  ! grep -q "DIFFERS from source" "$log_file" || fail "cache drift check compared beyond plugin source"
}

test_settings_backups_pruned_to_latest_five() {
  local tmp count
  tmp="$(make_fixture)"
  mkdir -p "$tmp/claude"
  printf '{"userKey":"keep"}' > "$tmp/claude/settings.json"
  touch -t 202601010101 "$tmp/claude/settings.json.bak.20260101010101"
  touch -t 202601010102 "$tmp/claude/settings.json.bak.20260101010201"
  touch -t 202601010103 "$tmp/claude/settings.json.bak.20260101010301"
  touch -t 202601010104 "$tmp/claude/settings.json.bak.20260101010401"
  touch -t 202601010105 "$tmp/claude/settings.json.bak.20260101010501"
  touch -t 202601010106 "$tmp/claude/settings.json.bak.20260101010601"

  CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_PLUGINS=1 SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >/dev/null 2>&1

  count="$(ls "$tmp/claude"/settings.json.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" = "5" ] || fail "expected 5 settings backups, found $count"
  [ ! -e "$tmp/claude/settings.json.bak.20260101010101" ] || fail "oldest backup was not pruned"
}

test_apply_is_idempotent() {
  local tmp first second
  tmp="$(make_fixture)"

  CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_PLUGINS=1 SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >/dev/null 2>&1
  first="$(cat "$tmp/claude/settings.json")"

  CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_PLUGINS=1 SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >/dev/null 2>&1
  second="$(cat "$tmp/claude/settings.json")"

  [ "$first" = "$second" ] || fail "apply.sh is not idempotent: settings.json changed on the second run"
}

test_apply_preserves_user_keys() {
  local tmp
  tmp="$(make_fixture)"
  printf '{"userKey":"keep","permissions":{"allow":["Bash(useronly:*)"]}}' > "$tmp/claude/settings.json"

  CLAUDE_CONFIG_DIR="$tmp/claude" SKIP_PLUGINS=1 SKIP_SKILLS=1 "$REPO_ROOT/bootstrap/apply.sh" >/dev/null 2>&1

  python3 - "$tmp/claude/settings.json" <<'PY' || fail "apply.sh clobbered user settings"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("userKey") == "keep", d
assert "Bash(useronly:*)" in d["permissions"]["allow"], d["permissions"]["allow"]
PY
}

test_own_plugin_install_failure_exits_nonzero
test_cache_drift_compares_plugin_source_only
test_settings_backups_pruned_to_latest_five
test_apply_is_idempotent
test_apply_preserves_user_keys
printf 'PASS: bootstrap apply smoke tests\n'
