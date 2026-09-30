#!/bin/bash
# =============================================================================
# shorten-path.sh — Shorten a path for vybemux's status bar (status-right):
# ~/long/path/to/project -> ~/l/p/t/project
#
# Invoked from tmux.conf:
#   status-right "#(bash ~/.tmux/scripts/shorten-path.sh #{pane_id})"
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

# tmux parses #[...] in this output (status-right), so a directory name such as
# "#[bg=red]x" could restyle the bar; "##" is tmux's escape for a literal "#".
if [[ -n "${HOME:-}" && ( "$path" == "$HOME" || "$path" == "$HOME"/* ) ]]; then
    path="~${path#"$HOME"}"
fi

printf '%s\n' "$path" | awk -F/ 'BEGIN{ORS=""}{for(i=1;i<NF;i++) printf "%s/", substr($i,1,1); print $NF}' | sed 's/#/##/g'
