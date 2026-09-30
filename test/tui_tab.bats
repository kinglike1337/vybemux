#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/tui-tab.sh
# =============================================================================

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/tui-tab.sh"

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    STUB_LOG="$BATS_TEST_TMPDIR/tmux.log"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
    : >"$STUB_LOG"
}

# tmux stub: logs every invocation to $STUB_LOG and answers
# show-options/display/list-windows with the fixture values passed in.
# git_tui/file_tui empty -> the script falls back to lazygit/yazi.
# existing_windows empty -> no window with the role name exists.
make_tmux_stub() {
    local git_tui="$1" file_tui="$2" existing_windows="$3"
    cat >"$STUB_BIN/tmux" <<EOF
#!/bin/bash
echo "\$@" >>"$STUB_LOG"
case "\$1" in
    show-options)
        case "\$3" in
            '@git_tui') printf '%s\n' "$git_tui" ;;
            '@file_tui') printf '%s\n' "$file_tui" ;;
        esac
        ;;
    display)
        case "\$3" in
            '#{session_name}') echo "mysession" ;;
            '#{pane_current_path}') echo "/home/testuser/project" ;;
        esac
        ;;
    list-windows)
        if [ -n "$existing_windows" ]; then
            printf '%s\n' "$existing_windows"
        fi
        ;;
esac
EOF
    chmod +x "$STUB_BIN/tmux"
}

@test "unknown role yields an error and exit 1" {
    make_tmux_stub "true" "true" ""
    run bash "$SCRIPT" "invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown role 'invalid'"* ]]
}

@test "missing argument yields a Usage error" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "no override for git falls back to lazygit as the default" {
    make_tmux_stub "" "" ""
    run bash "$SCRIPT" "git"
    [ "$status" -eq 0 ]
    grep -q "lazygit" "$STUB_LOG"
}

@test "no override for files falls back to yazi as the default" {
    make_tmux_stub "" "" ""
    run bash "$SCRIPT" "files"
    [ "$status" -eq 0 ]
    grep -q "yazi" "$STUB_LOG"
}

@test "command from override not installed -> notice instead of a new window" {
    make_tmux_stub "definitely-not-a-real-binary-xyz" "" ""
    run bash "$SCRIPT" "git"
    [ "$status" -eq 0 ]
    grep -q "display-message" "$STUB_LOG"
    grep -Fq "tui-tab: 'definitely-not-a-real-binary-xyz' is not installed (set @git_tui)" "$STUB_LOG"
    run ! grep -q "^new-window" "$STUB_LOG"
}

@test "existing window is focused instead of being created" {
    make_tmux_stub "true" "" "git"
    run bash "$SCRIPT" "git"
    [ "$status" -eq 0 ]
    grep -qx "select-window -t mysession:git" "$STUB_LOG"
    run ! grep -q "^new-window" "$STUB_LOG"
}

@test "no existing window -> a new window is created, automatic-rename off" {
    make_tmux_stub "true" "" ""
    run bash "$SCRIPT" "git"
    [ "$status" -eq 0 ]
    grep -qx "new-window -t mysession -n git -c /home/testuser/project true" "$STUB_LOG"
    grep -qx "set-window-option -t mysession:git automatic-rename off" "$STUB_LOG"
}

@test "files role reads @file_tui instead of @git_tui" {
    make_tmux_stub "" "true" ""
    run bash "$SCRIPT" "files"
    [ "$status" -eq 0 ]
    grep -qx "new-window -t mysession -n files -c /home/testuser/project true" "$STUB_LOG"
}

@test "a tool only reachable through the extended PATH is launched by absolute path" {
    local fixture_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$fixture_home/.local/bin"
    printf '#!/bin/bash\n' >"$fixture_home/.local/bin/mytui"
    chmod +x "$fixture_home/.local/bin/mytui"
    make_tmux_stub "mytui" "" ""

    run env HOME="$fixture_home" bash "$SCRIPT" "git"

    [ "$status" -eq 0 ]
    grep -qx "new-window -t mysession -n git -c /home/testuser/project $fixture_home/.local/bin/mytui" "$STUB_LOG"
}

@test "arguments of an override are preserved after the resolved program" {
    local fixture_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$fixture_home/.local/bin"
    printf '#!/bin/bash\n' >"$fixture_home/.local/bin/mytui"
    chmod +x "$fixture_home/.local/bin/mytui"
    make_tmux_stub "mytui --flag value" "" ""

    run env HOME="$fixture_home" bash "$SCRIPT" "git"

    [ "$status" -eq 0 ]
    grep -qx "new-window -t mysession -n git -c /home/testuser/project $fixture_home/.local/bin/mytui --flag value" "$STUB_LOG"
}

@test "a resolved path with spaces is shell-quoted for the new window" {
    local fixture_home="$BATS_TEST_TMPDIR/my home"
    mkdir -p "$fixture_home/.local/bin"
    printf '#!/bin/bash\n' >"$fixture_home/.local/bin/mytui"
    chmod +x "$fixture_home/.local/bin/mytui"
    make_tmux_stub "mytui" "" ""

    run env HOME="$fixture_home" bash "$SCRIPT" "git"

    [ "$status" -eq 0 ]
    grep -Fqx "new-window -t mysession -n git -c /home/testuser/project $(printf '%q' "$fixture_home/.local/bin/mytui")" "$STUB_LOG"
}

@test "an override with arguments whose program is missing still shows the notice" {
    make_tmux_stub "definitely-not-a-real-binary-xyz --flag" "" ""
    run bash "$SCRIPT" "git"
    [ "$status" -eq 0 ]
    grep -Fq "tui-tab: 'definitely-not-a-real-binary-xyz' is not installed (set @git_tui)" "$STUB_LOG"
    run ! grep -q "^new-window" "$STUB_LOG"
}
