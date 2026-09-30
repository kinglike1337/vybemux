#!/usr/bin/env bats
# =============================================================================
# Tests for install.sh release-safety behavior
# =============================================================================

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
    FIXTURE_REPO="$BATS_TEST_TMPDIR/repo"
    FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_HOME" "$STUB_BIN"

    cp "$PROJECT_ROOT/install.sh" "$PROJECT_ROOT/tmux.conf" \
        "$PROJECT_ROOT/tmux.bash" "$PROJECT_ROOT/tmux.conf.local.example" \
        "$PROJECT_ROOT/VERSION" "$FIXTURE_REPO/"
    cp "$PROJECT_ROOT"/scripts/*.sh "$FIXTURE_REPO/scripts/"

    mkdir -p \
        "$FIXTURE_REPO/plugins/tpm" \
        "$FIXTURE_REPO/plugins/tmux-resurrect/scripts" \
        "$FIXTURE_REPO/plugins/tmux-continuum" \
        "$FIXTURE_REPO/plugins/tmux-yank"
    touch \
        "$FIXTURE_REPO/plugins/tpm/tpm" \
        "$FIXTURE_REPO/plugins/tmux-resurrect/scripts/save.sh" \
        "$FIXTURE_REPO/plugins/tmux-continuum/continuum.tmux" \
        "$FIXTURE_REPO/plugins/tmux-yank/yank.tmux"

    cat >"$STUB_BIN/tmux" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "-V" ]]; then
    printf '%s\n' "${TMUX_VERSION_OUTPUT:-tmux 3.6}"
    exit 0
fi
for argument in "$@"; do
    if [[ "$argument" == "source-file" ]]; then
        calls_file="${TMUX_SOURCE_CALLS_FILE:-/dev/null}"
        calls=$(($(cat "$calls_file" 2>/dev/null || echo 0) + 1))
        [[ "$calls_file" == /dev/null ]] || printf '%s\n' "$calls" >"$calls_file"
        if [[ "$calls" -eq "${TMUX_SOURCE_FAIL_ON_CALL:-0}" ]]; then
            exit 1
        fi
        exit "${TMUX_SOURCE_STATUS:-0}"
    fi
done
exit 0
EOF
    cat >"$STUB_BIN/date" <<'EOF'
#!/bin/bash
printf '2026-09-04_120000\n'
EOF
    chmod +x "$STUB_BIN/tmux" "$STUB_BIN/date"
    export PATH="$STUB_BIN:/usr/bin:/bin"
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg"
}

@test "installer rejects a checkout whose plugin directories are empty" {
    rm "$FIXTURE_REPO/plugins/tpm/tpm"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Plugin content missing"* ]]
}

@test "same-second installations preserve the original backup" {
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"
    [ "$status" -eq 0 ]
    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"
    [ "$status" -eq 0 ]

    run find "$FIXTURE_HOME/.vybemux-backup" -mindepth 1 -maxdepth 1 -type d
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    run grep -Rlx 'original user configuration' "$FIXTURE_HOME/.vybemux-backup"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "installer aborts on tmux older than 3.5 before touching anything" {
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"

    run env HOME="$FIXTURE_HOME" TMUX_VERSION_OUTPUT="tmux 3.4" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"requires tmux >= 3.5. Your version: 3.4"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ ! -e "$FIXTURE_HOME/.vybemux-backup" ]
    [ ! -e "$FIXTURE_HOME/.tmux" ]
}

@test "installer --force installs on tmux older than 3.5 with a warning" {
    run env HOME="$FIXTURE_HOME" TMUX_VERSION_OUTPUT="tmux 3.4" \
        bash "$FIXTURE_REPO/install.sh" --force

    [ "$status" -eq 0 ]
    [[ "$output" == *"Continuing because --force was given"* ]]
    [ -f "$FIXTURE_HOME/.tmux.conf" ]
}

@test "installer only warns when the tmux version cannot be determined" {
    run env HOME="$FIXTURE_HOME" TMUX_VERSION_OUTPUT="tmux master" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not determine the tmux version"* ]]
}

@test "installer does not warn for tmux 3.5a, 3.6 or a next-3.7 development build" {
    local version_output
    for version_output in "tmux 3.5a" "tmux 3.6" "tmux next-3.7"; do
        run env HOME="$FIXTURE_HOME" TMUX_VERSION_OUTPUT="$version_output" \
            bash "$FIXTURE_REPO/install.sh"
        [ "$status" -eq 0 ]
        [[ "$output" != *"requires tmux >= 3.5"* ]]
    done
}

@test "installer fails when source-file reports an invalid tmux config" {
    run env HOME="$FIXTURE_HOME" TMUX_SOURCE_STATUS=1 \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"tmux.conf contains syntax errors"* ]]
}

@test "installer validates the new config before touching an existing installation" {
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"

    run env HOME="$FIXTURE_HOME" TMUX_SOURCE_STATUS=1 \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Nothing was changed"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ ! -e "$FIXTURE_HOME/.vybemux-backup" ]
    [ ! -e "$FIXTURE_HOME/.tmux" ]
}

@test "installer restores the previous installation when validation of the installed config fails" {
    mkdir -p "$FIXTURE_HOME/.tmux/scripts"
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"
    printf 'original bash integration\n' >"$FIXTURE_HOME/.tmux.bash"
    printf 'old script\n' >"$FIXTURE_HOME/.tmux/scripts/old.sh"
    printf '0.0.0\n' >"$FIXTURE_HOME/.tmux/VERSION"

    run env HOME="$FIXTURE_HOME" TMUX_SOURCE_FAIL_ON_CALL=2 \
        TMUX_SOURCE_CALLS_FILE="$BATS_TEST_TMPDIR/source-calls" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"restoring the previous installation"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ "$(cat "$FIXTURE_HOME/.tmux.bash")" = "original bash integration" ]
    [ "$(cat "$FIXTURE_HOME/.tmux/scripts/old.sh")" = "old script" ]
    [ "$(cat "$FIXTURE_HOME/.tmux/VERSION")" = "0.0.0" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts/shorten-path.sh" ]
    [ ! -e "$FIXTURE_HOME/.tmux/plugins" ]
}

@test "installer restores the previous installation when a step after the backup fails" {
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"
    printf '#!/bin/bash\nexit 1\n' >"$FIXTURE_REPO/scripts/harden-resurrect-permissions.sh"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Installation did not complete"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts" ]
    [ ! -e "$FIXTURE_HOME/.tmux/plugins" ]
}

@test "installer restores the previous installation when interrupted by SIGTERM" {
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"
    printf '#!/bin/bash\nkill -TERM "$PPID"\n' >"$FIXTURE_REPO/scripts/harden-resurrect-permissions.sh"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 143 ]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts" ]
}

@test "an abort during the backup phase never deletes files that were not backed up yet" {
    mkdir -p "$FIXTURE_HOME/.tmux/scripts"
    printf 'original user configuration\n' >"$FIXTURE_HOME/.tmux.conf"
    printf 'mine\n' >"$FIXTURE_HOME/.tmux/scripts/my-own.sh"
    printf '0.0.0\n' >"$FIXTURE_HOME/.tmux/VERSION"
    cat >"$STUB_BIN/mv" <<'STUB'
#!/bin/bash
for argument in "$@"; do
    if [[ "$argument" == */.tmux/scripts ]]; then
        echo "mv: simulated failure" >&2
        exit 1
    fi
done
exec /bin/mv "$@"
STUB
    chmod +x "$STUB_BIN/mv"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"restoring the previous installation"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux.conf")" = "original user configuration" ]
    [ "$(cat "$FIXTURE_HOME/.tmux/scripts/my-own.sh")" = "mine" ]
    [ "$(cat "$FIXTURE_HOME/.tmux/VERSION")" = "0.0.0" ]
}

@test "installer removes its own files when validation fails on a first installation" {
    run env HOME="$FIXTURE_HOME" TMUX_SOURCE_FAIL_ON_CALL=2 \
        TMUX_SOURCE_CALLS_FILE="$BATS_TEST_TMPDIR/source-calls" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 1 ]
    [ ! -e "$FIXTURE_HOME/.tmux.conf" ]
    [ ! -e "$FIXTURE_HOME/.tmux.bash" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts" ]
    [ ! -e "$FIXTURE_HOME/.tmux/plugins" ]
}

@test "installer restricts existing resurrect data permissions" {
    local resurrect_dir="$FIXTURE_HOME/.local/share/tmux/resurrect"
    mkdir -p "$resurrect_dir"
    printf 'saved pane data\n' >"$resurrect_dir/pane_contents.tar.gz"
    chmod 755 "$resurrect_dir"
    chmod 644 "$resurrect_dir/pane_contents.tar.gz"

    run env -u XDG_DATA_HOME HOME="$FIXTURE_HOME" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$resurrect_dir")" = "700" ]
    [ "$(stat -c %a "$resurrect_dir/pane_contents.tar.gz")" = "600" ]
    [ -x "$FIXTURE_HOME/.tmux/scripts/harden-resurrect-permissions.sh" ]
    [ ! -e "$FIXTURE_HOME/.tmux/resurrect" ]
}

@test "installer also restricts inactive legacy and XDG resurrect stores" {
    local legacy_dir="$FIXTURE_HOME/.tmux/resurrect"
    local xdg_dir="$FIXTURE_HOME/.local/share/tmux/resurrect"
    mkdir -p "$legacy_dir" "$xdg_dir"
    printf 'legacy\n' >"$legacy_dir/tmux_resurrect_legacy.txt"
    printf 'xdg\n' >"$xdg_dir/tmux_resurrect_xdg.txt"
    chmod 755 "$legacy_dir" "$xdg_dir"
    chmod 644 "$legacy_dir/tmux_resurrect_legacy.txt" \
        "$xdg_dir/tmux_resurrect_xdg.txt"

    run env -u XDG_DATA_HOME HOME="$FIXTURE_HOME" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$legacy_dir")" = "700" ]
    [ "$(stat -c %a "$xdg_dir")" = "700" ]
    [ "$(stat -c %a "$legacy_dir/tmux_resurrect_legacy.txt")" = "600" ]
    [ "$(stat -c %a "$xdg_dir/tmux_resurrect_xdg.txt")" = "600" ]
}

@test "status flags a plugins symlink whose source directory is gone" {
    mkdir -p "$FIXTURE_HOME/.tmux"
    ln -s "$BATS_TEST_TMPDIR/deleted-clone/plugins" "$FIXTURE_HOME/.tmux/plugins"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh" --status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins symlink is dangling"* ]]
    [[ "$output" == *"deleted-clone/plugins"* ]]
}

@test "status reports a healthy plugins symlink as found" {
    mkdir -p "$FIXTURE_HOME/.tmux"
    ln -s "$FIXTURE_REPO/plugins" "$FIXTURE_HOME/.tmux/plugins"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh" --status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins directory found"* ]]
    [[ "$output" != *"dangling"* ]]
    [[ "$output" != *"another checkout"* ]]
}

@test "status shows the plugins link target and warns when it points to another checkout" {
    mkdir -p "$FIXTURE_HOME/.tmux" "$BATS_TEST_TMPDIR/other-clone/plugins"
    ln -s "$BATS_TEST_TMPDIR/other-clone/plugins" "$FIXTURE_HOME/.tmux/plugins"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh" --status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Plugins directory found: $FIXTURE_HOME/.tmux/plugins -> $BATS_TEST_TMPDIR/other-clone/plugins"* ]]
    [[ "$output" == *"Plugins link to another checkout"* ]]
}

@test "a commented-out source line does not count as already sourcing tmux.bash" {
    printf '# [ -f ~/.tmux.bash ] && . ~/.tmux.bash\n' >"$FIXTURE_HOME/.bashrc"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"does not source"* ]]
    [[ "$output" != *"already sources"* ]]
}

@test "a differently written line does not count as the source line" {
    printf 'test -f ~/.tmux.bash && . ~/.tmux.bash\n' >"$FIXTURE_HOME/.bashrc"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"does not source"* ]]
}

@test "the exact source line, even indented or with CRLF, counts as already sourced" {
    printf 'export A=1\n  [ -f ~/.tmux.bash ] && . ~/.tmux.bash\r\n' >"$FIXTURE_HOME/.bashrc"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"already sources"* ]]
}

@test "status does not report a commented-out source line as found" {
    printf '# [ -f ~/.tmux.bash ] && . ~/.tmux.bash\n' >"$FIXTURE_HOME/.bashrc"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh" --status

    [[ "$output" == *"Source line NOT found"* ]]
}

@test "a broken ~/.tmux.conf.local only warns, the installation still completes" {
    printf 'this-is-not-a-real-tmux-command\n' >"$FIXTURE_HOME/.tmux.conf.local"

    run env HOME="$FIXTURE_HOME" TMUX_SOURCE_FAIL_ON_CALL=3 \
        TMUX_SOURCE_CALLS_FILE="$BATS_TEST_TMPDIR/source-calls" \
        bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Your ~/.tmux.conf.local has errors"* ]]
    [[ "$output" == *"installed successfully"* ]]
    [ -f "$FIXTURE_HOME/.tmux.conf" ]
    [ -d "$FIXTURE_HOME/.tmux/scripts" ]
}

@test "a valid ~/.tmux.conf.local produces no override warning" {
    printf 'set -g mouse on\n' >"$FIXTURE_HOME/.tmux.conf.local"

    run env HOME="$FIXTURE_HOME" bash "$FIXTURE_REPO/install.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *"has errors"* ]]
}
