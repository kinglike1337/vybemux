#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/resurrect-claude-hook.sh.
#
# Black-box only: the script exits when the file is missing (line 38) and the
# actual processing runs in the top-level loop at the end of the file -- so
# source-based unit testing of individual functions is not possible. Each test
# invokes the script with a prepared resurrect save file and checks the
# rewritten file.
#
# The pane line format (tab-separated, 11 fields) is derived from
# plugins/tmux-resurrect/scripts/save.sh (pane_format/dump_panes), not from
# the hook's own cut indices -- otherwise a wrong index in the hook would be
# confirmed by the test instead of exposed:
#   pane  session_name  window_number  window_active  :window_flags
#   pane_index  pane_title  :dir  pane_active  pane_command  :full_command
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/resurrect-claude-hook.sh"
BASH_BIN="$(command -v bash)"

# Duplicated (not sourced) from CLAUDE_ENV_CLEAR_PREFIX in the script under
# test -- this file is black-box only (see file header), so this literal is
# the expected-output side of the contract, kept in sync by hand.
CLEAR_PREFIX='unset "${!ANTHROPIC_@}" CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK; '

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"
    # Sandboxes $HOME so the hook's "$HOME/.claude*/sessions" candidate-dir
    # scan (for alternate CLAUDE_CONFIG_DIR profiles) never touches this
    # machine's real ~/.claude* directories.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
    mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
    export PATH="$STUB_BIN:$PATH"
    # Empty default stub so that "tmux" is always resolvable (see the
    # comment on PANES_SNAPSHOT further down) -- tests that need matching
    # pane data override it via make_tmux_stub.
    make_tmux_stub ""
}

teardown() {
    if [ -f "$BATS_TEST_TMPDIR/claude.pids" ]; then
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null || true
        done <"$BATS_TEST_TMPDIR/claude.pids"
    fi
}

# Names of every currently-exported var that the hook's env-capture allowlist
# could match (ANTHROPIC_*, CLAUDE_CONFIG_DIR, the named CLAUDE_CODE_* config
# flags) -- stripped from spawned fixture processes below so tests are
# hermetic regardless of *this test suite's own* process environment (bats
# itself may be running inside a real Claude Code session, which exports
# CLAUDE_CODE_SESSION_ID and friends).
claude_env_allowlist_names() {
    compgen -v | grep -E '^(ANTHROPIC_[A-Z0-9_]*|CLAUDE_CONFIG_DIR|CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC|CLAUDE_CODE_AUTO_COMPACT_WINDOW|CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK)$' || true
}

claude_env_unset_args() {
    local v
    while IFS= read -r v; do
        [ -n "$v" ] && printf -- '-u\n%s\n' "$v"
    done < <(claude_env_allowlist_names)
}

# Starts a real background process: its PID and the real /proc/<pid>/stat
# provide the procStart basis for the hook's verification logic -- no mock of
# /proc, that is the core of the correctness under test (staleness protection
# against PID reuse). Runs with every allowlist-matching var unset, so this
# stays a "clean" fixture unaffected by the env-var capture feature -- tests
# for that feature use spawn_fake_claude_pid_with_env instead.
spawn_fake_claude_pid() {
    local unset_args=()
    mapfile -t unset_args < <(claude_env_unset_args)
    env "${unset_args[@]}" sleep 100 </dev/null >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >>"$BATS_TEST_TMPDIR/claude.pids"
    echo "$pid"
}

# Like spawn_fake_claude_pid, but on top of the same clean slate, the
# background process also carries the given extra vars (readable via the
# real /proc/<pid>/environ) -- for exercising the hook's env-var capture.
# Extra args are passed straight to "env" as NAME=value pairs.
spawn_fake_claude_pid_with_env() {
    local unset_args=()
    mapfile -t unset_args < <(claude_env_unset_args)
    env "${unset_args[@]}" "$@" sleep 100 </dev/null >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >>"$BATS_TEST_TMPDIR/claude.pids"
    echo "$pid"
}

proc_start_time_of() {
    local pid="$1" stat_line rest
    stat_line="$(cat "/proc/$pid/stat")"
    rest="${stat_line##*) }"
    awk '{print $20}' <<<"$rest"
}

# tmux stub: answers only to "list-panes", with the TSV lines passed in. It
# must always be able to serve PANES_SNAPSHOT="$(tmux list-panes …)" (set -euo
# pipefail, bare assignment) -- with tmux missing entirely, the hook dies with
# exit 127 and leaves the file unchanged.
make_tmux_stub() {
    local output="$1"
    {
        echo '#!/bin/bash'
        echo 'if [ "$1" = "list-panes" ]; then'
        printf '  printf %%s\\\\n %s\n' "$(printf '%q' "$output")"
        echo 'fi'
    } >"$STUB_BIN/tmux"
    chmod +x "$STUB_BIN/tmux"
}

write_session_json() {
    local pid="$1" session_id="$2" tmux_field="$3" cwd="$4" proc_start="$5" updated="${6:-100}"
    jq -n \
        --arg sessionId "$session_id" \
        --arg tmux "$tmux_field" \
        --arg cwd "$cwd" \
        --arg procStart "$proc_start" \
        --argjson updatedAt "$updated" \
        '{sessionId: $sessionId, tmux: $tmux, cwd: $cwd, procStart: $procStart, updatedAt: $updatedAt}' \
        >"$CLAUDE_CONFIG_DIR/sessions/${pid}.json"
}

# Builds a resurrect save file with exactly one "pane" line.
# full_command WITHOUT a leading colon, dir WITH one (as in the real format).
write_resurrect_file() {
    local full_command="$1" dir="$2"
    local IFS=$'\t'
    local fields=(pane sess 0 0 ":0" 0 title "$dir" 1 bash ":$full_command")
    printf '%s\n' "${fields[*]}" >"$BATS_TEST_TMPDIR/resurrect.txt"
}

# Like write_session_json, but without "updatedAt" -- covers the
# (.updatedAt // .startedAt // 0) fallback in build_session_index.
write_session_json_started_at() {
    local pid="$1" session_id="$2" tmux_field="$3" cwd="$4" proc_start="$5" started="$6"
    jq -n \
        --arg sessionId "$session_id" \
        --arg tmux "$tmux_field" \
        --arg cwd "$cwd" \
        --arg procStart "$proc_start" \
        --argjson startedAt "$started" \
        '{sessionId: $sessionId, tmux: $tmux, cwd: $cwd, procStart: $procStart, startedAt: $startedAt}' \
        >"$CLAUDE_CONFIG_DIR/sessions/${pid}.json"
}

run_hook() {
    run "$BASH_BIN" "$SCRIPT" "$BATS_TEST_TMPDIR/resurrect.txt"
}

last_field() {
    local line
    line="$(cat "$BATS_TEST_TMPDIR/resurrect.txt")"
    echo "${line##*$'\t'}"
}

@test "unique match writes claude --resume <sessionId>" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}claude --resume session-abc" ]
}

@test "a resolved pane with none of the allowlisted vars set still gets the clear-prefix" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    # No captured KEY=value at all (spawn_fake_claude_pid strips every
    # allowlisted var), but the pane's own restore-time shell may still have
    # e.g. a global ~/.bashrc default exported -- the clear-prefix must run
    # regardless of whether anything was actually captured.
    [ "$(last_field)" = ":${CLEAR_PREFIX}claude --resume session-abc" ]
}

@test "a non-empty credential goes to a private env file, never into the save file or command line" {
    local pid proc_start env_file
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=fake-key-123 ANTHROPIC_AUTH_TOKEN=fake-token-456 ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    env_file="$BATS_TEST_TMPDIR/claude-env/session-abc.env"
    [ "$(last_field)" = ":${CLEAR_PREFIX}( . $(printf '%q' "$env_file"); ANTHROPIC_MODEL=m1 claude --resume session-abc )" ]
    ! grep -qE 'fake-key-123|fake-token-456' "$BATS_TEST_TMPDIR/resurrect.txt"
    grep -qx 'export ANTHROPIC_API_KEY=fake-key-123' "$env_file"
    grep -qx 'export ANTHROPIC_AUTH_TOKEN=fake-token-456' "$env_file"
    [ "$(stat -c %a "$env_file")" = "600" ]
    [ "$(stat -c %a "$BATS_TEST_TMPDIR/claude-env")" = "700" ]
}

@test "a session id with shell metacharacters falls back to the picker" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" 'abc; touch /tmp/pwned' "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "captures multiple allowlisted vars sorted alphabetically by name" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_BASE_URL=https://example.test CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CONFIG_DIR=/home/testuser/.claude-minimal)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}ANTHROPIC_BASE_URL=https://example.test CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 CLAUDE_CONFIG_DIR=/home/testuser/.claude-minimal claude --resume session-abc" ]
}

@test "non-allowlisted env vars (including CLAUDE_CODE_ internal runtime vars) are not captured" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=fake-key-123 CLAUDE_CODE_SESSION_ID=internal-id CLAUDE_CODE_MESSAGING_TOKEN=internal-secret SOME_OTHER_SECRET=leak-me)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}( . $(printf '%q' "$BATS_TEST_TMPDIR/claude-env/session-abc.env"); claude --resume session-abc )" ]
    grep -qx 'export ANTHROPIC_API_KEY=fake-key-123' "$BATS_TEST_TMPDIR/claude-env/session-abc.env"
    ! grep -qE 'internal-id|internal-secret|leak-me' "$BATS_TEST_TMPDIR/claude-env/session-abc.env"
}

@test "an allowlisted var with an empty value survives as KEY=''" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}ANTHROPIC_API_KEY='' claude --resume session-abc" ]
}

@test "a value with shell-special characters is safely quoted" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid_with_env 'ANTHROPIC_BASE_URL=http://example.test/x y;$z')"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}$(printf 'ANTHROPIC_BASE_URL=%q' 'http://example.test/x y;$z') claude --resume session-abc" ]
}

@test "a non-ASCII resurrect directory yields the same pure-ASCII restore line under C and UTF-8" {
    local utf8_locale pid proc_start res_dir="$BATS_TEST_TMPDIR/jürgen" line_c line_utf8
    utf8_locale="$(locale -a 2>/dev/null | grep -ixE 'C\.utf-?8|en_US\.utf-?8' | head -n 1)" || true
    [ -n "$utf8_locale" ] || skip "no UTF-8 locale installed"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=key-in-file)"
    proc_start="$(proc_start_time_of "$pid")"
    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    mkdir -p "$res_dir"

    write_resurrect_file "claude" ":/home/testuser/project"
    mv "$BATS_TEST_TMPDIR/resurrect.txt" "$res_dir/resurrect.txt"
    LC_ALL=C run "$BASH_BIN" "$SCRIPT" "$res_dir/resurrect.txt"
    [ "$status" -eq 0 ]
    line_c="$(awk -F'\t' '{ print $11 }' "$res_dir/resurrect.txt")"

    write_resurrect_file "claude" ":/home/testuser/project"
    mv "$BATS_TEST_TMPDIR/resurrect.txt" "$res_dir/resurrect.txt"
    LC_ALL="$utf8_locale" run "$BASH_BIN" "$SCRIPT" "$res_dir/resurrect.txt"
    [ "$status" -eq 0 ]
    line_utf8="$(awk -F'\t' '{ print $11 }' "$res_dir/resurrect.txt")"

    [[ "$line_c" == *"claude-env/session-abc.env"* ]]
    [ "$line_c" = "$line_utf8" ]
    ! LC_ALL=C grep -q '[^ -~]' <<<"$line_utf8"
}

@test "an env file referenced by an older save in locale-dependent quoting is kept" {
    local utf8_locale pid proc_start res_dir="$BATS_TEST_TMPDIR/jürgen"
    utf8_locale="$(locale -a 2>/dev/null | grep -ixE 'C\.utf-?8|en_US\.utf-?8' | head -n 1)" || true
    [ -n "$utf8_locale" ] || skip "no UTF-8 locale installed"
    mkdir -p "$res_dir/claude-env"
    printf 'export ANTHROPIC_API_KEY=old\n' >"$res_dir/claude-env/older.env"
    # Written before the hook quoted paths byte-wise: raw UTF-8 path.
    printf 'pane\ts\t0\t:w\t1\t0\t:t\t:/x\t0\tclaude\t:( . %s; claude --resume older )\n' \
        "$res_dir/claude-env/older.env" >"$res_dir/tmux_resurrect_20260101T000000.txt"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"
    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"
    mv "$BATS_TEST_TMPDIR/resurrect.txt" "$res_dir/resurrect.txt"

    LC_ALL="$utf8_locale" run "$BASH_BIN" "$SCRIPT" "$res_dir/resurrect.txt"
    [ "$status" -eq 0 ]
    [ -e "$res_dir/claude-env/older.env" ]
}

@test "under a UTF-8 locale, a value ending in an incomplete multibyte sequence does not swallow the next variable" {
    local utf8_locale pid proc_start env_file
    utf8_locale="$(locale -a 2>/dev/null | grep -ixE 'C\.utf-?8|en_US\.utf-?8' | head -n 1)" || true
    [ -n "$utf8_locale" ] || skip "no UTF-8 locale installed"
    # Order matters: env appends these in argument order, so the key directly
    # follows the value ending in \357 inside /proc/<pid>/environ.
    pid="$(spawn_fake_claude_pid_with_env $'ANTHROPIC_MODEL=model\357' ANTHROPIC_API_KEY=key-after-it CLAUDE_CONFIG_DIR=/cfg)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    LC_ALL="$utf8_locale" run_hook
    [ "$status" -eq 0 ]
    env_file="$BATS_TEST_TMPDIR/claude-env/session-abc.env"
    [ "$(last_field)" = ":${CLEAR_PREFIX}( . $(printf '%q' "$env_file"); ANTHROPIC_MODEL=\$'model\\357' CLAUDE_CONFIG_DIR=/cfg claude --resume session-abc )" ]
    grep -qx 'export ANTHROPIC_API_KEY=key-after-it' "$env_file"
}

@test "an alternate CLAUDE_CONFIG_DIR profile's session directory is also discovered" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    local alt_dir="$HOME/.claude-minimal/sessions"
    mkdir -p "$alt_dir"
    jq -n \
        --arg sessionId "session-alt" \
        --arg tmux "sess:@1.%1" \
        --arg cwd "/home/testuser/project" \
        --arg procStart "$proc_start" \
        --argjson updatedAt 100 \
        '{sessionId: $sessionId, tmux: $tmux, cwd: $cwd, procStart: $procStart, updatedAt: $updatedAt}' \
        >"$alt_dir/${pid}.json"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}claude --resume session-alt" ]
}

@test "no match in the index falls back to the picker" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "other:@9.%9" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "missing jq (symlink farm without jq) falls back to the picker" {
    local pid proc_start farm bin
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    farm="$BATS_TEST_TMPDIR/jq-missing-bin"
    mkdir -p "$farm"
    for bin in awk cut cat basename dirname mktemp mv rm; do
        ln -s "$(command -v "$bin")" "$farm/$bin"
    done
    ln -s "$STUB_BIN/tmux" "$farm/tmux"

    PATH="$farm" run "$BASH_BIN" "$SCRIPT" "$BATS_TEST_TMPDIR/resurrect.txt"
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "missing tmux falls back to the picker instead of leaving the file unchanged" {
    local pid proc_start farm bin
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    farm="$BATS_TEST_TMPDIR/tmux-missing-bin"
    mkdir -p "$farm"
    for bin in awk cut cat basename dirname mktemp mv rm jq; do
        ln -s "$(command -v "$bin")" "$farm/$bin"
    done

    PATH="$farm" run "$BASH_BIN" "$SCRIPT" "$BATS_TEST_TMPDIR/resurrect.txt"
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "stale PID (procStart mismatch) falls back to the picker" {
    local pid
    pid="$(spawn_fake_claude_pid)"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "999999999"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "with multiple candidates the most recently updated one wins" {
    local pid1 pid2 proc_start1 proc_start2
    pid1="$(spawn_fake_claude_pid)"
    proc_start1="$(proc_start_time_of "$pid1")"
    pid2="$(spawn_fake_claude_pid)"
    proc_start2="$(proc_start_time_of "$pid2")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    # pid1 (the higher, winning value) uses the updatedAt fallback to
    # startedAt (no "updatedAt" key) -- without that fallback its comparison
    # value would be 0 and pid2 (updatedAt=200) would win wrongly.
    # Covers (.updatedAt // .startedAt // 0).
    write_session_json_started_at "$pid1" "session-fallback" "sess:@1.%1" "/home/testuser/project" "$proc_start1" 300
    write_session_json "$pid2" "session-updatedat" "sess:@1.%1" "/home/testuser/project" "$proc_start2" 200
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}claude --resume session-fallback" ]
}

@test "non-claude pane stays unchanged" {
    write_resurrect_file "bash" ":/home/testuser/project"
    local before
    before="$(cat "$BATS_TEST_TMPDIR/resurrect.txt")"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/resurrect.txt")" = "$before" ]
}

@test "claude-code-proxy is NOT detected as claude" {
    write_resurrect_file "claude-code-proxy --foo" ":/home/testuser/project"
    local before
    before="$(cat "$BATS_TEST_TMPDIR/resurrect.txt")"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/resurrect.txt")" = "$before" ]
}

@test "/usr/bin/claude is detected via its basename and rewritten" {
    write_resurrect_file "/usr/bin/claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":claude --resume" ]
}

@test "cwd with an escaped space is resolved correctly" {
    local pid proc_start
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/my project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/my\\ project"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(last_field)" = ":${CLEAR_PREFIX}claude --resume session-abc" ]
}

@test "missing trailing newline: line content stays the same but gains one" {
    printf 'pane\tsess\t0\t0\t:0\t0\ttitle\t:/home/testuser/project\t1\tbash\t:bash' >"$BATS_TEST_TMPDIR/resurrect.txt"

    run_hook
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/resurrect.txt")" = "$(printf 'pane\tsess\t0\t0\t:0\t0\ttitle\t:/home/testuser/project\t1\tbash\t:bash')" ]
}

@test "realistic multi-line file: window/state lines untouched, two claude panes each get their own sessionId" {
    local pid1 pid2 proc_start1 proc_start2
    pid1="$(spawn_fake_claude_pid)"
    proc_start1="$(proc_start_time_of "$pid1")"
    pid2="$(spawn_fake_claude_pid)"
    proc_start2="$(proc_start_time_of "$pid2")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1\nsess\t1\t0\t@2\t%2\nsess\t2\t0\t@3\t%3'
    write_session_json "$pid1" "session-one" "sess:@1.%1" "/home/testuser/one" "$proc_start1" 100
    write_session_json_started_at "$pid2" "session-two" "sess:@2.%2" "/home/testuser/two" "$proc_start2" 50

    local IFS=$'\t' window_line pane_bash pane_claude1 pane_claude2 state_line
    window_line="window${IFS}sess${IFS}0${IFS}name${IFS}0${IFS}:0${IFS}layout"
    pane_bash="pane${IFS}sess${IFS}2${IFS}0${IFS}:0${IFS}0${IFS}title${IFS}:/home/testuser/three${IFS}1${IFS}bash${IFS}:bash"
    pane_claude1="pane${IFS}sess${IFS}0${IFS}0${IFS}:0${IFS}0${IFS}title${IFS}:/home/testuser/one${IFS}1${IFS}claude${IFS}:claude"
    pane_claude2="pane${IFS}sess${IFS}1${IFS}0${IFS}:0${IFS}0${IFS}title${IFS}:/home/testuser/two${IFS}1${IFS}claude${IFS}:claude"
    state_line="state${IFS}client_session${IFS}sess"

    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$window_line" "$pane_bash" "$pane_claude1" "$pane_claude2" "$state_line" \
        >"$BATS_TEST_TMPDIR/resurrect.txt"

    run_hook
    [ "$status" -eq 0 ]

    mapfile -t out_lines <"$BATS_TEST_TMPDIR/resurrect.txt"
    [ "${out_lines[0]}" = "$window_line" ]
    [ "${out_lines[1]}" = "$pane_bash" ]
    [ "${out_lines[2]##*$'\t'}" = ":${CLEAR_PREFIX}claude --resume session-one" ]
    [ "${out_lines[3]##*$'\t'}" = ":${CLEAR_PREFIX}claude --resume session-two" ]
    [ "${out_lines[4]}" = "$state_line" ]
}

# -----------------------------------------------------------------------------
# Execution tests: every test above only asserts the TEXT the hook writes.
# These two actually run that text in a bash subshell that stands in for a
# real restored pane's already-sourced-~/.bashrc shell -- deliberately
# pre-polluted with the exact kind of leaked global default
# (ANTHROPIC_DEFAULT_*) the fix exists to clear -- and inspect what the
# resumed "claude" process (a stub that dumps its own env) actually receives.
# Confirms two things a text-only assertion cannot: that the generated line
# is valid bash the target shell can execute at all, and that
# "${!ANTHROPIC_@}" behaves as documented with zero matches (expands to zero
# words, not one empty-string word that would otherwise show up as a bogus
# "unset ''" argument).
# -----------------------------------------------------------------------------

install_claude_env_dump_stub() {
    cat >"$STUB_BIN/claude" <<'EOF'
#!/bin/bash
env >"$CLAUDE_ENV_DUMP"
EOF
    chmod +x "$STUB_BIN/claude"
}

@test "executing the generated line clears a leaked default but keeps the captured var and an unrelated var" {
    local pid proc_start unset_args=() cmd out_env
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_MODEL=gpt-5.6-sol)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    cmd="$(last_field)"
    cmd="${cmd#:}"

    install_claude_env_dump_stub
    out_env="$BATS_TEST_TMPDIR/child-env"
    mapfile -t unset_args < <(claude_env_unset_args)
    # Simulates a restored pane's shell: clean of this test suite's own
    # ambient allowlist vars, then given the exact leaked global defaults
    # (as if sourced from ~/.bashrc) the fix must remove, plus one unrelated
    # var that must survive untouched.
    env "${unset_args[@]}" \
        CLAUDE_ENV_DUMP="$out_env" \
        ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3-flash \
        ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 \
        SOME_UNRELATED_VAR=keep-me \
        bash -c "$cmd"

    grep -qx 'ANTHROPIC_MODEL=gpt-5.6-sol' "$out_env"
    grep -qx 'SOME_UNRELATED_VAR=keep-me' "$out_env"
    ! grep -q '^ANTHROPIC_DEFAULT_' "$out_env"
}

@test "executing the generated line clears leaked defaults even when nothing was captured (zero-match unset)" {
    local pid proc_start unset_args=() cmd out_env
    pid="$(spawn_fake_claude_pid)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    cmd="$(last_field)"
    cmd="${cmd#:}"

    install_claude_env_dump_stub
    out_env="$BATS_TEST_TMPDIR/child-env-zero"
    mapfile -t unset_args < <(claude_env_unset_args)
    env "${unset_args[@]}" \
        CLAUDE_ENV_DUMP="$out_env" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.3-flash \
        SOME_UNRELATED_VAR=keep-me \
        bash -c "$cmd"

    grep -qx 'SOME_UNRELATED_VAR=keep-me' "$out_env"
    ! grep -q '^ANTHROPIC_' "$out_env"
}

@test "bash indirect-prefix expansion with zero matches yields zero words, not one empty word" {
    # Load-bearing assumption behind CLAUDE_ENV_CLEAR_PREFIX: with no
    # ANTHROPIC_*-named variable set, "${!ANTHROPIC_@}" must vanish entirely
    # (like "$@" with zero positional params) rather than leave a stray empty
    # string that would turn "unset ${!ANTHROPIC_@} X Y" into
    # "unset '' X Y" -- harmless for "unset" specifically, but this pins the
    # exact expansion behavior the fix depends on, independent of the hook.
    local unset_args=()
    mapfile -t unset_args < <(claude_env_unset_args)
    run env "${unset_args[@]}" bash -c 'f() { echo "$#"; }; f "${!ANTHROPIC_@}"'
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}


run_line_in_pane_shell() {
    local out_env="$1" cmd unset_args=()
    shift
    cmd="$(last_field)"
    cmd="${cmd#:}"
    install_claude_env_dump_stub
    mapfile -t unset_args < <(claude_env_unset_args)
    env "${unset_args[@]}" CLAUDE_ENV_DUMP="$out_env" "$@" bash -c "$cmd"
}

@test "executing the generated line restores the credential from the env file even though the pane shell has none" {
    local pid proc_start out_env="$BATS_TEST_TMPDIR/child-env-key"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=wrapper-only-key ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    ! grep -q 'wrapper-only-key' "$BATS_TEST_TMPDIR/resurrect.txt"

    run_line_in_pane_shell "$out_env" ANTHROPIC_DEFAULT_OPUS_MODEL=leaked
    grep -qx 'ANTHROPIC_API_KEY=wrapper-only-key' "$out_env"
    grep -qx 'ANTHROPIC_MODEL=m1' "$out_env"
    ! grep -q '^ANTHROPIC_DEFAULT_' "$out_env"
}

@test "ANTHROPIC_CUSTOM_HEADERS and a base URL with userinfo go to the env file and survive a restore" {
    local pid proc_start out_env="$BATS_TEST_TMPDIR/child-env-hdr"
    pid="$(spawn_fake_claude_pid_with_env 'ANTHROPIC_CUSTOM_HEADERS=Authorization: Bearer sekrit' ANTHROPIC_BASE_URL=https://user:pass@proxy.test/v1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    ! grep -qE 'sekrit|user:pass' "$BATS_TEST_TMPDIR/resurrect.txt"

    run_line_in_pane_shell "$out_env"
    grep -qx 'ANTHROPIC_CUSTOM_HEADERS=Authorization: Bearer sekrit' "$out_env"
    grep -qx 'ANTHROPIC_BASE_URL=https://user:pass@proxy.test/v1' "$out_env"
}

@test "a deliberately empty credential override stays inline and still clears the pane shell's own key" {
    local pid proc_start out_env="$BATS_TEST_TMPDIR/child-env-empty"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_API_KEY=)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/claude-env" ]

    run_line_in_pane_shell "$out_env" ANTHROPIC_API_KEY=global-default
    grep -qx 'ANTHROPIC_API_KEY=' "$out_env"
}

@test "stale env files of sessions no longer in the save file are removed" {
    local pid proc_start
    mkdir -p "$BATS_TEST_TMPDIR/claude-env"
    printf 'export ANTHROPIC_API_KEY=old\n' >"$BATS_TEST_TMPDIR/claude-env/gone.env"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/claude-env/gone.env" ]
}

@test "an env file still referenced by an older save file is kept" {
    local pid proc_start
    mkdir -p "$BATS_TEST_TMPDIR/claude-env"
    printf 'export ANTHROPIC_API_KEY=old\n' >"$BATS_TEST_TMPDIR/claude-env/older.env"
    printf 'pane\ts\t0\t:w\t1\t0\t:t\t:/x\t0\tclaude\t:( . %s; claude --resume older )\n' \
        "$(printf '%q' "$BATS_TEST_TMPDIR/claude-env/older.env")" \
        >"$BATS_TEST_TMPDIR/tmux_resurrect_20260101T000000.txt"
    pid="$(spawn_fake_claude_pid_with_env ANTHROPIC_MODEL=m1)"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    [ -e "$BATS_TEST_TMPDIR/claude-env/older.env" ]
}

# Like run_line_in_pane_shell, but types the line into an interactive bash
# (stdin, not -c), as tmux-resurrect's send-keys does: only there is history
# expansion active.
run_line_in_interactive_pane_shell() {
    local out_env="$1" cmd unset_args=()
    shift
    cmd="$(last_field)"
    cmd="${cmd#:}"
    install_claude_env_dump_stub
    mapfile -t unset_args < <(claude_env_unset_args)
    (cd "$BATS_TEST_TMPDIR" && env "${unset_args[@]}" HISTFILE=/dev/null CLAUDE_ENV_DUMP="$out_env" "$@" \
        bash --norc --noprofile -i <<<"$cmd" >"$BATS_TEST_TMPDIR/pane.log" 2>&1) || true
}

@test "a value containing ! goes to the env file, so history expansion cannot reject the restore line" {
    local pid proc_start out_env="$BATS_TEST_TMPDIR/child-env-bang"
    # %q renders the first as http://proxy.test/\"a and the second as
    # $'m!\001'; interactive bash's history expansion misreads that pair and
    # used to abort the whole line with "!ANTHROPIC_@}: event not found".
    pid="$(spawn_fake_claude_pid_with_env 'ANTHROPIC_BASE_URL=http://proxy.test/"a' $'ANTHROPIC_MODEL=m!\001')"
    proc_start="$(proc_start_time_of "$pid")"

    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    write_session_json "$pid" "session-abc" "sess:@1.%1" "/home/testuser/project" "$proc_start"
    write_resurrect_file "claude" ":/home/testuser/project"

    run_hook
    [ "$status" -eq 0 ]
    # The clear-prefix's "${!ANTHROPIC_@}" is the only "!" left in the line.
    [[ "$(last_field)" != *'!'*'!'* ]]
    grep -qF "export ANTHROPIC_MODEL=\$'m!\\001'" "$BATS_TEST_TMPDIR/claude-env/session-abc.env"

    run_line_in_interactive_pane_shell "$out_env"
    ! grep -q 'event not found' "$BATS_TEST_TMPDIR/pane.log"
    grep -qxF $'ANTHROPIC_MODEL=m!\001' "$out_env"
    grep -qxF 'ANTHROPIC_BASE_URL=http://proxy.test/"a' "$out_env"
}
