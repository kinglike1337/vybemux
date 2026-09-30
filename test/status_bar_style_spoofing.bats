#!/usr/bin/env bats
# =============================================================================
# Regression tests for status-bar style/click-range spoofing: tmux parses
# #[...] anywhere in a drawn string, so a session or window name containing
# e.g. #[bg=#ff0001] must not restyle the status line (or menu titles and
# prompts), and click ranges must not be redefinable through a name.
#
# Needs a real tmux server plus script(1) (util-linux) for an attached client,
# same as status_bar_shell_injection.bats (see there for why render_status_until
# polls and attaches read-only). The marker style bg=#ff0001 appears nowhere
# in the theme; with RGB it renders as the SGR sequence 48;2;255;0;1. A
# control test proves the marker is detectable when a name is NOT escaped, so
# "no marker" cannot pass vacuously.
# =============================================================================

PROJECT_CONFIG="$BATS_TEST_DIRNAME/../tmux.conf"
TMUX_TEST_SOCKET=""
MARKER_SGR='\x1b\[[0-9;]*48;2;255;0;1'

setup() {
    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux is not installed"
    fi
    if ! command -v script >/dev/null 2>&1; then
        skip "script (util-linux) is not installed"
    fi
    FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$FIXTURE_HOME/.tmux/scripts"
    cp "$BATS_TEST_DIRNAME/../scripts/"*.sh "$FIXTURE_HOME/.tmux/scripts/"
    TMUX_TEST_SOCKET="vybemux-spoof-$BATS_TEST_NUMBER-$$"
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]]; then
        tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
    wait 2>/dev/null || true
}

# Attaches a read-only client for a few seconds at a time, appending to the
# log, until `pattern` (grep -P) shows up or the timeout elapses.
render_status_until() {
    local log="$1" pattern="$2" timeout_s="${3:-8}"
    : >"$log"
    local elapsed=0 step=2
    while ((elapsed < timeout_s)); do
        TERM=xterm-256color timeout "$step" script -q -e -a \
            -c "tmux -L $TMUX_TEST_SOCKET attach-session -r" \
            "$log" </dev/null >/dev/null 2>&1 || true
        if grep -aqP -- "$pattern" "$log" 2>/dev/null; then
            return 0
        fi
        elapsed=$((elapsed + step))
    done
    return 1
}

start_server() {
    local session="$1" window="$2" config="${3:-$PROJECT_CONFIG}"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null \
        new-session -d -s "$session" -x 120 -y 24
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$config"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1
    tmux -L "$TMUX_TEST_SOCKET" set -g automatic-rename off
    # Without this, "set-titles-string #S | #W" writes the names into the
    # client's terminal title, and a positive marker could be satisfied by
    # the title alone without the status line ever rendering the name.
    tmux -L "$TMUX_TEST_SOCKET" set -g set-titles off
    tmux -L "$TMUX_TEST_SOCKET" rename-window -t "$session:0" "$window"
}

@test "a directory name with a #[...] style does not restyle status-right" {
    local maldir="$BATS_TEST_TMPDIR/work/#[bg=#ff0001]EVILDIR"
    mkdir -p "$maldir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null \
        new-session -d -s plain -x 120 -y 24 -c "$maldir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1
    tmux -L "$TMUX_TEST_SOCKET" set -g set-titles off

    # Positive marker: the status-right rendering, which shortens "work" to
    # "w". The pane's own shell prompt shows the full unshortened path, so
    # matching "/w/" (either the literal escaped text or, if the name were
    # not escaped, the injected style right before EVILDIR) can only come from
    # shorten-path.sh output.
    render_status_until "$BATS_TEST_TMPDIR/dir.log" \
        '/w/(#\[bg=#ff0001\]|\x1b\[[0-9;]*48;2;255;0;1m)EVILDIR'
    ! grep -aqP -- "$MARKER_SGR" "$BATS_TEST_TMPDIR/dir.log"
}

@test "a session name with a #[...] style does not restyle the status line" {
    start_server '#[bg=#ff0001]EVILSESSION' 'plain'

    render_status_until "$BATS_TEST_TMPDIR/session.log" 'EVILSESSION'
    ! grep -aqP -- "$MARKER_SGR" "$BATS_TEST_TMPDIR/session.log"
}

@test "a window name with a #[...] style does not restyle the status line" {
    start_server 'plain' '#[bg=#ff0001]EVILWINDOW'

    render_status_until "$BATS_TEST_TMPDIR/window.log" 'EVILWINDOW'
    ! grep -aqP -- "$MARKER_SGR" "$BATS_TEST_TMPDIR/window.log"
}

@test "control: an unescaped window name in the same format does restyle the status line" {
    # Source the project config first (it carries the RGB terminal feature the
    # marker colour needs; without it tmux downsamples #ff0001 to 256 colours
    # and the marker never appears), then override only the window formats.
    start_server 'plain' '#[bg=#ff0001]EVILWINDOW'
    tmux -L "$TMUX_TEST_SOCKET" setw -g window-status-format " #I:#W "
    tmux -L "$TMUX_TEST_SOCKET" setw -g window-status-current-format " #I:#W "

    render_status_until "$BATS_TEST_TMPDIR/control.log" "$MARKER_SGR"
}

@test "names with # are shown literally, not mangled, in the session list and window list" {
    start_server 'sess#1' 'win#2'

    render_status_until "$BATS_TEST_TMPDIR/literal.log" 'sess#1'
    grep -aq 'win#2' "$BATS_TEST_TMPDIR/literal.log"
}

@test "every use of a session/window name or pane title in a drawn format is escaped with q/h" {
    # Drawn contexts: status line, menu titles, prompts. command-prompt -I
    # (initial input text) and set-titles-string (terminal title) are not
    # style-parsed and are deliberately left alone. After removing the escaped
    # q/h forms, no raw reference (#S, #W, #T, #{session_name}, #{window_name},
    # #{pane_title}, including modifier forms such as #{=10:window_name}) may
    # remain on a line.
    local offenders
    offenders="$(grep -vE '^[[:space:]]*#' "$PROJECT_CONFIG" |
        grep -vE 'command-prompt .*-I "#[SW]"' |
        grep -vE 'set-titles-string' |
        sed -E 's/#\{q\/h:(session_name|window_name|pane_title)\}//g' |
        grep -E '#[SWT]([^A-Za-z0-9_]|$)|(session_name|window_name|pane_title)' || true)"
    [ -z "$offenders" ]
}
