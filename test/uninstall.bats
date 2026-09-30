#!/usr/bin/env bats
# =============================================================================
# Tests for uninstall.sh data-preservation behavior
# =============================================================================

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
    FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$FIXTURE_HOME/.tmux/scripts" "$FIXTURE_HOME/.tmux/resurrect" \
        "$FIXTURE_HOME/source-plugins"
    printf 'conf\n' >"$FIXTURE_HOME/.tmux.conf"
    printf 'bash\n' >"$FIXTURE_HOME/.tmux.bash"
    printf 'script\n' >"$FIXTURE_HOME/.tmux/scripts/about.sh"
    printf '1.0.0\n' >"$FIXTURE_HOME/.tmux/VERSION"
    printf 'v1.0.0\n' >"$FIXTURE_HOME/.tmux/VERSION_GIT"
    ln -s "$FIXTURE_HOME/source-plugins" "$FIXTURE_HOME/.tmux/plugins"
    printf 'saved session\n' >"$FIXTURE_HOME/.tmux/resurrect/tmux_resurrect_1.txt"
}

run_uninstall() {
    run env HOME="$FIXTURE_HOME" bash "$PROJECT_ROOT/uninstall.sh" \
        <<<$'y\nn'
}

@test "uninstall keeps saved tmux-resurrect sessions and other user files in ~/.tmux" {
    printf 'mine\n' >"$FIXTURE_HOME/.tmux/my-notes.txt"

    run_uninstall

    [ "$status" -eq 0 ]
    [ "$(cat "$FIXTURE_HOME/.tmux/resurrect/tmux_resurrect_1.txt")" = "saved session" ]
    [ "$(cat "$FIXTURE_HOME/.tmux/my-notes.txt")" = "mine" ]
    [[ "$output" == *"will be kept"* ]]
    [[ "$output" == *".tmux/resurrect"* ]]
}

@test "uninstall removes exactly what the installer created" {
    run_uninstall

    [ "$status" -eq 0 ]
    [ ! -e "$FIXTURE_HOME/.tmux.conf" ]
    [ ! -e "$FIXTURE_HOME/.tmux.bash" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts" ]
    [ ! -e "$FIXTURE_HOME/.tmux/VERSION" ]
    [ ! -e "$FIXTURE_HOME/.tmux/VERSION_GIT" ]
    [ ! -L "$FIXTURE_HOME/.tmux/plugins" ]
}

@test "uninstall removes the plugins symlink but never the directory it points to" {
    printf 'plugin\n' >"$FIXTURE_HOME/source-plugins/keep.txt"

    run_uninstall

    [ "$status" -eq 0 ]
    [ ! -L "$FIXTURE_HOME/.tmux/plugins" ]
    [ "$(cat "$FIXTURE_HOME/source-plugins/keep.txt")" = "plugin" ]
}

@test "uninstall removes ~/.tmux itself when nothing else is left in it" {
    rm -r "$FIXTURE_HOME/.tmux/resurrect"

    run_uninstall

    [ "$status" -eq 0 ]
    [ ! -e "$FIXTURE_HOME/.tmux" ]
}

@test "uninstall leaves a real plugins directory that is not the installer's symlink" {
    rm "$FIXTURE_HOME/.tmux/plugins"
    mkdir "$FIXTURE_HOME/.tmux/plugins"
    printf 'own plugin\n' >"$FIXTURE_HOME/.tmux/plugins/mine.txt"

    run_uninstall

    [ "$status" -eq 0 ]
    [ "$(cat "$FIXTURE_HOME/.tmux/plugins/mine.txt")" = "own plugin" ]
}

@test "uninstall keeps and lists files the user added to ~/.tmux/scripts" {
    printf 'mine\n' >"$FIXTURE_HOME/.tmux/scripts/my-own.sh"

    run_uninstall

    [ "$status" -eq 0 ]
    [ "$(cat "$FIXTURE_HOME/.tmux/scripts/my-own.sh")" = "mine" ]
    [ ! -e "$FIXTURE_HOME/.tmux/scripts/about.sh" ]
    [[ "$output" == *"will be kept"* ]]
    [[ "$output" == *".tmux/scripts/my-own.sh"* ]]
}

@test "a second run with only resurrect data left has nothing to uninstall and does not ask" {
    run_uninstall
    [ "$status" -eq 0 ]

    run env HOME="$FIXTURE_HOME" bash "$PROJECT_ROOT/uninstall.sh" <<<'n'

    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to uninstall"* ]]
    [[ "$output" != *"Do you want to continue?"* ]]
    [ "$(cat "$FIXTURE_HOME/.tmux/resurrect/tmux_resurrect_1.txt")" = "saved session" ]
}

@test "the uninstaller's script list matches the scripts install.sh copies" {
    local installed uninstalled
    installed="$(grep -o 'TMUX_SCRIPTS_DIR/[a-z-]*\.sh"$' "$PROJECT_ROOT/install.sh" |
        sed 's|TMUX_SCRIPTS_DIR/||; s|"$||' | sort -u)"
    uninstalled="$(sed -n '/^INSTALLED_SCRIPTS=(/,/^)/p' "$PROJECT_ROOT/uninstall.sh" |
        grep -o '[a-z-]*\.sh' | sort -u)"

    [ -n "$installed" ]
    [ "$installed" = "$uninstalled" ]
}

@test "uninstall removes only the exact source line and leaves commented-out lines alone" {
    printf '%s\n' 'export A=1' \
        '# [ -f ~/.tmux.bash ] && . ~/.tmux.bash' \
        '[ -f ~/.tmux.bash ] && . ~/.tmux.bash' \
        'export B=2' >"$FIXTURE_HOME/.bashrc"
    chmod 640 "$FIXTURE_HOME/.bashrc"

    run_uninstall

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed source line from ~/.bashrc"* ]]
    [ "$(cat "$FIXTURE_HOME/.bashrc")" = "$(printf '%s\n' 'export A=1' '# [ -f ~/.tmux.bash ] && . ~/.tmux.bash' 'export B=2')" ]
    [ "$(stat -c %a "$FIXTURE_HOME/.bashrc")" = "640" ]
}

@test "uninstall reports no source line and leaves .bashrc untouched when only a commented-out line exists" {
    printf '# [ -f ~/.tmux.bash ] && . ~/.tmux.bash\n' >"$FIXTURE_HOME/.bashrc"

    run_uninstall

    [ "$status" -eq 0 ]
    [[ "$output" == *"No vybemux source line found"* ]]
    [[ "$output" != *"Removed source line"* ]]
    [ "$(cat "$FIXTURE_HOME/.bashrc")" = "# [ -f ~/.tmux.bash ] && . ~/.tmux.bash" ]
    [ ! -e "$FIXTURE_HOME/.bashrc.vybemux-uninstall-backup" ]
}

@test "an indented source line inside a block becomes a no-op so .bashrc stays valid" {
    printf '%s\n' 'case $- in *i*) ;; *) return;; esac' \
        'if [ -n "$PS1" ]; then' \
        '  [ -f ~/.tmux.bash ] && . ~/.tmux.bash' \
        'fi' >"$FIXTURE_HOME/.bashrc"

    run_uninstall

    [ "$status" -eq 0 ]
    run bash -n "$FIXTURE_HOME/.bashrc"
    [ "$status" -eq 0 ]
    ! grep -q '\.tmux\.bash' "$FIXTURE_HOME/.bashrc"
    grep -qx '  : # vybemux source line removed' "$FIXTURE_HOME/.bashrc"
}

@test "uninstall leaves no temporary copy of .bashrc behind" {
    printf '[ -f ~/.tmux.bash ] && . ~/.tmux.bash\n' >"$FIXTURE_HOME/.bashrc"

    run_uninstall

    [ "$status" -eq 0 ]
    run bash -c "ls -A '$FIXTURE_HOME' | grep -E '^\.bashrc\.[A-Za-z0-9]{6}$'"
    [ "$status" -ne 0 ]
}
