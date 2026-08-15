#!/usr/bin/env bash
# unwrap-layout.sh — collapse the dev layout back to the pane tagged
# @role ai, or the active pane if none is tagged.
#
# WARNING: this kills the other panes outright (nvim/lazygit/terminal).
# Any unsaved work in them is lost — same as closing a pane.
set -euo pipefail

# Anchor to the invoking pane (run-shell sets $TMUX_PANE).
tgt="${TMUX_PANE:-$(tmux display -p '#{pane_id}')}"

keep="$(
  tmux list-panes ${tgt:+-t "$tgt"} -F '#{@role} #{pane_id}' \
    | awk '$1 == "ai" { print $2; exit }'
)"
keep="${keep:-$tgt}"

tmux kill-pane -a -t "$keep"
tmux select-pane -t "$keep"
