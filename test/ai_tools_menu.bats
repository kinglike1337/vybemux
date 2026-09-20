#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/ai-tools-menu.sh
# =============================================================================

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/ai-tools-menu.sh"

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    STUB_LOG="$BATS_TEST_TMPDIR/tmux.log"
    mkdir -p "$STUB_BIN"
    # Point HOME at an empty fake directory AND truncate PATH to stub + system
    # (not merely prepend to it): the script prepends $HOME/.local/bin etc.,
    # but this machine's real claude/opencode/codex/pi binaries may also live
    # directly in the inherited PATH (not only via .local/bin) and must not
    # skew the presence detection.
    export HOME="$BATS_TEST_TMPDIR/fakehome"
    export PATH="$STUB_BIN:/usr/bin:/bin"
    : >"$STUB_LOG"
}

# tmux stub: logs each argument on its own line (so that individual menu keys
# like "c" can be matched exactly, without overlapping item text) and answers
# the 'display -p' queries the script needs for client/pane/session targeting.
make_tmux_stub() {
    cat >"$STUB_BIN/tmux" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >>"$STUB_LOG"
case "\$1" in
    display)
        case "\$3" in
            '#{pane_current_path}') echo "/home/testuser/project" ;;
            '#{client_name}') echo "test-client" ;;
            '#{pane_id}') echo "%1" ;;
            '#{session_name}') echo "test-session" ;;
        esac
        ;;
esac
EOF
    chmod +x "$STUB_BIN/tmux"
}

# Creates a no-op stub command in STUB_BIN so that `command -v <name>`
# succeeds for that tool.
stub_tool() {
    local name="$1"
    printf '#!/bin/bash\nexit 0\n' >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

@test "no tool installed -> notice instead of display-menu" {
    make_tmux_stub
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx "display-message" "$STUB_LOG"
    grep -qx "ai-tools-menu: no AI coding tool installed (claude/opencode/codex/pi)" "$STUB_LOG"
    run ! grep -qx "display-menu" "$STUB_LOG"
}

@test "display-menu is invoked with -O and -M (mouse click on an item works)" {
    # tmux man page: "-M tells tmux the menu should handle mouse events; by
    # default only menus opened from mouse key bindings do so." This submenu
    # is opened via run-shell (no mouse key binding), so without -M mouse
    # clicks on items would be silently ignored.
    make_tmux_stub
    stub_tool claude
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx -- "-OM" "$STUB_LOG"
}

@test "display-menu gets client and pane as explicit targets (-c/-t)" {
    # tmux man page: "target-pane gives the target for any commands run from
    # the menu." This submenu runs from a run-shell subprocess with no bound
    # client — without -c/-t the menu still renders, but a selected item has
    # no target and does nothing.
    make_tmux_stub
    stub_tool claude
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx -- "-c" "$STUB_LOG"
    grep -qx "test-client" "$STUB_LOG"
    grep -qx -- "%1" "$STUB_LOG"
}

@test "new-window commands target the calling session explicitly (-t)" {
    make_tmux_stub
    stub_tool claude
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q -- '-t "test-session"' "$STUB_LOG"
}

@test "only codex installed -> menu contains exclusively Codex entries" {
    make_tmux_stub
    stub_tool codex
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx "display-menu" "$STUB_LOG"
    grep -q "Codex (resume)" "$STUB_LOG"
    grep -q "Codex (continue)" "$STUB_LOG"
    grep -q "Codex (new)" "$STUB_LOG"
    run ! grep -q "Claude" "$STUB_LOG"
    run ! grep -q "OpenCode" "$STUB_LOG"
    run ! grep -q "Pi (" "$STUB_LOG"
}

@test "only pi installed -> menu contains exclusively Pi entries" {
    make_tmux_stub
    stub_tool pi
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "Pi (resume)" "$STUB_LOG"
    grep -q "Pi (continue)" "$STUB_LOG"
    grep -q "Pi (new)" "$STUB_LOG"
    run ! grep -q "Claude" "$STUB_LOG"
    run ! grep -q "Codex" "$STUB_LOG"
    run ! grep -q "OpenCode" "$STUB_LOG"
}

@test "all four tools installed -> menu contains all of them, no duplicate shortcuts" {
    make_tmux_stub
    stub_tool claude
    stub_tool opencode
    stub_tool codex
    stub_tool pi
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    for label in "Claude (resume)" "Claude (continue)" "Claude (new)" \
        "OpenCode (continue)" "OpenCode (new)" \
        "Codex (resume)" "Codex (continue)" "Codex (new)" \
        "Pi (resume)" "Pi (continue)" "Pi (new)"; do
        grep -q -- "$label" "$STUB_LOG"
    done
    # The first 11 lines after "display-menu" are the fixed flags/values
    # (-OM -c test-client -t %1 -T "AI Tools" -x C -y C) — "C" there is a
    # position value, not an item shortcut, and must not be counted by the
    # duplicate check.
    local items_log
    items_log="$(awk '/^display-menu$/{f=1; skip=11; next} f && skip>0 {skip--; next} f' "$STUB_LOG")"
    for key in c C 1 o 2 x X 3 p P 4; do
        count="$(grep -cx -- "$key" <<<"$items_log")"
        [ "$count" -le 1 ]
    done
}

@test "OpenCode in the installer directory (~/.opencode/bin) is detected" {
    make_tmux_stub
    mkdir -p "$HOME/.opencode/bin"
    printf '#!/bin/bash\nexit 0\n' >"$HOME/.opencode/bin/opencode"
    chmod +x "$HOME/.opencode/bin/opencode"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "OpenCode (continue)" "$STUB_LOG"
}

@test "Pi in the versioned pi-node directory is detected without knowing the version" {
    make_tmux_stub
    mkdir -p "$HOME/.local/share/pi-node/node-v99.9.9-linux-x64/bin"
    printf '#!/bin/bash\nexit 0\n' >"$HOME/.local/share/pi-node/node-v99.9.9-linux-x64/bin/pi"
    chmod +x "$HOME/.local/share/pi-node/node-v99.9.9-linux-x64/bin/pi"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "Pi (resume)" "$STUB_LOG"
}

@test "item commands use the absolute path, not the bare tool name" {
    # The selected menu entry is later executed by the tmux server, not by
    # this script — the PATH augmentation above only applies to the
    # `command -v` detection. A bare name like "codex" would not be found in
    # the server's restricted PATH (the pane starts, the process fails
    # immediately, and the window disappears again).
    make_tmux_stub
    stub_tool codex
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q -- "\"$STUB_BIN/codex resume\"" "$STUB_LOG"
}

@test "new-window commands use the pane's working directory" {
    make_tmux_stub
    stub_tool claude
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q -- '-c "/home/testuser/project"' "$STUB_LOG"
}
