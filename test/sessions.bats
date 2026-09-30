#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/sessions.sh
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/sessions.sh"
BADGE='#[fg=#1a1b26,bg=#7aa2f7,bold]'
MUTED='#[fg=#565f89,bg=#1a1b26]'

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"
}

# tmux stub: answers "list-sessions" with the lines passed in (one session
# per line; an empty fixture -> empty output, as if no server were running)
# and "display-message -p -t <id> '#{session_name}'" with the given current
# session name, simulating the id -> name lookup sessions.sh performs.
make_tmux_stub() {
    local output="$1"
    local cur_name="${2:-}"
    {
        echo '#!/bin/bash'
        echo 'if [ "$1" = "list-sessions" ]; then'
        printf '  printf %%s\\\\n %s\n' "$(printf '%q' "$output")"
        echo 'elif [ "$1" = "display-message" ]; then'
        printf '  printf %%s %s\n' "$(printf '%q' "$cur_name")"
        echo 'fi'
    } >"$STUB_BIN/tmux"
    chmod +x "$STUB_BIN/tmux"
}

make_tmux_stub_failing() {
    {
        echo '#!/bin/bash'
        echo 'exit 1'
    } >"$STUB_BIN/tmux"
    chmod +x "$STUB_BIN/tmux"
}

@test "current session gets the badge, others are muted" {
    make_tmux_stub $'work\npersonal' "work"
    run bash "$SCRIPT" '$3'
    [ "$status" -eq 0 ]
    local expected
    expected="$(printf '%s %s ' "$BADGE" "work")$(printf '%s %s ' "$MUTED" "personal")"
    [ "$output" = "$expected" ]
}

@test "without a current session (empty argument) all sessions are muted" {
    make_tmux_stub $'work\npersonal'
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local expected
    expected="$(printf '%s %s ' "$MUTED" "work")$(printf '%s %s ' "$MUTED" "personal")"
    [ "$output" = "$expected" ]
}

@test "no running server (list-sessions returns nothing) -> empty output" {
    make_tmux_stub "" "work"
    run bash "$SCRIPT" '$3'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "tmux list-sessions fails -> empty output instead of an error" {
    make_tmux_stub_failing
    run bash "$SCRIPT" '$3'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "# in a session name is escaped as ## so tmux cannot parse it as a style or range" {
    make_tmux_stub $'#[range=user|evil]x\nplain' '#[range=user|evil]x'
    run bash "$SCRIPT" '$3'
    [ "$status" -eq 0 ]
    local expected
    expected="$(printf '%s %s ' "$BADGE" '##[range=user|evil]x')$(printf '%s %s ' "$MUTED" 'plain')"
    [ "$output" = "$expected" ]
}
