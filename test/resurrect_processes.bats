#!/usr/bin/env bats
# =============================================================================
# Tests for the claude entry of @resurrect-processes in tmux.conf.
# Runs the real tmux-resurrect matcher (process_restore_helpers.sh, including
# its eval of the option value) against an isolated tmux server that has the
# project's own option value applied; needs tmux, skipped without it.
# =============================================================================

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
RESURRECT_SCRIPTS="$PROJECT_ROOT/plugins/tmux-resurrect/scripts"
SOCKET=""

setup() {
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux is not installed"
    fi
    if [ ! -f "$RESURRECT_SCRIPTS/process_restore_helpers.sh" ]; then
        skip "tmux-resurrect submodule is not checked out"
    fi
    SOCKET="vybemux-procs-$$-$BATS_TEST_NUMBER"
    tmux -L "$SOCKET" -f /dev/null new-session -d -s t
    grep '^set -g @resurrect-processes' "$PROJECT_ROOT/tmux.conf" >"$BATS_TEST_TMPDIR/processes.conf"
    tmux -L "$SOCKET" source-file "$BATS_TEST_TMPDIR/processes.conf"
}

teardown() {
    if [[ -n "$SOCKET" ]]; then
        tmux -L "$SOCKET" kill-server 2>/dev/null || true
    fi
}

restored() {
    local server_env
    server_env="$(tmux -L "$SOCKET" display -p '#{socket_path},#{pid},0')"
    TMUX="$server_env" CURRENT_DIR="$RESURRECT_SCRIPTS" bash -c '
        source "$CURRENT_DIR/variables.sh"
        source "$CURRENT_DIR/helpers.sh"
        source "$CURRENT_DIR/process_restore_helpers.sh"
        _process_on_the_restore_list "$1"
    ' _ "$1"
}

not_restored() {
    run restored "$1"
    [ "$status" -ne 0 ]
}

@test "the option value from tmux.conf is applied to the isolated server" {
    run tmux -L "$SOCKET" show-option -gqv @resurrect-processes
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude"* ]]
}

@test "the fallback line written by the hook is restored" {
    restored 'claude --resume'
}

@test "a hook line with session id is restored" {
    restored 'claude --resume 0a1b2c3d-0000-4000-8000-000000000000'
}

@test "a hook line with the unset prefix and env assignments is restored" {
    restored 'unset "${!ANTHROPIC_@}" CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK; ANTHROPIC_MODEL=m1 claude --resume abc-123'
}

@test "a hook line that sources the private env file is restored" {
    restored 'unset "${!ANTHROPIC_@}" CLAUDE_CONFIG_DIR; ( . /home/u/.tmux/resurrect/claude-env/abc.env; ANTHROPIC_MODEL=m1 claude --resume abc )'
}

@test "a raw claude command that the hook did not rewrite is restored" {
    restored 'claude --dangerously-skip-permissions'
    restored 'claude'
}

@test "unrelated commands that merely contain claude are not restored" {
    not_restored 'cat claude.log'
    not_restored 'cd ~/.claude && ls'
    not_restored 'claude-code-proxy --port 8080'
    not_restored 'grep claude README.md'
    not_restored 'node server.js --name claude'
}

@test "the baseline: the default process list still restores its own commands" {
    restored 'tail -f claude.log'
}
