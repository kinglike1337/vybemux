#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/shorten-path.sh
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/shorten-path.sh"

setup() {
    export HOME="/home/testuser"
}

@test "shortens a path under HOME to ~ plus single-character components" {
    run bash "$SCRIPT" "/home/testuser/long/path/to/project"
    [ "$status" -eq 0 ]
    [ "$output" = "~/l/p/t/project" ]
}

@test "shortens a path outside HOME component-wise as well" {
    run bash "$SCRIPT" "/var/log/some/deep/path"
    [ "$status" -eq 0 ]
    [ "$output" = "/v/l/s/d/path" ]
}

@test "HOME itself becomes ~ without further shortening" {
    run bash "$SCRIPT" "/home/testuser"
    [ "$status" -eq 0 ]
    [ "$output" = "~" ]
}

@test "a single-component path under HOME stays unchanged (only the final component)" {
    run bash "$SCRIPT" "/home/testuser/project"
    [ "$status" -eq 0 ]
    [ "$output" = "~/project" ]
}
