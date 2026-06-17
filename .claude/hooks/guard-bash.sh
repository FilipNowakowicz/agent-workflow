#!/usr/bin/env bash
# PreToolUse guard for Bash. Blocks `git commit` invocations whose message
# would carry a Claude/Anthropic co-author trailer — this repo's commits
# never add one (see CONTRIBUTING.md). Backed up by the .githooks/commit-msg
# git hook, which catches the same thing outside Claude Code.
set -uo pipefail

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
else
  cmd=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')
fi

[ -z "${cmd:-}" ] && exit 0

case "$cmd" in
*git\ commit*) ;;
*) exit 0 ;;
esac

if printf '%s' "$cmd" | grep -Eiq 'co-authored-by:[^"'"'"']*(claude|anthropic)|claude-session:'; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This repo never adds a Claude/Anthropic co-author trailer to commits. Remove the Co-Authored-By / Claude-Session line and retry."}}\n'
  exit 0
fi

exit 0
