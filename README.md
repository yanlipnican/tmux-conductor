# tmux-conductor

A tmux plugin for managing git worktrees and sessions via an interactive fzf picker.

- Lists all worktrees across configured projects
- Shows open tmux sessions per worktree with status indicators
- Create new worktrees and sessions with `ctrl-n`
- Kill sessions or delete worktrees with `ctrl-x`
- Preview pane with git status, diff stats, PR info and CI checks

## Requirements

- tmux
- [fzf](https://github.com/junegunn/fzf) ≥ 0.30 (`start:reload` bind), ≥ 0.27 for popup (`-p`)
- git

Optional:
- [gh](https://cli.github.com/) + [jq](https://jqlang.github.io/jq/) — PR and CI info in preview

## Install

### Via TPM

```bash
set -g @plugin 'janlipnican/tmux-conductor'
```

Then `prefix + I` to install.

### Manual / development

```bash
git clone https://github.com/janlipnican/tmux-conductor ~/.tmux/plugins/tmux-conductor
```

Add to `tmux.conf`:

```bash
run-shell "~/.tmux/plugins/tmux-conductor/conductor.tmux"
```

## Configuration

Set options in `tmux.conf` **before** `run tpm` (or `run-shell`):

| Option | Default | Description |
|--------|---------|-------------|
| `@conductor-key` | `W` | Key binding to open the picker (`prefix + W`) |
| `@conductor-projects` | `` | Colon-separated list of git repo paths to manage |
| `@conductor-worktrees-dir` | `~/.local/share/tmux-conductor/worktrees` | Where new worktrees are created |
| `@conductor-new-session-script` | built-in `new-session.sh` | Script called to open a new session |
| `@conductor-status-var` | `` | tmux env var to read agent status from (empty = hide status column) |
| `@conductor-bind-new` | `ctrl-n` | Create new worktree |
| `@conductor-bind-delete` | `ctrl-x` | Kill session or delete worktree |
| `@conductor-bind-refresh` | `ctrl-r` | Refresh the list |

### Example

```bash
set -g @conductor-projects "$HOME/Workspace/myapp:$HOME/Workspace/other-repo"
set -g @conductor-worktrees-dir "$HOME/Workspace/worktrees"
set -g @conductor-key "W"
set -g @plugin 'janlipnican/tmux-conductor'
```

## Custom session script

By default, opening a worktree creates a plain single-window tmux session. You can replace this with any script:

```bash
set -g @conductor-new-session-script "~/.config/tmux/scripts/my-layout.sh"
```

The script receives two arguments: `<worktree-path> <session-name>`.

> **Important:** your script must set `CONDUCTOR_SESSION` on the new session, otherwise the picker won't claim it as a worktree session:
> ```bash
> tmux set-environment -t "$session_name" CONDUCTOR_SESSION 1
> ```

### Example: lazygit + editor layout

```bash
#!/usr/bin/env bash
wt_path="$1"
session_name="$2"

tmux new-session -d -s "$session_name" -c "$wt_path" 2>/dev/null
tmux set-environment -t "$session_name" CONDUCTOR_SESSION 1

PANE_LEFT=$(tmux display-message -t "${session_name}:1" -p '#{pane_id}')
PANE_RIGHT=$(tmux split-window -h -l "60%" -t "$PANE_LEFT" -c "$wt_path" -P -F '#{pane_id}')

tmux send-keys -t "$PANE_LEFT" "lazygit" Enter
tmux send-keys -t "$PANE_RIGHT" "nvim" Enter

tmux switch-client -t "$session_name" 2>/dev/null || tmux attach-session -t "$session_name"
```

## Claude Code integration (optional)

tmux-conductor can display Claude Code agent status (Working / Question / Idle) next to each session.

### 1. Enable the status column

```bash
set -g @conductor-status-var "CLAUDE_STATUS"
```

### 2. Install the hook

Create `~/.claude/hooks/tmux-status.sh`:

```bash
#!/bin/bash
EVENT="$1"
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [ -z "$CWD" ]; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  if [ -n "$SESSION_ID" ]; then
    STATUS_FILE="$HOME/.clawed-code/sessions/${SESSION_ID}.json"
    [ -f "$STATUS_FILE" ] && CWD=$(jq -r '.cwd // empty' "$STATUS_FILE" 2>/dev/null)
  fi
fi

[ -z "$CWD" ] && exit 0

if [ "$EVENT" = "Notification" ]; then
  NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
  [ "$NOTIF_TYPE" = "idle_prompt" ] && exit 0
fi

SESSION=$(tmux list-panes -a -F '#{session_name} #{pane_current_path}' 2>/dev/null | \
  while read -r s pdir; do
    [ "$pdir" = "$CWD" ] && echo "$s" && break
  done)

[ -z "$SESSION" ] && exit 0

case "$EVENT" in
  PreToolUse)   tmux set-environment -t "$SESSION" CLAUDE_STATUS working ;;
  Stop)         tmux set-environment -t "$SESSION" CLAUDE_STATUS idle ;;
  Notification) tmux set-environment -t "$SESSION" CLAUDE_STATUS needs_input ;;
esac
```

Register it in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tmux-status.sh PreToolUse", "timeout": 5 }] }],
    "Stop":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tmux-status.sh Stop",       "timeout": 5 }] }],
    "Notification":[{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tmux-status.sh Notification","timeout": 5 }] }]
  }
}
```

## License

MIT
