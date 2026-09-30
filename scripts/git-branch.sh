#!/bin/bash
# =============================================================================
# git-branch.sh — Current git branch for vybemux's status bar (status-right).
#
# Invoked from tmux.conf:
#   status-right "#(bash ~/.tmux/scripts/git-branch.sh #{pane_id})"
# tmux expands #{pane_id} (its own "%N" identifier, never derived from a
# user-controlled string) before the script runs, and the pane's real cwd
# is looked up below via tmux itself rather than embedded into the #(...)
# command line, so a directory name containing shell metacharacters never
# reaches sh -c as unescaped text.
# =============================================================================
set -euo pipefail

pane_id="${1:-}"
path=""
if [ -n "$pane_id" ]; then
    path="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null || true)"
fi

if [ -z "$path" ]; then
    echo '-'
    exit 0
fi

git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-'
