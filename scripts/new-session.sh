#!/usr/bin/env bash
# Default session creator for tmux-conductor.
# Usage: new-session.sh <worktree-path> <session-name>
#
# Custom scripts set via @conductor-new-session-script must also set
# CONDUCTOR_SESSION on the new session, or the picker won't claim it.

wt_path="$1"
session_name="$2"

tmux new-session -d -s "$session_name" -c "$wt_path" 2>/dev/null
tmux set-environment -t "$session_name" CONDUCTOR_SESSION 1

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$session_name"
else
  tmux attach-session -t "$session_name"
fi
