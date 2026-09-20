#!/bin/bash
# =============================================================================
# sessions.sh — Session list for vybemux's status bar (status-left).
# Prints all tmux sessions; the current session is highlighted as a blue badge
# (Tokyo Night accent #7aa2f7), while the others are muted (#565f89).
# The tmux style codes (#[...]) are rendered directly in status-left.
#
# Invoked from tmux.conf:
#   status-left "#(bash ~/.tmux/scripts/sessions.sh '#S')"
# tmux expands #S to the name of the current session before the script runs.
# =============================================================================
set -euo pipefail

cur="${1:-}"

# All sessions (one per line). If list-sessions fails (no server),
# the output stays empty -> status-left without a list instead of an error.
sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)"

# Tokyo Night colors as tmux style codes.
BADGE='#[fg=#1a1b26,bg=#7aa2f7,bold]'   # current session: accent badge
MUTED='#[fg=#565f89,bg=#1a1b26]'         # other sessions: muted

while IFS= read -r name; do
    [ -z "$name" ] && continue
    if [ "$name" = "$cur" ]; then
        printf '%s %s ' "$BADGE" "$name"
    else
        printf '%s %s ' "$MUTED" "$name"
    fi
done <<< "$sessions"
