#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Read key with fallback — never overwrite user-set options
KEY=$(tmux show-option -gv @conductor-key 2>/dev/null)
KEY="${KEY:-W}"

tmux bind-key "$KEY" run-shell "$CURRENT_DIR/scripts/session-picker.sh"
