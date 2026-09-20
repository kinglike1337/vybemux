#!/bin/bash
# =============================================================================
# tui-tab.sh — Singleton TUI tab (Start-or-Switch) for vybemux.
# Ensures exactly one window per role (git|files) in the calling session:
# if it exists -> focus it; otherwise create it + start the command.
# Invocation: tui-tab.sh <git|files>
# =============================================================================
set -euo pipefail

# Common user-PATH prefixes — tmux's run-shell inherits a reduced PATH from the
# server (often only /usr/bin:/bin), so tools installed via Homebrew, cargo, or
# ~/.local/bin are invisible. Prepend the standard user locations.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

role="${1:?Usage: tui-tab.sh <git|files>}"

# Read command from tmux user option (override file), with a default fallback.
case "$role" in
    git)
        cmd="$(tmux show-options -gv '@git_tui' 2>/dev/null || true)"
        cmd="${cmd:-lazygit}" ;;
    files)
        cmd="$(tmux show-options -gv '@file_tui' 2>/dev/null || true)"
        cmd="${cmd:-yazi}" ;;
    *)
        echo "tui-tab.sh: unknown role '$role' (expected: git|files)" >&2
        exit 1 ;;
esac

# Command must be installed; otherwise do not create a tab (avoid an empty window).
if ! command -v "$cmd" >/dev/null 2>&1; then
    tmux display-message "tui-tab: '$cmd' is not installed (set @${role}_tui)"
    exit 0
fi

# Session + path of the calling session/pane (robust even with detached sessions).
session="$(tmux display -p '#{session_name}')"
cwd="$(tmux display -p '#{pane_current_path}')"

# Search for singleton window by name (exact line comparison).
if tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qx "$role"; then
    tmux select-window -t "$session:$role"
else
    tmux new-window -t "$session" -n "$role" -c "$cwd" "$cmd"
    tmux set-window-option -t "$session:$role" automatic-rename off
fi
