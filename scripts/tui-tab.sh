#!/bin/bash
# =============================================================================
# tui-tab.sh — Singleton-TUI-Tab (Start-or-Switch) für vybemux.
# Stellt pro Rolle (git|files) genau ein Window in der aufrufenden Session
# sicher: existiert es -> fokussieren; sonst erzeugen + Befehl starten.
# Aufruf: tui-tab.sh <git|files>
# =============================================================================
set -euo pipefail

# Common user-PATH prefixes — tmux's run-shell inherits a reduced PATH from the
# server (often only /usr/bin:/bin), so tools installed via Homebrew, cargo, or
# ~/.local/bin are invisible. Prepend the standard user locations.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

rolle="${1:?Usage: tui-tab.sh <git|files>}"

# Befehl aus tmux-User-Option (Override-File) lesen, mit Default-Fallback.
case "$rolle" in
    git)
        cmd="$(tmux show-options -gv '@git_tui' 2>/dev/null || true)"
        cmd="${cmd:-lazygit}" ;;
    files)
        cmd="$(tmux show-options -gv '@file_tui' 2>/dev/null || true)"
        cmd="${cmd:-yazi}" ;;
    *)
        echo "tui-tab.sh: unbekannte Rolle '$rolle' (erwartet: git|files)" >&2
        exit 1 ;;
esac

# Befehl muss installiert sein, sonst keinen Tab erzeugen (leeres Window vermeiden).
if ! command -v "$cmd" >/dev/null 2>&1; then
    tmux display-message "tui-tab: '$cmd' nicht installiert (setze @${rolle}_tui)"
    exit 0
fi

# Session + Pfad der aufrufenden Session/Pane (robust auch bei detached Sessions).
session="$(tmux display -p '#{session_name}')"
cwd="$(tmux display -p '#{pane_current_path}')"

# Singleton-Window nach Name suchen (exakter Zeilenvergleich).
if tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qx "$rolle"; then
    tmux select-window -t "$session:$rolle"
else
    tmux new-window -t "$session" -n "$rolle" -c "$cwd" "$cmd"
    tmux set-window-option -t "$session:$rolle" automatic-rename off
fi
