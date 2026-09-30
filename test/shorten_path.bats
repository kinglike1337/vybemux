#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/shorten-path.sh
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/shorten-path.sh"

setup() {
    export HOME="/home/testuser"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
}

# tmux stub: answers "display-message -p -t <id> '#{pane_current_path}'"
# with the given path, simulating the id -> cwd lookup shorten-path.sh
# performs instead of taking the path directly as an argument.
make_tmux_stub() {
    local path="$1"
    {
        echo '#!/bin/bash'
        echo 'if [ "$1" = "display-message" ]; then'
        printf '  printf %%s %s\n' "$(printf '%q' "$path")"
        echo 'fi'
    } >"$STUB_BIN/tmux"
    chmod +x "$STUB_BIN/tmux"
}

@test "shortens a path under HOME to ~ plus single-character components" {
    make_tmux_stub "/home/testuser/long/path/to/project"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "~/l/p/t/project" ]
}

@test "shortens a path outside HOME component-wise as well" {
    make_tmux_stub "/var/log/some/deep/path"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "/v/l/s/d/path" ]
}

@test "HOME itself becomes ~ without further shortening" {
    make_tmux_stub "/home/testuser"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "~" ]
}

@test "a single-component path under HOME stays unchanged (only the final component)" {
    make_tmux_stub "/home/testuser/project"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "~/project" ]
}

@test "# in a directory name is escaped as ## so tmux cannot parse it as a style" {
    make_tmux_stub "$HOME/a/#[bg=red]x"
    run bash "$SCRIPT" "%1"
    [ "$status" -eq 0 ]
    [ "$output" = '~/a/##[bg=red]x' ]
}

@test "a HOME containing regex metacharacters is matched literally" {
    export HOME="/home/te.st[1]"
    make_tmux_stub "/home/te.st[1]/long/project"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "~/l/project" ]
}

@test "a path that only looks like HOME through a regex wildcard is not shortened to ~" {
    export HOME="/home/te.st"
    make_tmux_stub "/home/teXst/project"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "/h/t/project" ]
}

@test "a sibling directory that merely starts with HOME is not treated as inside HOME" {
    make_tmux_stub "/home/testuser2/project"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "/h/t/project" ]
}
