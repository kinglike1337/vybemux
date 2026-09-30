#!/usr/bin/env bats
# =============================================================================
# Regression test for the ai-tools-menu.sh command-injection bug (issue #50):
# a crafted pane_current_path must not let a chosen "AI Tools" menu item run
# arbitrary shell code through tmux's own command parser.
#
# scripts/ai-tools-menu.sh no longer bakes the resolved path into an item's
# command string; it embeds a "##{pane_current_path}" placeholder instead
# (see the comment above the `items=()` block in that script). tmux's
# display-menu expands an item's whole command *text* once, up front, before
# ever tokenizing it (menu_add_item() in tmux's own source): "##" collapses
# to a literal "#" during that pass without re-expanding what follows, so
# the *stored*, already-tokenized command still contains the placeholder as
# plain text; only new-window's own -c handling expands it later, into an
# argument slot parsing has already closed. An earlier version of this fix
# used tmux's "q:" format modifier to escape the value instead of deferring
# it -- that failed against a directory name containing a literal newline or
# tab, which "q:" does not escape and tmux's own parser treats specially
# regardless (a newline ends the current command, a tab splits tokens, both
# only when unquoted -- exactly the state "q:"'s escaping never reaches).
#
# This can't be proven by actually clicking a menu item: tmux's `send-keys`
# injects raw bytes into the pane instead of dispatching through the
# client's key/overlay tables (confirmed empirically), and there is no other
# scriptable way to deliver the keyboard/mouse event display-menu needs.
# It also can't be proven by driving an equivalent command (new-window,
# bind-key, source-file) with the raw #{...} text on the command line
# directly: every one of those expands formats per-argument *after* tmux's
# parser has already split the command into tokens, which is a different
# (and, on its own, order-safe) code path from display-menu's
# whole-string-first expansion.
#
# What reproduces the real mechanism without any keypress: `display -p -t
# <pane> '<template>'` runs the exact same whole-string format_single() call
# menu_add_item() runs on an item's command, and `source-file` parses+
# executes the result through the same string parser (cmd_parse_and_append()
# calls) a chosen menu item does. Piping the expanded text from the first
# into the second reproduces menu selection end to end, using the real
# per-item command template ai-tools-menu.sh actually builds (extracted from
# a stubbed run of the script itself, so this test can't silently drift from
# what the script emits).
# =============================================================================

TMUX_TEST_SOCKET=""

setup() {
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux is not installed"
    fi
    TMUX_TEST_SOCKET="vybemux-ai-tools-injection-$BATS_TEST_NUMBER-$$"
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]]; then
        tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
}

# Runs the real script with a stubbed tmux/claude and returns the exact
# command string it built for the "Claude (resume)" item (the third of the
# three lines display-menu logs per item: name, key, command). Using the
# script's own output, rather than a hand-typed copy of it, means this test
# fails loudly if the template ever changes shape instead of quietly testing
# a stale one. The stub's own "#{pane_current_path}" answer is the crafted
# `maldir`, not an unrelated placeholder: if a future change reintroduces
# resolving the path in bash (the original bug) instead of deferring it to
# tmux, the extracted template would then embed `maldir` directly and
# unescaped, and the negative tests below would fail again as they should --
# a fixed placeholder would hide that regression completely.
extract_resume_template() {
    local maldir="$1"
    local stub_bin="$BATS_TEST_TMPDIR/stubbin"
    local stub_log="$BATS_TEST_TMPDIR/stub.log"
    local maldir_file="$BATS_TEST_TMPDIR/maldir.txt"
    mkdir -p "$stub_bin"
    # maldir's bytes (quotes, newlines, ...) go into the stub's ANSWER via a
    # file, never interpolated into the heredoc-generated stub script's own
    # source text -- a literal '"' in maldir would otherwise break out of
    # the stub script's own quoting and corrupt it.
    printf '%s' "$maldir" >"$maldir_file"
    cat >"$stub_bin/tmux" <<EOF
#!/bin/bash
printf '%s\n' "\$@" >>"$stub_log"
case "\$1" in
    display)
        case "\$3" in
            '#{pane_current_path}') cat "$maldir_file" ;;
            '#{client_name}') echo "test-client" ;;
            '#{pane_id}') echo "%1" ;;
        esac
        ;;
esac
EOF
    chmod +x "$stub_bin/tmux"
    # Sleeps rather than exiting immediately: a dead pane's process is gone
    # by the time a test can inspect it, and #{pane_current_path} needs a
    # live process to resolve (it reads /proc/<pid>/cwd) -- an immediately
    # exiting stub would make the correctness test below race the pane's
    # own death instead of checking anything real.
    printf '#!/bin/bash\nsleep 5\n' >"$stub_bin/claude"
    chmod +x "$stub_bin/claude"
    : >"$stub_log"

    HOME="$BATS_TEST_TMPDIR/fakehome" PATH="$stub_bin:/usr/bin:/bin" \
        bash "$BATS_TEST_DIRNAME/../scripts/ai-tools-menu.sh" >/dev/null

    awk '/^c$/{getline; print; exit}' "$stub_log"
}

# Expands `template` against `pane`'s real context (the same whole-string
# format_single() call menu_add_item() performs) and parses+executes the
# result via source-file (the same string parser cmd_parse_and_append()
# uses for a chosen item), all with no client attached and no keypress.
# "-u" forces the client to treat its output as UTF-8: without it (and
# without a UTF-8 locale in the environment, e.g. under `env -i`) tmux
# replaces control bytes like the crafted newline/tab below with "_" in
# `display -p`'s output, neutralizing the payload in the test harness
# itself before source-file ever sees it -- the real menu is unaffected,
# since menu_add_item() expands server-side with no such client-side
# sanitizing.
run_menu_template() {
    local template="$1" pane="$2"
    local expanded cmdfile="$BATS_TEST_TMPDIR/expanded-$RANDOM.tmux"
    expanded="$(tmux -u -L "$TMUX_TEST_SOCKET" display -p -t "$pane" "$template")"
    printf '%s\n' "$expanded" >"$cmdfile"
    tmux -L "$TMUX_TEST_SOCKET" source-file "$cmdfile"
}

@test "a crafted directory with a newline and a tab cannot inject a second tmux command" {
    local workdir="$BATS_TEST_TMPDIR/work-nl"
    mkdir -p "$workdir"
    local nl=$'\n' tab=$'\t'
    local maldir="$workdir/a${nl}run-shell${tab}touch $workdir/pwned${nl}display-message"
    mkdir -p "$maldir"

    tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s main -x 200 -y 30 -c "$maldir"
    sleep 0.3

    local template
    template="$(extract_resume_template "$maldir")"
    run_menu_template "$template" main

    [ ! -e "$workdir/pwned" ]
}

@test "a crafted directory with a newline and a tab opens the new window in the real directory" {
    local workdir="$BATS_TEST_TMPDIR/work-nl-correct"
    mkdir -p "$workdir"
    local nl=$'\n' tab=$'\t'
    local maldir="$workdir/a${nl}run-shell${tab}touch $workdir/pwned${nl}display-message"
    mkdir -p "$maldir"

    tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s main -x 200 -y 30 -c "$maldir"
    sleep 0.3

    local template
    template="$(extract_resume_template "$maldir")"
    run_menu_template "$template" main
    sleep 0.3

    # Targeted directly by the window name the template sets (-n claude),
    # via command substitution rather than a line-oriented list/grep: the
    # malicious path itself contains embedded newlines, which "$(...)"
    # preserves (it only strips trailing ones) but a line-based tool would
    # split across several lines and defeat a naive textual match.
    local actual
    actual="$(tmux -u -L "$TMUX_TEST_SOCKET" display -p -t main:claude '#{pane_current_path}')"
    [ "$actual" = "$maldir" ]
}

@test "a crafted directory with a double-quote and a semicolon cannot inject a second tmux command" {
    local workdir="$BATS_TEST_TMPDIR/work-dquote"
    mkdir -p "$workdir"
    local maldir="$workdir/a\";touch $workdir/pwned;echo \"b"
    mkdir -p "$maldir"

    tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s main -x 200 -y 30 -c "$maldir"
    sleep 0.3

    local template
    template="$(extract_resume_template "$maldir")"
    run_menu_template "$template" main

    [ ! -e "$workdir/pwned" ]
}

@test "a crafted directory with a double-quote and a semicolon opens the new window in the real directory" {
    local workdir="$BATS_TEST_TMPDIR/work-dquote-correct"
    mkdir -p "$workdir"
    local maldir="$workdir/a\";touch $workdir/pwned;echo \"b"
    mkdir -p "$maldir"

    tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s main -x 200 -y 30 -c "$maldir"
    sleep 0.3

    local template
    template="$(extract_resume_template "$maldir")"
    run_menu_template "$template" main
    sleep 0.3

    local actual
    actual="$(tmux -u -L "$TMUX_TEST_SOCKET" display -p -t main:claude '#{pane_current_path}')"
    [ "$actual" = "$maldir" ]
}
