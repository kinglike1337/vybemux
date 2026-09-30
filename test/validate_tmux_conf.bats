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

@test "the user's own ~/.tmux.conf is not loaded before the validated file" {
    local fixture_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$fixture_home"
    printf 'set -g @ambient-loaded yes\n' >"$fixture_home/.tmux.conf"
    printf '%s\n' "if-shell -F '#{@ambient-loaded}' 'this-is-not-a-real-tmux-command'" \
        >"$BATS_TEST_TMPDIR/probe.conf"

    run env HOME="$fixture_home" bash "$SCRIPT" "$BATS_TEST_TMPDIR/probe.conf"

    [ "$status" -eq 0 ]
    [[ "$output" == *"tmux.conf is syntactically valid"* ]]
}

@test "a broken ~/.tmux.conf neither hides nor causes errors in the validated file" {
    local fixture_home="$BATS_TEST_TMPDIR/home-broken"
    mkdir -p "$fixture_home"
    printf 'this-is-not-a-real-tmux-command\n' >"$fixture_home/.tmux.conf"
    printf 'set -g mouse on\n' >"$BATS_TEST_TMPDIR/valid.conf"
    printf 'set -g mouse on\nthis-is-also-not-a-command\n' >"$BATS_TEST_TMPDIR/broken.conf"

    run env HOME="$fixture_home" bash "$SCRIPT" "$BATS_TEST_TMPDIR/valid.conf"
    [ "$status" -eq 0 ]

    run env HOME="$fixture_home" bash "$SCRIPT" "$BATS_TEST_TMPDIR/broken.conf"
    [ "$status" -eq 1 ]
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

@test "the clipboard reaches the terminal through tmux's own OSC 52, not through a copy command" {
    grep -qx 'set -g set-clipboard on' "$PROJECT_CONFIG"

    run grep '^set -goq @override_copy_command' "$PROJECT_CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" != *'52;'* ]]
    [[ "$output" != *'base64'* ]]
    [ "$output" = "set -goq @override_copy_command 'cat >/dev/null'" ]
    run grep '@custom_copy_command' "$PROJECT_CONFIG"
    [ "$status" -ne 0 ]
}

@test "a broken ~/.tmux.conf.local does not make a valid config invalid" {
    local fixture_home="$BATS_TEST_TMPDIR/home-local"
    mkdir -p "$fixture_home"
    printf 'this-is-not-a-real-tmux-command\n' >"$fixture_home/.tmux.conf.local"
    printf 'source-file -q ~/.tmux.conf.local\nset -g mouse on\n' >"$BATS_TEST_TMPDIR/sources-local.conf"

    run env HOME="$fixture_home" bash "$SCRIPT" "$BATS_TEST_TMPDIR/sources-local.conf"

    [ "$status" -eq 0 ]
    [[ "$output" == *"tmux.conf is syntactically valid"* ]]
}

@test "the plugins of an existing installation are not started during validation" {
    local fixture_home="$BATS_TEST_TMPDIR/home-tpm"
    mkdir -p "$fixture_home/.tmux/plugins/tpm"
    printf '#!/bin/bash\ntouch "%s/tpm-ran"\n' "$BATS_TEST_TMPDIR" >"$fixture_home/.tmux/plugins/tpm/tpm"
    chmod +x "$fixture_home/.tmux/plugins/tpm/tpm"

    run env HOME="$fixture_home" bash "$SCRIPT" "$PROJECT_CONFIG"

    [ "$status" -eq 0 ]
    # TPM is started asynchronously by the config's run-shell; give a job that
    # did start time to touch its marker before asserting it never ran.
    sleep 1
    [ ! -e "$BATS_TEST_TMPDIR/tpm-ran" ]
}

@test "--label names the file in the messages" {
    printf 'set -g mouse on\n' >"$BATS_TEST_TMPDIR/ok.conf"
    printf 'this-is-not-a-real-tmux-command\n' >"$BATS_TEST_TMPDIR/bad.conf"

    run bash "$SCRIPT" --label "your override" "$BATS_TEST_TMPDIR/ok.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"your override is syntactically valid"* ]]

    run bash "$SCRIPT" --label "your override" "$BATS_TEST_TMPDIR/bad.conf"
    [ "$status" -eq 1 ]
    [[ "$output" == *"your override contains syntax errors"* ]]
}

@test "a relative config path is resolved against the caller's directory" {
    printf 'set -g mouse on\n' >"$BATS_TEST_TMPDIR/rel.conf"

    run bash -c "cd '$BATS_TEST_TMPDIR' && bash '$SCRIPT' rel.conf"

    [ "$status" -eq 0 ]
    [[ "$output" == *"syntactically valid"* ]]
}

@test "--keep-home lets a user override resolve its ~-relative includes against the real HOME" {
    local fixture_home="$BATS_TEST_TMPDIR/home-keep"
    mkdir -p "$fixture_home"
    printf 'set -g mouse on\n' >"$fixture_home/extra.conf"
    printf 'source-file ~/extra.conf\nif-shell "test -f ~/extra.conf" "set -g @found yes"\n' >"$fixture_home/.tmux.conf.local"

    run env HOME="$fixture_home" bash "$SCRIPT" --keep-home --label "your override" "$fixture_home/.tmux.conf.local"

    [ "$status" -eq 0 ]
    [[ "$output" == *"your override is syntactically valid"* ]]
}

@test "without --keep-home the same ~-relative include is not found (isolation unchanged)" {
    local fixture_home="$BATS_TEST_TMPDIR/home-isolated"
    mkdir -p "$fixture_home"
    printf 'set -g mouse on\n' >"$fixture_home/extra.conf"
    printf 'source-file ~/extra.conf\n' >"$fixture_home/.tmux.conf.local"

    run env HOME="$fixture_home" bash "$SCRIPT" "$fixture_home/.tmux.conf.local"

    [ "$status" -eq 1 ]
}

@test "--keep-home still reports a genuinely broken override" {
    local fixture_home="$BATS_TEST_TMPDIR/home-broken-keep"
    mkdir -p "$fixture_home"
    printf 'this-is-not-a-real-tmux-command\n' >"$fixture_home/.tmux.conf.local"

    run env HOME="$fixture_home" bash "$SCRIPT" --keep-home --label "your override" "$fixture_home/.tmux.conf.local"

    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown command"* ]]
    [[ "$output" == *"your override contains syntax errors"* ]]
}

@test "an unknown option is rejected" {
    run bash "$SCRIPT" --bogus "$PROJECT_CONFIG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: --bogus"* ]]
}
