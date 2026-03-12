#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Defaults — users can override these before `run tpm`
tmux set-option -gq @conductor-key                "W"
tmux set-option -gq @conductor-projects           ""
tmux set-option -gq @conductor-worktrees-dir      "$HOME/.local/share/tmux-conductor/worktrees"
tmux set-option -gq @conductor-new-session-script "$CURRENT_DIR/scripts/new-session.sh"
tmux set-option -gq @conductor-status-var         ""
tmux set-option -gq @conductor-bind-new           "ctrl-n"
tmux set-option -gq @conductor-bind-delete        "ctrl-x"
tmux set-option -gq @conductor-bind-refresh       "ctrl-r"

KEY=$(tmux show-option -gv @conductor-key)
tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/session-picker.sh"
