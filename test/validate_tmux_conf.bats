#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/validate-tmux-conf.sh — deliberately uses a real
# isolated tmux server (no PATH stub like the other tests): the script
# checks that "source-file" reports a real syntax error from tmux, and
# that is exactly what a mock must not take over. Requires tmux to be
# installed (installed in the unit-tests CI job, see .gitea/workflows/ci.yml);
# locally without tmux the tests are skipped instead of failing.
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-tmux-conf.sh"
PROJECT_CONFIG="$BATS_TEST_DIRNAME/../tmux.conf"
TMUX_TEST_SOCKET=""

setup() {
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux is not installed"
    fi
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]]; then
        tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
}

@test "a valid config is reported as syntactically valid" {
    printf 'set -g mouse on\n' >"$BATS_TEST_TMPDIR/valid.conf"
    run bash "$SCRIPT" "$BATS_TEST_TMPDIR/valid.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tmux.conf is syntactically valid"* ]]
}

@test "a config with an unknown command is reported as an error" {
    printf 'set -g mouse on\nthis-is-not-a-real-tmux-command\n' >"$BATS_TEST_TMPDIR/broken.conf"
    run bash "$SCRIPT" "$BATS_TEST_TMPDIR/broken.conf"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tmux.conf contains syntax errors"* ]]
    [[ "$output" == *"unknown command"* ]]
}

@test "a missing config file yields an error" {
    run bash "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist.conf"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Config file not found"* ]]
}

@test "without an argument the project's own tmux.conf is validated (default path)" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tmux.conf is syntactically valid"* ]]
}

@test "the project config preserves the user save hook across quiet reloads" {
    local fixture_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$fixture_home"
    TMUX_TEST_SOCKET="vybemux-hook-reload-$BATS_TEST_NUMBER-$$"
    env HOME="$fixture_home" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null \
        new-session -d -s check
    tmux -L "$TMUX_TEST_SOCKET" set-option -g \
        @resurrect-hook-post-save-all 'printf legacy-hook'

    run env HOME="$fixture_home" tmux -L "$TMUX_TEST_SOCKET" \
        source-file "$PROJECT_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" != *"already set"* ]]

    run env HOME="$fixture_home" tmux -L "$TMUX_TEST_SOCKET" \
        source-file "$PROJECT_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" != *"already set"* ]]

    run tmux -L "$TMUX_TEST_SOCKET" show-option -gqv \
        @vybemux-resurrect-hook-post-save-all
    [ "$status" -eq 0 ]
    [ "$output" = "printf legacy-hook" ]
}
