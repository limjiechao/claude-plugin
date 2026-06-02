#!/usr/bin/env bash
# ~/.claude/statusline.sh
# Claude Code status line: dir | git branch | model | context usage | cost | duration
# Receives JSON on stdin.
#
# Fields used (from Claude Code statusLine JSON schema):
#   .context_window.used_percentage    — % of context window consumed (null before first message)
#   .context_window.total_input_tokens — cumulative input tokens in context
#   .cost.total_cost_usd               — estimated session cost in USD (client-side)
#   .cost.total_duration_ms            — total wall-clock time since session start, in ms
#   .rate_limits.five_hour.used_percentage — % of 5-hour rate limit used (Pro/Max only,
#   .rate_limits.seven_day.used_percentage —   present after first API response; each
#                                              window independently optional)

input=$(cat)

# -- directory: shorten to ~-relative or basename --------------------
raw_dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
home="$HOME"
case "$raw_dir" in
  "$home"/*)  short_dir="~/${raw_dir#"$home"/}" ;;
  "$home")    short_dir="~" ;;
  *)          short_dir="$raw_dir" ;;
esac

# -- git branch (skip optional locks, silent on failure) -------------
branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$raw_dir" symbolic-ref --short HEAD 2>/dev/null)

# -- git dirty state (uncommitted changes, incl. untracked files) ----
dirty=""
if [ -n "$branch" ]; then
  if [ -n "$(GIT_OPTIONAL_LOCKS=0 git -C "$raw_dir" status --porcelain 2>/dev/null)" ]; then
    dirty="1"
  fi
fi

# -- model -----------------------------------------------------------
model=$(printf '%s' "$input" | jq -r '.model.display_name // ""')

# -- context window usage --------------------------------------------
# used_percentage is pre-calculated by Claude Code; null before first API call.
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // empty')
ctx_tokens=${ctx_tokens%.*}   # strip any decimal jq may emit

# Format token count: "123k" when >= 1000, else raw. 0 is kept (e.g. right
# after /compact, total_input_tokens reads 0 until the next API call) so the
# count never silently disappears at 0%.
ctx_tokens_fmt=""
if [ -n "$ctx_tokens" ] && [ "$ctx_tokens" -ge 0 ] 2>/dev/null; then
  if [ "$ctx_tokens" -ge 1000 ]; then
    ctx_tokens_fmt=$(printf '%dk' "$(( ctx_tokens / 1000 ))")
  else
    ctx_tokens_fmt="${ctx_tokens}"
  fi
fi

# -- cost ------------------------------------------------------------
# total_cost_usd is a float; fall back to 0 when null/missing.
cost_usd=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')
cost_fmt=$(printf '$%.2f' "$cost_usd")

# -- rate limits -----------------------------------------------------
# Pro/Max only; absent for non-subscribers and before the first API call.
rl_5h=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_7d=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# -- session duration ------------------------------------------------
# total_duration_ms is wall-clock ms since session start; fall back to 0.
dur_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // 0')
dur_s=$(( ${dur_ms%.*} / 1000 ))   # integer seconds (strip any decimal jq may emit)
dur_m=$(( dur_s / 60 ))
dur_s_rem=$(( dur_s % 60 ))
if [ "$dur_m" -gt 0 ]; then
  dur_fmt="${dur_m}m ${dur_s_rem}s"
else
  dur_fmt="${dur_s_rem}s"
fi

# -- ANSI colours (will be dimmed further by Claude Code) ------------
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
DIM='\033[2m'
RESET='\033[0m'

# -- assemble --------------------------------------------------------
out=""

# directory
out="${out}${CYAN}${BOLD}${short_dir}${RESET}"

# branch (only when inside a git repo); red * when working tree is dirty
if [ -n "$branch" ]; then
  out="${out}  ${GREEN}${branch}${RESET}"
  [ -n "$dirty" ] && out="${out}${RED}*${RESET}"
fi

# model
if [ -n "$model" ]; then
  out="${out}  ${YELLOW}${model}${RESET}"
fi

# context usage — always shown; placeholder "0k|0%" before first API call
if [ -n "$ctx_pct" ]; then
  ctx_pct_int=$(printf '%.0f' "$ctx_pct")
  if [ -n "$ctx_tokens_fmt" ]; then
    ctx_seg="${GREEN}${ctx_tokens_fmt}${RESET}${DIM}|${ctx_pct_int}%${RESET}"
  else
    ctx_seg="${DIM}${ctx_pct_int}%${RESET}"
  fi
else
  ctx_seg="${GREEN}0k${RESET}${DIM}|0%${RESET}"
fi
out="${out}  ${ctx_seg}"

# rate limits — always shown; placeholder "5h·0%|7d·0%" when no data yet
if [ -n "$rl_5h" ] || [ -n "$rl_7d" ]; then
  rl_seg=""
  [ -n "$rl_5h" ] && rl_seg="${DIM}5h·${RESET}${MAGENTA}$(printf '%.0f' "$rl_5h")%${RESET}"
  if [ -n "$rl_7d" ]; then
    [ -n "$rl_seg" ] && rl_seg="${rl_seg}${DIM}|${RESET}"
    rl_seg="${rl_seg}${DIM}7d·${RESET}${MAGENTA}$(printf '%.0f' "$rl_7d")%${RESET}"
  fi
else
  rl_seg="${DIM}5h·0%|7d·0%${RESET}"
fi
out="${out}  ${rl_seg}"

# cost — always shown (shows $0.00 before first API call)
out="${out}  ${DIM}${cost_fmt}${RESET}"

# duration — always shown; "0s" at session start
out="${out}  ${DIM}${dur_fmt}${RESET}"

printf "%b\n" "$out"
