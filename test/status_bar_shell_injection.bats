#!/usr/bin/env bats
# =============================================================================
# Regression tests for the status-bar shell-injection class of bug:
# tmux.conf's status-left/status-right #(...) commands must not let a
# crafted session or directory name run arbitrary shell code when tmux
# expands #{session_name}/#{pane_current_path} into the command line before
# handing it to sh -c.
#
# Requires a real tmux server (no PATH stub, same reasoning as
# validate_tmux_conf.bats) plus `script` (util-linux) to force a status-line
# render: #(...) status-line jobs are only executed for an attached client,
# so a plain `new-session -d` + `source-file` never triggers them.
#
# tmux.conf invokes scripts via "~/.tmux/scripts/...", so $FIXTURE_HOME must
# have a real copy of the current scripts/ there (mirroring what install.sh
# does) -- otherwise the #(...) job just fails with "No such file or
# directory" and every assertion below would pass vacuously, having tested
# nothing.
#
# A session name embedded in a marker path must not contain '.' or ':':
# tmux silently rewrites those to '_' in session names (they are the
# session:window.pane target separators), which would corrupt the injected
# path and make a real exploit look like a false negative. $BATS_TEST_TMPDIR
# is safe (no dots), a plain mktemp -d path (e.g. /tmp/tmp.XXXXXXXXXX) is not.
#
# Rendering is driven by render_status_until(), not a fixed sleep window,
# for two reasons found running this under CI-like conditions (closed
# stdin, loaded runner):
#   - attach-session (no -r) forwards a closed/absent stdin's EOF to the
#     pane's shell as ^D, which logs it out and ends the client before any
#     #(...) job output is ever rendered -- attach read-only (-r) ignores
#     input instead.
#   - tmux redraws the status line differentially: a cell that hasn't
#     changed since the previous frame isn't re-emitted, so a fixed-size
#     capture window can catch a frame where the expected text is split
#     across writes (or not fully drawn yet) even though the render is
#     correct moments later. Polling for the expected content, up to a
#     timeout, waits out that raciness instead of gambling on one snapshot.
# =============================================================================

PROJECT_CONFIG="$BATS_TEST_DIRNAME/../tmux.conf"
TMUX_TEST_SOCKET=""

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
    TMUX_TEST_SOCKET="vybemux-injection-$BATS_TEST_NUMBER-$$"
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]]; then
        tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
    wait 2>/dev/null || true
}

# Repeatedly attaches a read-only client (ignores input, so a closed/absent
# stdin can't EOF the pane's shell and end the client before anything
# renders) for a couple of seconds at a time, appending to the same log,
# until `pattern` (a grep -P regex) shows up or `timeout_s` total elapses.
# `script` must run in the foreground here -- backgrounding it stops it from
# writing the typescript file at all in this environment -- so genuine
# "stop the instant it appears" polling isn't possible; instead, each
# fresh attach forces tmux to redraw the whole status line from scratch
# (differential redraws only kick in *within* one attached session), which
# sidesteps a stale/split partial redraw far more reliably than one long
# attach would. Returns 0 iff `pattern` was seen. TERM is pinned to
# xterm-256color: tmux.conf grants RGB only to that terminal type, and a CI
# container with no TERM at all may refuse to attach.
render_status_until() {
    local log="$1" pattern="$2" timeout_s="${3:-8}" target="${4:-}"
    local target_args=()
    [[ -n "$target" ]] && target_args=(-t "$target")
    : >"$log"
    local elapsed=0 step=2
    while ((elapsed < timeout_s)); do
        TERM=xterm-256color timeout "$step" script -q -e -a \
            -c "tmux -L $TMUX_TEST_SOCKET attach-session -r ${target_args[*]}" \
            "$log" </dev/null >/dev/null 2>&1 || true
        if grep -aqP -- "$pattern" "$log" 2>/dev/null; then
            tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
            return 0
        fi
        elapsed=$((elapsed + step))
    done
    tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    return 1
}

@test "status-right's git branch lookup does not execute shell code from a crafted directory name" {
    local workdir="$BATS_TEST_TMPDIR/work-git"
    mkdir -p "$workdir"
    local maldir="$workdir/x;touch $workdir/pwned-git;y"
    mkdir -p "$maldir"
    # A unique branch name is the positive marker: it can only come from
    # git-branch.sh actually running `git -C <path> rev-parse`, unlike a raw
    # directory-name fragment, which also leaks into the log via the pane's
    # own shell prompt (PS1 shows the cwd) regardless of whether any
    # status-bar script ever ran.
    git -C "$maldir" init -q -b vybemux-injection-marker-git
    git -C "$maldir" -c user.email=test@example.com -c user.name=test \
        commit -q --allow-empty -m init

    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s poc -x 80 -y 24 -c "$maldir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1

    render_status_until "$BATS_TEST_TMPDIR/term-git.log" "vybemux-injection-marker-git"

    [ ! -e "$workdir/pwned-git" ]
}

@test "status-right's shorten-path.sh call does not execute shell code from a crafted directory name" {
    local workdir="$BATS_TEST_TMPDIR/work-path"
    mkdir -p "$workdir"
    local maldir="$workdir/a'\$(touch $workdir/pwned-path)'b"
    mkdir -p "$maldir"

    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s poc -x 80 -y 24 -c "$maldir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1

    # Positive marker: the *shortened* form of the path (single-char
    # components before the final "pwned-path" segment), which only
    # shorten-path.sh produces. The raw "pwned-path" text alone is a false
    # positive -- it also leaks via the pane's own shell prompt (PS1 shows
    # the unshortened cwd) even when no status-bar script ever runs.
    render_status_until "$BATS_TEST_TMPDIR/term-path.log" '/a(/[^/])+/pwned-path'

    [ ! -e "$workdir/pwned-path" ]
}

# Not a reproduction of the original single-quote-breakout report: tmux.conf
# never wrapped values in double quotes, so this couldn't have broken out of
# anything there. It guards against a *future* quoting scheme built on
# "...", so the id-based design doesn't quietly regress into a new variant
# of the same bug class if someone reintroduces manual quoting later.
@test "status-right's scripts do not execute shell code from a double-quote breakout attempt" {
    local workdir="$BATS_TEST_TMPDIR/work-dquote"
    mkdir -p "$workdir"
    local maldir="$workdir/a\";touch $workdir/pwned-dquote;echo \"b"
    mkdir -p "$maldir"

    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s poc -x 80 -y 24 -c "$maldir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1

    # Same reasoning as the shorten-path.sh test above: require the
    # shortened form, not the raw name, as the positive marker.
    render_status_until "$BATS_TEST_TMPDIR/term-dquote.log" '/a(/[^/])+/pwned-dquote'

    [ ! -e "$workdir/pwned-dquote" ]
}

@test "status-left's session list does not execute shell code from a crafted session name" {
    local workdir="$BATS_TEST_TMPDIR/work-session"
    mkdir -p "$workdir"
    local sessname="x'\$(touch $workdir/pwned-session)'y"

    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s "$sessname" -x 80 -y 24 -c "$workdir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1

    # Positive marker: the session-list badge background immediately
    # followed by the session name, which only sessions.sh emits (this is
    # the only session, so it's both created and attached -- current, not
    # muted). The raw name alone is a false positive -- it also leaks via
    # the window title (tmux's own set-titles-string "#S | #W") even when
    # sessions.sh never runs at all.
    render_status_until "$BATS_TEST_TMPDIR/term-session.log" \
        '48;2;122;162;247m(\x1b\[[0-9;?]*[A-Za-z])* x'"'"'\$\(touch'

    [ ! -e "$workdir/pwned-session" ]
}

@test "status bar renders the badge, branch, and shortened path for a real session and repo" {
    local workdir="$BATS_TEST_TMPDIR/normal"
    # A space in the directory name doubles as coverage for the issue's
    # "space" character case: the id-based design has no manual quoting
    # for it to break out of, but this proves it still renders correctly.
    mkdir -p "$workdir/nested proj/myproject"
    git -C "$workdir/nested proj/myproject" init -q -b vybemux-regression-branch
    git -C "$workdir/nested proj/myproject" -c user.email=test@example.com \
        -c user.name=test commit -q --allow-empty -m init

    # A second, unattached session makes the badge-adjacency check below
    # meaningful: it proves the badge sits on the *current* session, not
    # merely that a session name appears anywhere in the output.
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s other -x 140 -y 24 -c "$workdir"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" new-session -d -s current -x 140 -y 24 -c "$workdir/nested proj/myproject"
    HOME="$FIXTURE_HOME" tmux -L "$TMUX_TEST_SOCKET" source-file "$PROJECT_CONFIG"
    tmux -L "$TMUX_TEST_SOCKET" set -g status-interval 1

    local log="$BATS_TEST_TMPDIR/term-normal.log"
    # Badge background (#7aa2f7) immediately precedes "current ", allowing
    # for style codes (e.g. bold) in between but no other session name --
    # this is what would fail again if #{session_id} ever lost its quotes
    # (sh -c reads "$N" as its own positional parameter, so *no* session
    # gets the badge, not just the wrong one).
    render_status_until "$log" '48;2;122;162;247m(\x1b\[[0-9;?]*[A-Za-z])* current ' 8 current

    grep -aq "vybemux-regression-branch" "$log"
    # "myproject" (the final, unshortened path component) rather than the
    # exact "/n/myproject": tmux's differential redraw can split a longer
    # match across separately-timed writes even when it displays correctly.
    grep -aq "myproject" "$log"
}
