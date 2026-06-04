#!/usr/bin/env bash
# PreToolUse hook for the `edit` agent (matcher: Edit|Write|NotebookEdit).
# The edit agent runs in `permissionMode: acceptEdits`, so writes are otherwise
# silent. This guard hard-denies edits to sensitive paths (guard infrastructure,
# secrets, shell dotfiles) and prompts for any write outside the project dir.
set -euo pipefail

target="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""')"

# Nothing to check — let the normal flow handle it.
[ -z "$target" ] && exit 0

emit() {  # emit <decision> <reason>
  jq -n --arg d "$1" --arg r "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Expand a leading ~ to $HOME.
case "$target" in
  "~")   target="$HOME" ;;
  "~/"*) target="$HOME/${target#\~/}" ;;
esac

# `..` segments can't be string-normalized reliably — require confirmation.
case "$target" in
  *..*) emit ask "path-guard: '$target' contains '..' — confirm the resolved location" ;;
esac

# Hard-deny edits to sensitive paths.
sensitive=(
  "$HOME/.claude"
  "$HOME/.ssh"
  "$HOME/.zshrc"
  "$HOME/.bashrc"
  "$HOME/.profile"
  "$HOME/.gitconfig"
  "$HOME/.aws"
  "$HOME/.npmrc"
)
for d in "${sensitive[@]}"; do
  if [ "$target" = "$d" ] || [[ "$target" == "$d/"* ]]; then
    emit deny "path-guard: edits to $d are not permitted"
  fi
done

# Resolve relative targets against the project dir; prompt if the write lands
# outside it (allows legit cross-repo edits with an explicit confirmation).
# When no project dir is set we cannot bound the write, so any ABSOLUTE path
# must be confirmed rather than silently allowed (the edit agent runs in
# acceptEdits, so a fall-through allow would be a silent arbitrary write).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  case "$target" in
    /*) abs="$target" ;;
    *)  abs="$CLAUDE_PROJECT_DIR/$target" ;;
  esac
  if [ "$abs" != "$CLAUDE_PROJECT_DIR" ] && [[ "$abs" != "$CLAUDE_PROJECT_DIR/"* ]]; then
    emit ask "path-guard: '$target' is outside the project directory — confirm the write"
  fi
else
  case "$target" in
    /*) emit ask "path-guard: no project directory set — confirm the write to '$target'" ;;
  esac
fi

emit allow "path-guard: target path permitted"
