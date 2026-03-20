#!/bin/bash
# tmux-conductor: interactive git worktree / session picker

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'

LABEL_IDLE=' worktrees — ctrl-r to refresh '
LABEL_LOADING=' worktrees — loading... '

generate() {
  local SESSIONS CURRENT_SESSION MAIN_DIRS CLAIMED_SESSIONS

  SESSIONS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  CURRENT_SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)

  # Build MAIN_DIRS from configured projects only
  MAIN_DIRS=""
  local PROJECTS
  PROJECTS=$(tmux show-option -gv @conductor-projects 2>/dev/null || echo "")
  if [ -n "$PROJECTS" ]; then
    IFS=':' read -ra PROJECT_LIST <<< "$PROJECTS"
    for proj in "${PROJECT_LIST[@]}"; do
      proj="${proj/#\~/$HOME}"
      [ -d "$proj" ] && MAIN_DIRS="$MAIN_DIRS"$'\n'"$proj"
    done
  fi
  MAIN_DIRS=$(echo "$MAIN_DIRS" | sort -u | grep -v '^$')

  local STATUS_VAR
  STATUS_VAR=$(tmux show-option -gv @conductor-status-var 2>/dev/null || echo "")

  CLAIMED_SESSIONS=""

  # Pass 1: collect all row data and compute max column widths
  declare -a R_TYPE R_PREFIX R_NAME R_BRANCH R_WT_PATH R_WT_BRANCH R_SESSION_NAME R_REPO R_STATUS_ICON
  local max_name=4     # min = len("NAME")
  local max_branch=6   # min = len("BRANCH")
  local idx=0

  while IFS= read -r main_dir; do
    [ -z "$main_dir" ] && continue
    local repo_name
    repo_name=$(basename "$main_dir")

    declare -a AT_PREFIX AT_NAME AT_BRANCH AT_PATH AT_WBRANCH AT_SNAME AT_CICON
    declare -a IT_PREFIX IT_NAME IT_BRANCH IT_PATH IT_WBRANCH IT_SNAME IT_CICON
    AT_PREFIX=(); AT_NAME=(); AT_BRANCH=(); AT_PATH=(); AT_WBRANCH=(); AT_SNAME=(); AT_CICON=()
    IT_PREFIX=(); IT_NAME=(); IT_BRANCH=(); IT_PATH=(); IT_WBRANCH=(); IT_SNAME=(); IT_CICON=()
    local ac=0 ic=0

    while IFS= read -r wt_line; do
      local wt_path wt_branch branch_display session_name session_col prefix
      wt_path=$(echo "$wt_line" | awk '{print $1}')
      wt_branch=$(echo "$wt_line" | awk '{print $3}' | tr -d '[]')
      [ -z "$wt_path" ] && continue

      branch_display=$(echo "$wt_branch" | sed 's|^[^/]*/||')
      dir_name=$(basename "$wt_path")

      session_name=""
      if [ -n "$SESSIONS" ]; then
        while IFS= read -r s; do
          local s_dir
          s_dir=$(tmux display-message -t "${s}:1.1" -p '#{pane_current_path}' 2>/dev/null)
          if [ "$s_dir" = "$wt_path" ] && tmux show-environment -t "$s" CONDUCTOR_SESSION 2>/dev/null | grep -q '^CONDUCTOR_SESSION='; then
            session_name="$s"
            break
          fi
        done <<< "$SESSIONS"
      fi

      local status_icon=""
      if [ -n "$session_name" ]; then
        session_col="$session_name"
        CLAIMED_SESSIONS="$CLAIMED_SESSIONS"$'\n'"$session_name"
        [ "$session_name" = "$CURRENT_SESSION" ] && prefix="  ▶ " || prefix="  ${GREEN}●${RESET} "
        if [ -n "$STATUS_VAR" ]; then
          local status_val
          status_val=$(tmux show-environment -t "$session_name" "$STATUS_VAR" 2>/dev/null | cut -d= -f2)
          case "$status_val" in
            working)     status_icon="  ${CYAN}Working${RESET}" ;;
            needs_input) status_icon="  ${YELLOW}Question${RESET}" ;;
            *)           status_icon="  ${DIM}Idle${RESET}" ;;
          esac
        fi
      else
        session_col="-"
        session_name="-"
        prefix="  ${DIM}○${RESET} "
      fi

      local nlen blen
      nlen=${#dir_name}; [ $nlen -gt $max_name ] && max_name=$nlen
      blen=${#branch_display}; [ $blen -gt $max_branch ] && max_branch=$blen

      if [ "$session_col" != "-" ]; then
        AT_PREFIX[$ac]="$prefix"; AT_NAME[$ac]="$dir_name"; AT_BRANCH[$ac]="$branch_display"
        AT_PATH[$ac]="$wt_path"; AT_WBRANCH[$ac]="$wt_branch"; AT_SNAME[$ac]="$session_name"; AT_CICON[$ac]="$status_icon"
        ac=$((ac + 1))
      else
        IT_PREFIX[$ic]="$prefix"; IT_NAME[$ic]="$dir_name"; IT_BRANCH[$ic]="$branch_display"
        IT_PATH[$ic]="$wt_path"; IT_WBRANCH[$ic]="$wt_branch"; IT_SNAME[$ic]="$session_name"; IT_CICON[$ic]="$status_icon"
        ic=$((ic + 1))
      fi
    done <<< "$(git -C "$main_dir" worktree list)"

    # Header + active rows first + inactive rows
    R_TYPE[$idx]="header"; R_REPO[$idx]="$repo_name"
    R_WT_PATH[$idx]="$main_dir"; R_WT_BRANCH[$idx]="HEADER"; R_SESSION_NAME[$idx]="HEADER"
    idx=$((idx + 1))

    for ((j = 0; j < ac; j++)); do
      R_TYPE[$idx]="row"; R_PREFIX[$idx]="${AT_PREFIX[$j]}"
      R_NAME[$idx]="${AT_NAME[$j]}"; R_BRANCH[$idx]="${AT_BRANCH[$j]}"
      R_WT_PATH[$idx]="${AT_PATH[$j]}"; R_WT_BRANCH[$idx]="${AT_WBRANCH[$j]}"; R_SESSION_NAME[$idx]="${AT_SNAME[$j]}"; R_STATUS_ICON[$idx]="${AT_CICON[$j]}"
      idx=$((idx + 1))
    done
    for ((j = 0; j < ic; j++)); do
      R_TYPE[$idx]="row"; R_PREFIX[$idx]="${IT_PREFIX[$j]}"
      R_NAME[$idx]="${IT_NAME[$j]}"; R_BRANCH[$idx]="${IT_BRANCH[$j]}"
      R_WT_PATH[$idx]="${IT_PATH[$j]}"; R_WT_BRANCH[$idx]="${IT_WBRANCH[$j]}"; R_SESSION_NAME[$idx]="${IT_SNAME[$j]}"; R_STATUS_ICON[$idx]="${IT_CICON[$j]}"
      idx=$((idx + 1))
    done
  done <<< "$MAIN_DIRS"

  # Append sessions not matched to any project worktree
  if [ -n "$SESSIONS" ]; then
    local has_other=0
    while IFS= read -r session; do
      [ -z "$session" ] && continue
      echo "$CLAIMED_SESSIONS" | grep -qxF "$session" && continue

      if [ $has_other -eq 0 ]; then
        R_TYPE[$idx]="header"; R_REPO[$idx]="other"
        R_WT_PATH[$idx]="HEADER"; R_WT_BRANCH[$idx]="HEADER"; R_SESSION_NAME[$idx]="HEADER"
        idx=$((idx + 1))
        has_other=1
      fi

      local s_dir
      s_dir=$(tmux display-message -t "${session}:1.1" -p '#{pane_current_path}' 2>/dev/null)

      local prefix
      [ "$session" = "$CURRENT_SESSION" ] && prefix="  ▶ " || prefix="  ${GREEN}●${RESET} "

      local nlen
      nlen=${#session}; [ $nlen -gt $max_name ] && max_name=$nlen

      local other_status_icon=""
      if [ -n "$STATUS_VAR" ]; then
        local other_status_val
        other_status_val=$(tmux show-environment -t "$session" "$STATUS_VAR" 2>/dev/null | cut -d= -f2)
        case "$other_status_val" in
          working)     other_status_icon="  ${CYAN}Working${RESET}" ;;
          needs_input) other_status_icon="  ${YELLOW}Question${RESET}" ;;
          *)           other_status_icon="  ${DIM}Idle${RESET}" ;;
        esac
      fi

      R_TYPE[$idx]="row"; R_PREFIX[$idx]="$prefix"
      R_NAME[$idx]="$session"; R_BRANCH[$idx]="—"
      R_WT_PATH[$idx]="$s_dir"; R_WT_BRANCH[$idx]="-"; R_SESSION_NAME[$idx]="$session"; R_STATUS_ICON[$idx]="$other_status_icon"
      idx=$((idx + 1))
    done <<< "$SESSIONS"
  fi

  [ $idx -eq 0 ] && return

  # Pass 2: output header line (for --header-lines=1), then rows
  local h_name h_branch h_status
  h_name=$(printf "%-${max_name}s" "NAME")
  h_branch=$(printf "%-${max_branch}s" "BRANCH")
  [ -n "$STATUS_VAR" ] && h_status="  STATUS" || h_status=""
  printf "    ${DIM}%s  %s%s${RESET}\tHEADER\tHEADER\tHEADER\n" "$h_name" "$h_branch" "$h_status"

  local lines=""
  for ((i = 0; i < idx; i++)); do
    if [ "${R_TYPE[$i]}" = "header" ]; then
      lines+="${BOLD}${CYAN}  ${R_REPO[$i]}${RESET}"$'\t'HEADER$'\t'HEADER$'\t'HEADER$'\n'
    else
      local col_name col_branch
      col_name=$(printf "%-${max_name}s" "${R_NAME[$i]}")
      col_branch=$(printf "%-${max_branch}s" "${R_BRANCH[$i]}")
      lines+="${R_PREFIX[$i]}${col_name}  ${DIM}${col_branch}${RESET}${R_STATUS_ICON[$i]}"$'\t'"${R_WT_PATH[$i]}"$'\t'"${R_WT_BRANCH[$i]}"$'\t'"${R_SESSION_NAME[$i]}"$'\n'
    fi
  done

  printf '%s' "$lines"
}

if [ "$1" = "--generate" ]; then
  generate
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────────────────

_new_session_script() {
  local script
  script=$(tmux show-option -gv @conductor-new-session-script 2>/dev/null)
  echo "${script:-$PLUGIN_DIR/scripts/new-session.sh}"
}

_computed_name() {
  local wt_path="$1" wt_branch="$2"
  local repo_name branch_clean
  repo_name=$(basename "$(git -C "$wt_path" worktree list 2>/dev/null | awk 'NR==1{print $1}')")
  branch_clean=$(echo "$wt_branch" | sed 's|^[^/]*/||; s|/|-|g')
  echo "$repo_name-$branch_clean"
}

# ── Subcommands ───────────────────────────────────────────────────────────

if [ "$1" = "--create" ]; then
  wt_path="$2"
  [ "$wt_path" = "HEADER" ] && exit 0

  main_dir=$(git -C "$wt_path" worktree list 2>/dev/null | awk 'NR==1{print $1}')
  repo_name=$(basename "$main_dir")

  local_worktrees_dir=$(tmux show-option -gv @conductor-worktrees-dir 2>/dev/null || echo "$HOME/.local/share/tmux-conductor/worktrees")
  local_worktrees_dir="${local_worktrees_dir/#\~/$HOME}"

  # Step 1: enter worktree name
  read -rp "Worktree name: " wt_name </dev/tty
  [ -z "$wt_name" ] && exit 0

  # Step 2: pick base branch (default: master or main)
  if git -C "$main_dir" rev-parse --verify master &>/dev/null; then
    default_base="master"
  elif git -C "$main_dir" rev-parse --verify main &>/dev/null; then
    default_base="main"
  else
    default_base=""
  fi
  base_branch=$(git -C "$main_dir" branch -a --format '%(refname:short)' \
    | sed 's|^origin/||' | sort -u \
    | fzf --prompt "Base branch: " --height 10 --reverse --border \
          --border-label " base branch " --query "$default_base" --select-1)
  [ -z "$base_branch" ] && exit 0

  # Step 3: enter branch name (pre-filled with worktree name), re-prompt if already exists
  while true; do
    read -rp "Branch name: " -i "$wt_name" -e branch </dev/tty
    [ -z "$branch" ] && exit 0
    if git -C "$main_dir" rev-parse --verify "$branch" &>/dev/null; then
      echo "Branch '$branch' already exists, choose a different name."
    else
      break
    fi
  done

  wt_new="$local_worktrees_dir/$repo_name/$wt_name"
  mkdir -p "$(dirname "$wt_new")"
  git -C "$main_dir" worktree add "$wt_new" -b "$branch" "$base_branch"

  "$(_new_session_script)" "$wt_new" "$wt_name"
  exit 0
fi

if [ "$1" = "--preview" ]; then
  wt_path="$2"
  [ "$wt_path" = "HEADER" ] && exit 0

  RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
  GREEN=$'\033[32m'; RED=$'\033[31m'; CYAN=$'\033[36m'; YELLOW=$'\033[33m'

  if git -C "$wt_path" rev-parse --git-dir &>/dev/null 2>&1; then
    branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf "${BOLD}  %s${RESET}\n" "$branch"
  fi
  printf "${DIM}  %s${RESET}\n" "${wt_path/#$HOME/\~}"

  git -C "$wt_path" rev-parse --git-dir &>/dev/null 2>&1 || exit 0
  printf "\n"

  # Uncommitted changes
  status_lines=$(git -C "$wt_path" status --short 2>/dev/null)
  if [ -n "$status_lines" ]; then
    printf "${DIM}  uncommitted${RESET}\n"
    echo "$status_lines" | head -10 | while IFS= read -r line; do
      printf "  %s\n" "$line"
    done
    total=$(echo "$status_lines" | wc -l | tr -d ' ')
    [ "$total" -gt 10 ] && printf "${DIM}  … %d more${RESET}\n" $((total - 10))
    printf "\n"
  fi

  # Diff stats vs base branch
  base=""
  git -C "$wt_path" rev-parse --verify master &>/dev/null && base="master"
  [ -z "$base" ] && git -C "$wt_path" rev-parse --verify main &>/dev/null && base="main"
  if [ -n "$base" ]; then
    shortstat=$(git -C "$wt_path" diff --shortstat "${base}...HEAD" 2>/dev/null)
    if [ -n "$shortstat" ]; then
      added=$(echo "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
      removed=$(echo "$shortstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
      files=$(echo "$shortstat" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
      [ -z "$added" ] && added=0; [ -z "$removed" ] && removed=0
      printf "  ${GREEN}+%s${RESET} ${RED}−%s${RESET}  ${DIM}%s files vs %s${RESET}\n\n" "$added" "$removed" "$files" "$base"
    fi
  fi

  # Pull request + CI
  if command -v gh &>/dev/null; then
    pr_json=$(cd "$wt_path" && gh pr view --json number,title,state,reviewDecision,statusCheckRollup,url 2>/dev/null)
    if [ -n "$pr_json" ]; then
      pr_number=$(echo "$pr_json" | jq -r '.number')
      pr_title=$(echo "$pr_json" | jq -r '.title')
      pr_state=$(echo "$pr_json" | jq -r '.state')
      pr_review=$(echo "$pr_json" | jq -r '.reviewDecision // ""')

      case "$pr_state" in
        OPEN)   state_fmt="${GREEN}open${RESET}" ;;
        MERGED) state_fmt="${CYAN}merged${RESET}" ;;
        CLOSED) state_fmt="${RED}closed${RESET}" ;;
        *)      state_fmt="${DIM}${pr_state,,}${RESET}" ;;
      esac
      case "$pr_review" in
        APPROVED)           review_fmt="  ${GREEN}✓ approved${RESET}" ;;
        CHANGES_REQUESTED)  review_fmt="  ${RED}✗ changes requested${RESET}" ;;
        REVIEW_REQUIRED)    review_fmt="  ${YELLOW}◌ needs review${RESET}" ;;
        *)                  review_fmt="" ;;
      esac

      printf "${DIM}  pull request${RESET}\n"
      printf "  ${BOLD}#%s${RESET}  %s\n" "$pr_number" "$pr_title"
      pr_url=$(echo "$pr_json" | jq -r '.url')
      printf "  %s%s\n" "$state_fmt" "$review_fmt"
      printf "  ${DIM}%s${RESET}\n" "$pr_url"

      checks=$(echo "$pr_json" | jq -c '.statusCheckRollup[]?' 2>/dev/null)
      if [ -n "$checks" ]; then
        printf "\n${DIM}  ci${RESET}\n"
        echo "$checks" | while IFS= read -r check; do
          name=$(echo "$check" | jq -r '.name')
          conclusion=$(echo "$check" | jq -r '.conclusion // .status // ""')
          case "$conclusion" in
            SUCCESS)         icon="${GREEN}✓${RESET}" ;;
            FAILURE)         icon="${RED}✗${RESET}" ;;
            IN_PROGRESS)     icon="${YELLOW}~${RESET}" ;;
            PENDING|QUEUED)  icon="${YELLOW}◌${RESET}" ;;
            SKIPPED|NEUTRAL) icon="${DIM}−${RESET}" ;;
            *)               icon="${DIM}?${RESET}" ;;
          esac
          printf "  %s  %s\n" "$icon" "$name"
        done
      fi
    fi
  fi
  exit 0
fi

if [ "$1" = "--delete" ]; then
  wt_path="$2"
  session_name="$3"
  [ "$wt_path" = "HEADER" ] && exit 0    # column header line
  [ "$session_name" = "HEADER" ] && exit 0  # project group header

  if [ "$session_name" != "-" ]; then
    confirm=$(printf 'no\nyes' | fzf --prompt "Kill session $session_name? " --height 4 --reverse)
    [ "$confirm" = "yes" ] && tmux kill-session -t "$session_name"
  else
    branch_name=$(basename "$wt_path")
    confirm=$(printf 'no\nyes' | fzf --prompt "Delete worktree $branch_name? " --height 4 --reverse)
    if [ "$confirm" = "yes" ]; then
      git -C "$wt_path" worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"
    fi
  fi
  exit 0
fi

# ── Read configurable binds ───────────────────────────────────────────────

BIND_NEW=$(tmux show-option -gv @conductor-bind-new 2>/dev/null || echo "ctrl-n")
BIND_DELETE=$(tmux show-option -gv @conductor-bind-delete 2>/dev/null || echo "ctrl-x")
BIND_REFRESH=$(tmux show-option -gv @conductor-bind-refresh 2>/dev/null || echo "ctrl-r")

HEADER="  $(printf '\e[2m')enter$(printf '\e[0m') open  $(printf '\e[2m')${BIND_NEW}$(printf '\e[0m') new  $(printf '\e[2m')${BIND_DELETE}$(printf '\e[0m') delete  $(printf '\e[2m')${BIND_REFRESH}$(printf '\e[0m') refresh"

# ── Main fzf picker ───────────────────────────────────────────────────────

selected=$(fzf-tmux -p 92%,80% \
  --ansi \
  --delimiter $'\t' \
  --with-nth 1 \
  --layout=reverse \
  --header-lines=1 \
  --header "$HEADER" \
  --border-label "$LABEL_LOADING" \
  --prompt '  ' \
  --no-sort \
  --preview "$0 --preview {2}" \
  --preview-window 'right:42%:border-left' \
  --preview-label ' detail ' \
  --bind "start:reload($0 --generate)" \
  --bind "load:change-border-label($LABEL_IDLE)" \
  --bind "$BIND_REFRESH:change-border-label($LABEL_LOADING)+reload($0 --generate)" \
  --bind "$BIND_NEW:execute($0 --create {2})+abort" \
  --bind "$BIND_DELETE:execute($0 --delete {2} {4})+reload($0 --generate)")

[ -z "$selected" ] && exit 0

wt_path=$(echo "$selected" | cut -f2)
wt_branch=$(echo "$selected" | cut -f3)
session_name=$(echo "$selected" | cut -f4)

[ "$wt_path" = "HEADER" ] && exit 0

if [ "$session_name" = "-" ]; then
  "$(_new_session_script)" "$wt_path" "$(basename "$wt_path")"
else
  tmux switch-client -t "$session_name"
fi
