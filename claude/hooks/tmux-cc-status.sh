#!/usr/bin/env bash
# Publish this Claude Code session's state onto its tmux pane as the @cc
# pane option, so the pane picker (prefix + C-p) can show it and the jump
# binding (prefix + C-w) can find panes that are waiting on the user.
#
# Registered in settings.json against four hook events:
#   UserPromptSubmit -> busy     Notification -> approve | idle
#   Stop             -> idle     SessionEnd   -> (cleared)
#
# States: busy = working, idle = finished and awaiting the next prompt,
#         approve = blocked on a permission prompt.
#
# This runs on every prompt submission, so it must stay silent and fast:
# stdout from a UserPromptSubmit hook is injected into the model's context,
# and a non-zero exit blocks the prompt. Hence the unconditional exit 0.
set -uo pipefail

finish() { exit 0; }
trap finish EXIT

[[ -n "${TMUX_PANE:-}" ]] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

case "${1:-}" in
  busy|idle)
    state="${1}"
    ;;
  notification)
    # Hook payload arrives as JSON on stdin. Both messages are literal strings
    # in the Claude Code binary; matching on them avoids parsing the JSON.
    payload=$(cat 2>/dev/null || true)
    case "$payload" in
      *"needs your permission"*) state=approve ;;
      *)                         state=idle    ;;
    esac
    ;;
  clear)
    tmux set -p -t "$TMUX_PANE" -u @cc >/dev/null 2>&1
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

tmux set -p -t "$TMUX_PANE" @cc "$state" >/dev/null 2>&1
exit 0
