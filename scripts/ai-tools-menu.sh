#!/bin/bash
# =============================================================================
# ai-tools-menu.sh — dynamic "AI Tools" submenu for vybemux.
# Shows entries only for actually installed coding agents
# (claude/opencode/codex/pi); if a tool is missing, its entry is omitted
# entirely instead of appearing greyed out. Invoked via run-shell from a
# display-menu item (Prefix+m or [+] menu).
# =============================================================================
set -euo pipefail

# Common user-PATH prefixes — tmux's run-shell inherits a reduced PATH from the
# server (often only /usr/bin:/bin), so tools installed via Homebrew, cargo,
# ~/.local/bin, or opencode's own installer (~/.opencode/bin) are invisible.
# Prepend the standard user locations.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

# pi's installer writes its own PATH export pointing at a version-pinned
# directory (~/.local/share/pi-node/node-vX.Y.Z-linux-x64/bin) rather than a
# stable symlink, so it can't be hardcoded above — discover whatever version
# is actually installed instead.
pi_bin_dir="$(find "$HOME/.local/share/pi-node" -mindepth 2 -maxdepth 2 -type d -name bin 2>/dev/null | head -1)" || true
[ -n "$pi_bin_dir" ] && PATH="$PATH:$pi_bin_dir"

# display-menu's item commands need an explicit target-client/-pane: run-shell
# spawns this script with no client bound to it, so without -c/-t the menu
# still renders (tmux finds a client to draw it on) but a chosen item's
# command has nothing to run against and silently does nothing.
client="$(tmux display -p '#{client_name}')"
[ -z "$client" ] && client="$(tmux list-clients -F '#{client_name}' | head -1)"
pane="$(tmux display -p '#{pane_id}')"
session="$(tmux display -p '#{session_name}')"
cwd="$(tmux display -p '#{pane_current_path}')"

# A chosen item's command is executed later by the tmux server, not by this
# script, so the PATH prepend above only affects which items get *shown* —
# resolve each tool to its absolute path now and bake that into the command,
# rather than the bare name (which the server's own restricted PATH can't
# find, causing the pane to exit immediately after a brief flicker).
items=()

if claude_bin="$(command -v claude)"; then
    items+=("Claude (resume)"   c "new-window -t \"$session\" -n claude -c \"$cwd\" \"$claude_bin --resume\"")
    items+=("Claude (continue)" C "new-window -t \"$session\" -n claude -c \"$cwd\" \"$claude_bin --continue\"")
    items+=("Claude (new)"      1 "new-window -t \"$session\" -n claude -c \"$cwd\" \"$claude_bin\"")
fi

if opencode_bin="$(command -v opencode)"; then
    items+=("OpenCode (continue)" o "new-window -t \"$session\" -n opencode -c \"$cwd\" \"$opencode_bin --continue\"")
    items+=("OpenCode (new)"      2 "new-window -t \"$session\" -n opencode -c \"$cwd\" \"$opencode_bin\"")
fi

if codex_bin="$(command -v codex)"; then
    items+=("Codex (resume)"   x "new-window -t \"$session\" -n codex -c \"$cwd\" \"$codex_bin resume\"")
    items+=("Codex (continue)" X "new-window -t \"$session\" -n codex -c \"$cwd\" \"$codex_bin resume --last\"")
    items+=("Codex (new)"      3 "new-window -t \"$session\" -n codex -c \"$cwd\" \"$codex_bin\"")
fi

if pi_bin="$(command -v pi)"; then
    items+=("Pi (resume)"   p "new-window -t \"$session\" -n pi -c \"$cwd\" \"$pi_bin --resume\"")
    items+=("Pi (continue)" P "new-window -t \"$session\" -n pi -c \"$cwd\" \"$pi_bin --continue\"")
    items+=("Pi (new)"      4 "new-window -t \"$session\" -n pi -c \"$cwd\" \"$pi_bin\"")
fi

if [ "${#items[@]}" -eq 0 ]; then
    tmux display-message "ai-tools-menu: no AI coding tool installed (claude/opencode/codex/pi)"
    exit 0
fi

tmux display-menu -OM -c "$client" -t "$pane" -T "AI Tools" -x C -y C "${items[@]}"
