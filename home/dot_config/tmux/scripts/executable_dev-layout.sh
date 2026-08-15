#!/usr/bin/env bash
# dev-layout.sh — build the standard dev layout in the CURRENT window.
#
# Usage: dev-layout.sh [dir] [window-name]
#   dir          directory to open everything in   (default: current pane path)
#   window-name  rename the window                 (default: basename of dir)
set -euo pipefail

BOTTOM_PCT=50

# Anchor to the invoking pane (run-shell sets $TMUX_PANE).
top="${TMUX_PANE:-$(tmux display -p '#{pane_id}')}"

dir="${1:-$(tmux display -p -t "$top" '#{pane_current_path}')}"
name="${2:-$(basename "$dir")}"

# tmux rejects window names starting with '.', so strip leading dots
name="${name#.}"
[ -z "$name" ] && name="dev"

tmux rename-window -t "$top" -- "$name"

left="$(tmux split-window -v -l "${BOTTOM_PCT}%" -c "$dir" -P -F '#{pane_id}')"
mid="$(tmux split-window -h -t "$left" -c "$dir"  -P -F '#{pane_id}')"
right="$(tmux split-window -h -t "$mid" -c "$dir"  -P -F '#{pane_id}')"

# Force exact thirds: set the two left columns to width/3, the rest fills.
win_width="$(tmux display -p '#{window_width}')"
third="$(( win_width / 3 ))"
tmux resize-pane -t "$left" -x "$third"
tmux resize-pane -t "$mid"  -x "$third"

tmux set -p -t "$top"   @role ai       ; tmux select-pane -t "$top"   -T ai
tmux set -p -t "$left"  @role editor   ; tmux select-pane -t "$left"  -T editor
tmux set -p -t "$mid"   @role git      ; tmux select-pane -t "$mid"   -T git
tmux set -p -t "$right" @role terminal ; tmux select-pane -t "$right" -T terminal

tmux send-keys -t "$left"  'nvim .'  C-m
tmux send-keys -t "$mid"   'lazygit' C-m

tmux send-keys -t "$top" 'claude' C-m
tmux select-pane -t "$top"
