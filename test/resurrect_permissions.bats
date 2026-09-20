#!/usr/bin/env bats
# =============================================================================
# Tests for tmux-resurrect data permissions
# =============================================================================

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$PROJECT_ROOT/scripts/harden-resurrect-permissions.sh"

@test "permission hook restricts the resurrect tree recursively" {
    local resurrect_dir="$BATS_TEST_TMPDIR/resurrect"
    mkdir -p "$resurrect_dir/save/pane_contents"
    printf 'layout\n' >"$resurrect_dir/tmux_resurrect_20260905T120000.txt"
    printf 'pane\n' >"$resurrect_dir/save/pane_contents/pane-%1"
    chmod 755 "$resurrect_dir" "$resurrect_dir/save" \
        "$resurrect_dir/save/pane_contents"
    chmod 644 "$resurrect_dir/tmux_resurrect_20260905T120000.txt" \
        "$resurrect_dir/save/pane_contents/pane-%1"

    run "$SCRIPT" "$resurrect_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$resurrect_dir")" = "700" ]
    [ "$(stat -c %a "$resurrect_dir/save")" = "700" ]
    [ "$(stat -c %a "$resurrect_dir/save/pane_contents")" = "700" ]
    [ "$(stat -c %a "$resurrect_dir/tmux_resurrect_20260905T120000.txt")" = "600" ]
    [ "$(stat -c %a "$resurrect_dir/save/pane_contents/pane-%1")" = "600" ]
}

@test "permission hook leaves unrelated files and execute bits unchanged" {
    local resurrect_dir="$BATS_TEST_TMPDIR/shared"
    mkdir -p "$resurrect_dir/save/pane_contents"
    printf 'layout\n' >"$resurrect_dir/tmux_resurrect_20260905T120000.txt"
    printf '#!/bin/bash\n' >"$resurrect_dir/unrelated-tool"
    printf '#!/bin/bash\n' >"$resurrect_dir/save/pane_contents/unrelated-tool"
    chmod 755 "$resurrect_dir" "$resurrect_dir/unrelated-tool" \
        "$resurrect_dir/save" "$resurrect_dir/save/pane_contents" \
        "$resurrect_dir/save/pane_contents/unrelated-tool"
    chmod 644 "$resurrect_dir/tmux_resurrect_20260905T120000.txt"

    run "$SCRIPT" "$resurrect_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$resurrect_dir")" = "755" ]
    [ "$(stat -c %a "$resurrect_dir/unrelated-tool")" = "755" ]
    [ "$(stat -c %a "$resurrect_dir/save")" = "755" ]
    [ "$(stat -c %a "$resurrect_dir/save/pane_contents/unrelated-tool")" = "755" ]
    [ "$(stat -c %a "$resurrect_dir/tmux_resurrect_20260905T120000.txt")" = "600" ]
}

@test "permission hook follows a symlinked resurrect root" {
    local target_dir="$BATS_TEST_TMPDIR/private-store"
    local resurrect_link="$BATS_TEST_TMPDIR/resurrect"
    mkdir -p "$target_dir"
    printf 'layout\n' >"$target_dir/tmux_resurrect_20260905T120000.txt"
    chmod 755 "$target_dir"
    chmod 644 "$target_dir/tmux_resurrect_20260905T120000.txt"
    ln -s "$target_dir" "$resurrect_link"

    run "$SCRIPT" "$resurrect_link"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$target_dir")" = "700" ]
    [ "$(stat -c %a "$target_dir/tmux_resurrect_20260905T120000.txt")" = "600" ]
}

@test "permission hook protects known pane files beside a custom artifact" {
    local resurrect_dir="$BATS_TEST_TMPDIR/resurrect"
    mkdir -p "$resurrect_dir/restore/pane_contents"
    printf 'geometry\n' >"$resurrect_dir/geometry"
    printf 'pane\n' >"$resurrect_dir/restore/pane_contents/pane-%1"
    chmod 755 "$resurrect_dir" "$resurrect_dir/restore" \
        "$resurrect_dir/restore/pane_contents"
    chmod 644 "$resurrect_dir/geometry" \
        "$resurrect_dir/restore/pane_contents/pane-%1"

    run "$SCRIPT" "$resurrect_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$resurrect_dir/geometry")" = "644" ]
    [ "$(stat -c %a "$resurrect_dir/restore/pane_contents/pane-%1")" = "600" ]
}

@test "permission hook creates the default resurrect directory securely" {
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_bin"
    printf '#!/bin/bash\nexit 1\n' >"$stub_bin/tmux"
    chmod +x "$stub_bin/tmux"

    run env -u XDG_DATA_HOME HOME="$BATS_TEST_TMPDIR/home" \
        PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$BATS_TEST_TMPDIR/home/.local/share/tmux/resurrect")" = "700" ]
    [ ! -e "$BATS_TEST_TMPDIR/home/.tmux/resurrect" ]
}

@test "permission hook matches upstream when hostname is unavailable" {
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    local configured_dir="$BATS_TEST_TMPDIR/base/\$HOSTNAME/resurrect"
    local expected_dir="$BATS_TEST_TMPDIR/base/resurrect"
    local command_name
    mkdir -p "$stub_bin"
    for command_name in chmod find mkdir; do
        ln -s "$(command -v "$command_name")" "$stub_bin/$command_name"
    done

    run env HOME="$BATS_TEST_TMPDIR/home" HOSTNAME=fixture-host \
        PATH="$stub_bin" "$SCRIPT" "$configured_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$expected_dir")" = "700" ]
    [ ! -e "$BATS_TEST_TMPDIR/base/fixture-host/resurrect" ]
    [ ! -e "$configured_dir" ]
}

@test "permission hook tolerates a failing hostname command" {
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    local configured_dir="$BATS_TEST_TMPDIR/base/\$HOSTNAME/resurrect"
    local expected_dir="$BATS_TEST_TMPDIR/base/resurrect"
    local command_name
    mkdir -p "$stub_bin"
    for command_name in chmod find mkdir; do
        ln -s "$(command -v "$command_name")" "$stub_bin/$command_name"
    done
    printf '#!/bin/bash\nexit 42\n' >"$stub_bin/hostname"
    chmod +x "$stub_bin/hostname"

    run env HOME="$BATS_TEST_TMPDIR/home" HOSTNAME=fixture-host \
        PATH="$stub_bin" "$SCRIPT" "$configured_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$expected_dir")" = "700" ]
    [ ! -e "$BATS_TEST_TMPDIR/base/fixture-host/resurrect" ]
    [ ! -e "$configured_dir" ]
}

@test "permission hook preserves the legacy default when it already exists" {
    local home_dir="$BATS_TEST_TMPDIR/home"
    local resurrect_dir="$home_dir/.tmux/resurrect"
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$resurrect_dir" "$stub_bin"
    printf '#!/bin/bash\nexit 1\n' >"$stub_bin/tmux"
    chmod +x "$stub_bin/tmux"
    chmod 755 "$resurrect_dir"

    run env -u XDG_DATA_HOME HOME="$home_dir" \
        PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$resurrect_dir")" = "700" ]
    [ ! -e "$home_dir/.local/share/tmux/resurrect" ]
}

@test "permission hook honors the configured XDG data directory" {
    local home_dir="$BATS_TEST_TMPDIR/home"
    local xdg_dir="$BATS_TEST_TMPDIR/xdg"
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_bin"
    printf '#!/bin/bash\nexit 1\n' >"$stub_bin/tmux"
    chmod +x "$stub_bin/tmux"

    run env HOME="$home_dir" XDG_DATA_HOME="$xdg_dir" \
        PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$xdg_dir/tmux/resurrect")" = "700" ]
}

@test "permission hook honors an explicit tmux-resurrect directory" {
    local home_dir="$BATS_TEST_TMPDIR/home"
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_bin"
    cat >"$stub_bin/tmux" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" == "@resurrect-dir" ]]; then
    printf '%s\n' "$CUSTOM_RESURRECT_DIR"
fi
EOF
    chmod +x "$stub_bin/tmux"

    run env HOME="$home_dir" CUSTOM_RESURRECT_DIR='~/custom-resurrect' \
        PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$home_dir/custom-resurrect")" = "700" ]
    [ ! -e "$home_dir/.local/share/tmux/resurrect" ]
}

@test "permission hook matches tmux-resurrect global tilde expansion" {
    local home_dir="$BATS_TEST_TMPDIR/home"
    local configured_dir="$BATS_TEST_TMPDIR/custom~/resurrect"
    local expected_dir="${configured_dir//\~/$home_dir}"

    run env HOME="$home_dir" "$SCRIPT" "$configured_dir"

    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$expected_dir")" = "700" ]
    [ ! -e "$configured_dir" ]
}

@test "permission hook runs a configured user post-save command" {
    local resurrect_dir="$BATS_TEST_TMPDIR/resurrect"
    local marker="$BATS_TEST_TMPDIR/user-hook-ran"
    local stub_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$resurrect_dir" "$stub_bin"
    cat >"$stub_bin/tmux" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" == "@vybemux-resurrect-hook-post-save-all" ]]; then
    printf '%s\n' 'printf hook-ran >"$HOOK_MARKER"'
fi
EOF
    chmod +x "$stub_bin/tmux"

    run env HOME="$BATS_TEST_TMPDIR/home" HOOK_MARKER="$marker" \
        PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT" --run-user-hook "$resurrect_dir"

    [ "$status" -eq 0 ]
    [ "$(cat "$marker")" = "hook-ran" ]
}

@test "tmux-resurrect runs permission hardening after the complete save" {
    run grep -F \
        "set -goFq @vybemux-resurrect-hook-post-save-all '#{@resurrect-hook-post-save-all}'" \
        "$PROJECT_ROOT/tmux.conf"

    [ "$status" -eq 0 ]
    run grep -F \
        "set -g @resurrect-hook-post-save-all '~/.tmux/scripts/harden-resurrect-permissions.sh --run-user-hook'" \
        "$PROJECT_ROOT/tmux.conf"

    [ "$status" -eq 0 ]
}
