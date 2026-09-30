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
# command has nothing to run against and silently does nothing. -t also
# anchors the #{...} formats below: they resolve against this same pane.
client="$(tmux display -p '#{client_name}')"
[ -z "$client" ] && client="$(tmux list-clients -F '#{client_name}' | head -1)"
pane="$(tmux display -p '#{pane_id}')"

# tmux substitutes #{...} formats into an item's command *text* before
# tokenizing it (menu_add_item() in tmux's source) — so merely swapping a
# bash-resolved $session/$cwd for a literal #{session_name}/#{pane_current_path}
# does NOT fix the injection this replaces (a name containing ", ;, or $
# still terminates the argument early either way).
#
# Escaping the value (tmux's "q:" format modifier, #{q:pane_current_path})
# isn't enough either: it backslash-escapes the characters tmux's own parser
# treats specially while unquoted (quotes, ;, $, #, whitespace, ...), but
# NOT a literal newline or tab — and tmux's parser ends the current command
# at an unquoted newline and splits tokens at an unquoted tab, so a
# directory name containing either still lets the rest be parsed as a
# separate command, unescaped.
#
# What actually works is deferring expansion instead of escaping the result:
#   - #{session_id} ("$N") is an inert identifier tmux assigns itself, like
#     #{pane_id} elsewhere in this repo — never derived from a user string,
#     so there's no value to escape or defer;
#   - "##{pane_current_path}" — tmux replaces "##" with a literal "#" during
#     the same expansion pass, without re-expanding what follows — so this
#     item's *stored* command, after menu_add_item() expands it, literally
#     contains -c "#{pane_current_path}" as text. Only when the item is
#     chosen and new-window's own -c handling expands *that* placeholder
#     (a normal, per-argument expansion every tmux command does after its
#     own arguments are already parsed) does the real path appear — as a
#     value substituted into an argument slot that parsing has already
#     closed, not as text tmux's parser ever re-tokenizes. No character in
#     the path, including a newline or tab, can affect parsing this way.
# $claude_bin/etc. don't need this: they're from `command -v`, a PATH lookup
# this script already trusts, never a directory/session name.
items=()

if claude_bin="$(command -v claude)"; then
    items+=("Claude (resume)"   c "new-window -t #{session_id} -n claude -c \"##{pane_current_path}\" \"$claude_bin --resume\"")
    items+=("Claude (continue)" C "new-window -t #{session_id} -n claude -c \"##{pane_current_path}\" \"$claude_bin --continue\"")
    items+=("Claude (new)"      1 "new-window -t #{session_id} -n claude -c \"##{pane_current_path}\" \"$claude_bin\"")
fi

if opencode_bin="$(command -v opencode)"; then
    items+=("OpenCode (continue)" o "new-window -t #{session_id} -n opencode -c \"##{pane_current_path}\" \"$opencode_bin --continue\"")
    items+=("OpenCode (new)"      2 "new-window -t #{session_id} -n opencode -c \"##{pane_current_path}\" \"$opencode_bin\"")
fi

if codex_bin="$(command -v codex)"; then
    items+=("Codex (resume)"   x "new-window -t #{session_id} -n codex -c \"##{pane_current_path}\" \"$codex_bin resume\"")
    items+=("Codex (continue)" X "new-window -t #{session_id} -n codex -c \"##{pane_current_path}\" \"$codex_bin resume --last\"")
    items+=("Codex (new)"      3 "new-window -t #{session_id} -n codex -c \"##{pane_current_path}\" \"$codex_bin\"")
fi

if pi_bin="$(command -v pi)"; then
    items+=("Pi (resume)"   p "new-window -t #{session_id} -n pi -c \"##{pane_current_path}\" \"$pi_bin --resume\"")
    items+=("Pi (continue)" P "new-window -t #{session_id} -n pi -c \"##{pane_current_path}\" \"$pi_bin --continue\"")
    items+=("Pi (new)"      4 "new-window -t #{session_id} -n pi -c \"##{pane_current_path}\" \"$pi_bin\"")
fi

if [ "${#items[@]}" -eq 0 ]; then
    tmux display-message "ai-tools-menu: no AI coding tool installed (claude/opencode/codex/pi)"
    exit 0
fi

tmux display-menu -OM -c "$client" -t "$pane" -T "AI Tools" -x C -y C "${items[@]}"
