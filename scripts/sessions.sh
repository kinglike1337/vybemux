#!/bin/bash
# =============================================================================
# sessions.sh — Session list for vybemux's status bar (status-left).
# Prints all tmux sessions; the current session is highlighted as a blue badge
# (Tokyo Night accent #7aa2f7), while the others are muted (#565f89).
# The tmux style codes (#[...]) are rendered directly in status-left.
#
# Invoked from tmux.conf:
#   status-left "#(bash ~/.tmux/scripts/sessions.sh '#{session_id}')"
# tmux expands #{session_id} (its own "$N" identifier, never derived from a
# user-controlled string) before the script runs, and the session's real
# name is looked up below via tmux itself rather than embedded into the
# #(...) command line, so a name containing shell metacharacters never
# reaches sh -c as unescaped text. (The single quotes only stop sh -c from
# treating "$N" as its own positional parameter; #{session_id} itself can
# never contain a quote to break out of them.)
# =============================================================================
set -euo pipefail

cur_id="${1:-}"
cur=""
if [ -n "$cur_id" ]; then
    cur="$(tmux display-message -p -t "$cur_id" '#{session_name}' 2>/dev/null || true)"
fi

# All sessions (one per line). If list-sessions fails (no server),
# the output stays empty -> status-left without a list instead of an error.
sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)"

# Tokyo Night colors as tmux style codes.
BADGE='#[fg=#1a1b26,bg=#7aa2f7,bold]'   # current session: accent badge
MUTED='#[fg=#565f89,bg=#1a1b26]'         # other sessions: muted

# tmux parses #[...] anywhere in a status-line string, including inside this
# script's output, so a session name containing e.g. #[range=user|x] or
# #[fg=red] could restyle the bar or redefine click ranges. "##" is tmux's own
# escape for a literal "#"; the comparison below uses the raw name.
while IFS= read -r name; do
    [ -z "$name" ] && continue
    shown="${name//#/##}"
    if [ "$name" = "$cur" ]; then
        printf '%s %s ' "$BADGE" "$shown"
    else
        printf '%s %s ' "$MUTED" "$shown"
    fi
done <<< "$sessions"
