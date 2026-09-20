#!/usr/bin/env bats
# =============================================================================
# Tests for the tmux-dev/tmux-project functions from tmux.bash.
# Aliases are deliberately not tested: they do not expand in non-interactive
# shells ("shopt -s expand_aliases" would be required) and contain no logic of
# their own, only fixed tmux command lines.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    STUB_LOG="$BATS_TEST_TMPDIR/tmux.log"
    mkdir -p "$STUB_BIN"
    # PATH is truncated (not merely prepended to): tmux-dev now checks via
    # `command -v` which AI tools are installed, and the real
    # claude/opencode/codex/pi binaries on this machine must not
    # skew that result. bash itself must stay reachable via /usr/bin:/bin.
    export PATH="$STUB_BIN:/usr/bin:/bin"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    : >"$STUB_LOG"
    # shellcheck source=/dev/null
    source "$BATS_TEST_DIRNAME/../tmux.bash"
}

# Creates a no-op stub command in STUB_BIN so that `command -v <name>`
# succeeds for that tool.
stub_tool() {
    local name="$1"
    printf '#!/bin/bash\nexit 0\n' >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

# tmux stub: logs every invocation; has-session returns the passed-in
# exit code (0 = the session already exists, 1 = it does not).
make_tmux_stub() {
    local has_session_exit="$1"
    cat >"$STUB_BIN/tmux" <<EOF
#!/bin/bash
echo "\$@" >>"$STUB_LOG"
if [ "\$1" = "has-session" ]; then
    exit $has_session_exit
fi
exit 0
EOF
    chmod +x "$STUB_BIN/tmux"
}

@test "tmux-dev: existing session is only attached, none is created" {
    make_tmux_stub 0
    run tmux-dev "sess" "/some/project"
    [ "$status" -eq 0 ]
    grep -qx "attach -t sess" "$STUB_LOG"
    run ! grep -q "^new-session" "$STUB_LOG"
}

@test "tmux-dev: a new session with shell/claude/opencode windows is created" {
    make_tmux_stub 1
    stub_tool claude
    stub_tool opencode
    run tmux-dev "sess" "/some/project"
    [ "$status" -eq 0 ]
    grep -qx "new-session -d -s sess -n shell -c /some/project" "$STUB_LOG"
    grep -qx "new-window -t sess -n claude -c /some/project" "$STUB_LOG"
    grep -qx "new-window -t sess -n opencode -c /some/project" "$STUB_LOG"
    grep -qx "select-window -t sess:1" "$STUB_LOG"
    grep -qx "attach -t sess" "$STUB_LOG"
}

@test "tmux-dev: codex/pi windows are created when installed" {
    make_tmux_stub 1
    stub_tool codex
    stub_tool pi
    run tmux-dev "sess" "/some/project"
    [ "$status" -eq 0 ]
    grep -qx "new-window -t sess -n codex -c /some/project" "$STUB_LOG"
    grep -qx "new-window -t sess -n pi -c /some/project" "$STUB_LOG"
    run ! grep -q "\-n claude " "$STUB_LOG"
    run ! grep -q "\-n opencode " "$STUB_LOG"
}

@test "tmux-dev: no AI tool installed -> shell window only" {
    make_tmux_stub 1
    run tmux-dev "sess" "/some/project"
    [ "$status" -eq 0 ]
    grep -qx "new-session -d -s sess -n shell -c /some/project" "$STUB_LOG"
    run ! grep -q "^new-window" "$STUB_LOG"
    grep -qx "select-window -t sess:1" "$STUB_LOG"
}

@test "tmux-dev: default session name is the basename of PWD" {
    make_tmux_stub 1
    local workdir="$BATS_TEST_TMPDIR/my-project"
    mkdir -p "$workdir"
    (cd "$workdir" && tmux-dev)
    grep -qx "new-session -d -s my-project -n shell -c $workdir" "$STUB_LOG"
}

@test "tmux-project: missing directory yields an error without calling tmux-dev" {
    make_tmux_stub 1
    run tmux-project "does-not-exist"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
    [ ! -s "$STUB_LOG" ]
}

@test "tmux-project: existing directory delegates to tmux-dev with the correct path" {
    make_tmux_stub 1
    mkdir -p "$HOME/projects/myproj"
    run tmux-project "myproj"
    [ "$status" -eq 0 ]
    grep -qx "new-session -d -s myproj -n shell -c $HOME/projects/myproj" "$STUB_LOG"
}

@test "tmux-project: missing argument yields a Usage error" {
    run tmux-project
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage"* ]]
}
