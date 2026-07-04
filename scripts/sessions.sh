#!/bin/bash
# =============================================================================
# sessions.sh — Session-Liste für die Statusleiste (status-left) von vybemux.
# Gibt alle tmux-Sessions aus; die aktuelle Session wird als blaues Badge
# (Tokyo-Night-Akzent #7aa2f7) hervorgehoben, die anderen gemutet (#565f89).
# Die tmux-Style-Codes (#[...]) werden im status-left direkt gerendert.
#
# Aufruf aus tmux.conf:
#   status-left "#(bash ~/.tmux/scripts/sessions.sh '#S')"
# tmux expandiert #S zum Namen der aktuellen Session, bevor das Skript läuft.
# =============================================================================
set -euo pipefail

cur="${1:-}"

# Alle Sessions (eine pro Zeile). Schlägt list-sessions fehl (kein Server),
# bleibt die Ausgabe leer -> status-left ohne Liste statt Fehlermeldung.
sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)"

# Tokyo-Night-Farben als tmux-Style-Codes.
BADGE='#[fg=#1a1b26,bg=#7aa2f7,bold]'   # aktuelle Session: Akzent-Badge
MUTED='#[fg=#565f89,bg=#1a1b26]'         # andere Sessions: gemutet

while IFS= read -r name; do
    [ -z "$name" ] && continue
    if [ "$name" = "$cur" ]; then
        printf '%s %s ' "$BADGE" "$name"
    else
        printf '%s %s ' "$MUTED" "$name"
    fi
done <<< "$sessions"
