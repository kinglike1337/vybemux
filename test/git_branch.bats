#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/git-branch.sh
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/git-branch.sh"

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
}

# tmux stub: answers "display-message -p -t <id> '#{pane_current_path}'"
# with the given path, simulating the id -> cwd lookup git-branch.sh
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

@test "prints the current branch of a git repository" {
    local repo="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" -c user.email=test@example.com -c user.name=test \
        commit -q --allow-empty -m init

    make_tmux_stub "$repo"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "prints a dash outside a git repository" {
    local dir="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$dir"

    make_tmux_stub "$dir"
    run bash "$SCRIPT" '%1'
    [ "$status" -eq 0 ]
    [ "$output" = "-" ]
}

@test "prints a dash when the pane id cannot be resolved (no argument)" {
    make_tmux_stub ""
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "-" ]
}
