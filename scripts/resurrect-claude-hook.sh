#!/bin/bash
# =============================================================================
# resurrect-claude-hook.sh — @resurrect-hook-post-save-layout for vybemux.
#
# For each running process, Claude Code writes <CLAUDE_CONFIG_DIR|~/.claude>/
# sessions/<PID>.json with a "sessionId" and a "tmux" field (format
# "<session>:<window_id>.<pane_id>", for example "0:@13.%52"). This hook runs
# immediately after the tmux-resurrect save (save.sh:246, before the "last" symlink)
# and replaces the command line of every "claude" pane in the save file with
# "claude --resume <sessionId>", so restore.sh (with the @resurrect-processes
# entry "~claude", without an inline strategy) resumes the conversation without
# an interactive picker.
#
# Every detected claude line is ALWAYS normalized to one of two forms:
#   - ":unset "${!ANTHROPIC_@}" ...; [KEY=value ...]claude --resume <sessionId>"
#     when the association succeeds unambiguously. tmux-resurrect replays a
#     restored pane's command via "tmux send-keys" into an ALREADY-RUNNING
#     interactive shell (restore_pane_process in
#     plugins/tmux-resurrect/scripts/process_restore_helpers.sh), which has
#     already sourced the user's normal shell startup files--so any
#     allowlisted variable NOT present in the resolved process's own
#     environment must be actively unset here, or it would leak in from that
#     shell's own global exports (e.g. a provider/model default exported
#     unconditionally in ~/.bashrc) instead of staying absent. The leading
#     "unset ...; " clears the whole allowlisted namespace in the TARGET
#     shell (see CLAUDE_ENV_CLEAR_PREFIX); the "KEY=value " assignments that
#     follow are the resolved process's own ANTHROPIC_*/CLAUDE_CODE_*/
#     CLAUDE_CONFIG_DIR environment (see capture_claude_env_prefix), so a
#     pane started against a non-default provider or model resumes against
#     the same one instead of silently falling back to the default. Together
#     these pin the pane to exactly what those variables were (set, or
#     deliberately absent) at save time--edits to the shell config made
#     afterwards do not retroactively reach an already resumed pane, only the
#     next fresh "claude" invocation.
#   - ":claude --resume"              as the picker fallback in every other case
#     (no jq, no /proc, no PID association, no match, or any unexpected error
#     while processing ONE pane line); no clear-prefix is added here since no
#     process was resolved to pin the pane to--the shell's own default
#     provider/model config is the correct behavior for an unresolved pane.
# This applies regardless of whether Claude Code is present on this host in the
# expected format: resurrect.sh itself has no "set -e" and ignores this hook's
# exit status (helpers.sh execute_hook); otherwise, a failed hook would symlink
# the raw, unprocessed file. Therefore, there is no early "exit 0" for missing
# sessions directories or similar: every pane line is processed robustly and
# independently, falling back to the picker when in doubt rather than aborting
# the entire run (and therefore all other claude panes that may already be
# resolvable).
#
# A save file written *before* this hook was installed still contains raw
# "claude" (no hook has ever processed it) and therefore restores once as a
# fresh start instead of via the picker; the next Continuum autosave (≤15 min)
# overwrites it automatically.
# =============================================================================
set -euo pipefail

RESURRECT_FILE="${1:-}"

# Candidate sessions directories, not just the hook's own
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}: this hook runs with the tmux server's
# environment, not any individual pane's, so a pane started via a wrapper
# that overrides CLAUDE_CONFIG_DIR for an alternate profile (e.g.
# CLAUDE_CONFIG_DIR=~/.claude-minimal) would otherwise never be found and
# would always fall back to the picker. "$HOME"/.claude*/sessions covers
# that without needing to know every profile name in advance; duplicates
# (e.g. the default dir matching both the explicit branch and the glob) are
# harmless--build_session_index just re-scans the same files.
SESSIONS_DIRS=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions")
for _alt_sessions_dir in "$HOME"/.claude*/sessions; do
    [ -d "$_alt_sessions_dir" ] && SESSIONS_DIRS+=("$_alt_sessions_dir")
done
unset _alt_sessions_dir

[ -n "$RESURRECT_FILE" ] && [ -f "$RESURRECT_FILE" ] || exit 0

# Check capabilities instead of assuming a platform: without jq or readable
# /proc (for example, on macOS), no attempt is made to resolve a sessionId;
# every claude line then receives the picker fallback directly.
LOOKUP_OK=1
command -v jq >/dev/null 2>&1 || LOOKUP_OK=0
[ -r "/proc/$$/stat" ] || LOOKUP_OK=0

# Reads the PID-specific start-time field from /proc/<pid>/stat (field 22,
# ticks since boot) in a PID-reuse-safe manner: comm (field 2) can contain
# parentheses and spaces, so parsing starts after the last closing parenthesis
# instead of splitting naively on whitespace.
proc_start_time() {
    local pid="$1" stat_line rest
    stat_line="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
    [ -n "$stat_line" ] || return 1
    rest="${stat_line##*) }"
    awk '{print $20}' <<<"$rest"
}

# Builds an in-memory index ONCE of all verified (live, procStart-checked)
# Claude sessions—one jq call per file instead of four calls per file PER pane.
# Line format: tmux_field<TAB>cwd<TAB>sessionId<TAB>updatedAt<TAB>pid.
build_session_index() {
    local dir f pid line json_proc_start live_proc_start tmux_field cwd session_id updated

    for dir in "${SESSIONS_DIRS[@]}"; do
        [ -d "$dir" ] || continue

        for f in "$dir"/*.json; do
            [ -f "$f" ] || continue
            pid="$(basename "$f")"
            pid="${pid%%.*}"
            [[ "$pid" =~ ^[0-9]+$ ]] || continue

            line="$(jq -r '[(.procStart // ""),(.tmux // ""),(.cwd // ""),(.sessionId // ""),(.updatedAt // .startedAt // 0)] | @tsv' "$f" 2>/dev/null)" || continue
            [ -n "$line" ] || continue

            json_proc_start="$(cut -d $'\t' -f1 <<<"$line")"
            [ -n "$json_proc_start" ] || continue
            live_proc_start="$(proc_start_time "$pid")" || continue
            [ -n "$live_proc_start" ] || continue
            [ "$live_proc_start" = "$json_proc_start" ] || continue

            session_id="$(cut -d $'\t' -f4 <<<"$line")"
            [ -n "$session_id" ] || continue

            tmux_field="$(cut -d $'\t' -f2 <<<"$line")"
            cwd="$(cut -d $'\t' -f3 <<<"$line")"
            updated="$(cut -d $'\t' -f5 <<<"$line")"
            [[ "$updated" =~ ^[0-9]+$ ]] || updated=0

            printf '%s\t%s\t%s\t%s\t%s\n' "$tmux_field" "$cwd" "$session_id" "$updated" "$pid"
        done
    done
}

SESSION_INDEX=""
if [ "$LOOKUP_OK" = "1" ]; then
    SESSION_INDEX="$(build_session_index)"
fi

# Searches the index for the entry whose tmux field ends in
# "<window_id>.<pane_id>" and whose cwd matches the pane directory (PID
# liveness and procStart were already verified while building the index). Of
# multiple matches, the most recently updated one wins. Prints
# "sessionId<TAB>pid" (pid is the source of the winning match, used by the
# caller to look up that process's environment).
resolve_session_id() {
    local window_id="$1" pane_id="$2" pane_dir="$3"
    local suffix="${window_id}.${pane_id}"
    local best_id="" best_pid="" best_updated=-1
    local line tmux_field cwd session_id updated pid

    [ -n "$SESSION_INDEX" ] || return 0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        tmux_field="$(cut -d $'\t' -f1 <<<"$line")"
        [[ "$tmux_field" == *"$suffix" ]] || continue

        cwd="$(cut -d $'\t' -f2 <<<"$line")"
        [ -n "$pane_dir" ] && [ "$cwd" != "$pane_dir" ] && continue

        session_id="$(cut -d $'\t' -f3 <<<"$line")"
        updated="$(cut -d $'\t' -f4 <<<"$line")"
        pid="$(cut -d $'\t' -f5 <<<"$line")"
        if [ "$updated" -ge "$best_updated" ]; then
            best_updated="$updated"
            best_id="$session_id"
            best_pid="$pid"
        fi
    done <<<"$SESSION_INDEX"

    printf '%s\t%s' "$best_id" "$best_pid"
}

# Reads the allowlisted provider/model config variables out of the resolved
# claude process's own environment and returns them as a shell-quoted
# "KEY=value " prefix, ready to be placed in front of "claude --resume <id>"
# in the restored command line.
#
# The allowlist is deliberately NOT "every ANTHROPIC_*/CLAUDE_CODE_*-prefixed
# var" -- CLAUDE_CODE_* in particular is Claude Code's own internal runtime
# namespace, not just provider config: a real running process also carries
# vars like CLAUDE_CODE_SESSION_ID and CLAUDE_CODE_MESSAGING_TOKEN (a live
# inter-process auth secret), which must never be replayed into a restored
# pane's command line. ANTHROPIC_* is not matched by prefix either: it also
# holds credentials (ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN,
# ANTHROPIC_CUSTOM_HEADERS, ...), so only the explicit non-secret names in
# classify_claude_env_entry are replayed with a value. CLAUDE_CODE_* is
# matched only by exact, individually-named flags known to affect
# provider/model behavior, plus CLAUDE_CONFIG_DIR (selects an alternate
# profile directory, e.g. ~/.claude-minimal). Extend those names deliberately,
# one at a time -- never widen them to a prefix match.
#
# Any other non-empty ANTHROPIC_* value is never written to the save file or
# the restore command line; it goes to a private file that the restore
# command sources (see write_claude_secret_env_file).
#
# The value is always included once the name matches, even when empty: some
# of the project's own shell wrapper functions deliberately export e.g.
# ANTHROPIC_API_KEY="" to override a global default, and dropping empty
# values here would silently restore the wrong provider's credentials.
# Restoring a pane therefore pins it to whatever allowlisted values that
# process had at save time, including its shell startup file's global
# exports; provider/model changes made after saving do not retroactively
# apply to a resumed pane.
# Prepended, verbatim, in front of capture_claude_env_prefix's output on
# every successfully resolved pane (see process_claude_pane_line): unsets the
# exact same name set the allowlist above matches, in the TARGET shell, before
# that shell applies the "KEY=value " assignments that follow. Kept in sync by
# hand with the allowlist's ANTHROPIC_*/CLAUDE_CONFIG_DIR/CLAUDE_CODE_* names
# above--if that case statement grows another named CLAUDE_CODE_* flag, add it
# here too.
#
# 'unset "${!ANTHROPIC_@}" ...' is written as a single-quoted literal: the
# "${!ANTHROPIC_@}" indirect-prefix expansion (bash-only, same word-splitting
# as "$@") is deliberately left UNEXPANDED here and only evaluated later by
# the restored pane's own shell at restore time, against ITS OWN environment
# at that moment--not this script's. That is what makes it clear exactly the
# variables the target shell actually has, however many there are, rather
# than a fixed guess made here at save time. "unset" on a name that shell
# doesn't have is a silent no-op (exit 0, no output), so this is always safe
# to run, including when the resolved process had none of these vars set.
# shellcheck disable=SC2016 # deliberately unexpanded here; see comment above
CLAUDE_ENV_CLEAR_PREFIX='unset "${!ANTHROPIC_@}" CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK; '

# Classifies one process environment entry: "inline" (safe to replay in the
# restore command), "secret" (value that must stay out of the command line
# and the save file, see write_claude_secret_env_file) or "skip" (not ours).
#
# ANTHROPIC_* is NOT allowlisted by prefix: only an explicit list of
# non-secret names is replayed with its value. An empty value is always
# replayed (deliberate override, e.g. ANTHROPIC_API_KEY=""), as is nothing
# else. A base URL carrying userinfo ("://user:pass@") counts as a secret.
#
# Any otherwise inline value containing "!" is routed to the env file too:
# tmux-resurrect types the restore line into an interactive shell, where
# history expansion is active. printf '%q' output is not safe against it
# (bash's history quote tracking misreads e.g. a "\"" followed by $'...!...'),
# and any "!" it deems unquoted makes the shell reject the WHOLE line (the
# clear-prefix's "${!ANTHROPIC_@}" then fails with "event not found"), so the
# pane is not restored at all. A sourced file is not history-expanded.
classify_claude_env_entry() {
    local key="$1" value="$2" class

    case "$key" in
    ANTHROPIC_[A-Z0-9_]*)
        if [ -z "$value" ]; then
            class=inline
        else
            case "$key" in
            ANTHROPIC_MODEL | ANTHROPIC_SMALL_FAST_MODEL | ANTHROPIC_BASE_URL | \
                ANTHROPIC_DEFAULT_*_MODEL)
                if [[ "$value" =~ ://[^/]*@ ]]; then
                    class=secret
                else
                    class=inline
                fi
                ;;
            *) class=secret ;;
            esac
        fi
        ;;
    CLAUDE_CONFIG_DIR | \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC | \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW | \
        CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK)
        class=inline
        ;;
    *) class=skip ;;
    esac

    if [ "$class" = inline ] && [[ "$value" == *'!'* ]]; then
        class=secret
    fi
    echo "$class"
}

# Writes the resolved process's secret ANTHROPIC_* values (API key, auth
# token, custom headers, URLs with userinfo, ...) and any allowlisted value
# containing "!" (see classify_claude_env_entry) to a private per-session
# file next to the save file, as "export KEY=value" lines, and prints the
# file's path. The restore command only sources that path, so the secret
# never appears in the save file, the typed command line, shell history or
# pane contents. Prints nothing when the process had no secret values; a
# file that is no longer needed is left to the pruning at the end of the
# script, which keeps files older save files still reference.
write_claude_secret_env_file() {
    local pid="$1" session_id="$2" entry key value body="" file tmp
    # /proc/<pid>/environ is raw bytes, not text in the hook's locale: under a
    # UTF-8 locale, "read -d ''" treats a value ending in an incomplete
    # multibyte sequence (e.g. a trailing \357) as continuing into the NUL
    # delimiter and silently drops the NEXT variable, which the clear-prefix
    # then removes from the restored pane as well. Byte semantics (scoped to
    # this function) keep every entry intact; printf '%q' then escapes all
    # non-ASCII bytes, so the output is the same in every locale.
    local LC_ALL=C

    file="${SECRET_ENV_DIR}/${session_id}.env"

    if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        while IFS= read -r -d '' entry; do
            key="${entry%%=*}"
            value="${entry#*=}"
            [ "$(classify_claude_env_entry "$key" "$value")" = secret ] || continue
            body+="export ${key}=$(printf '%q' "$value")"$'\n'
        done <"/proc/$pid/environ"
    fi

    [ -n "$body" ] || return 0

    (
        umask 077
        mkdir -p "$SECRET_ENV_DIR"
        chmod 700 "$SECRET_ENV_DIR"
        tmp="$(mktemp "${SECRET_ENV_DIR}/.env.XXXXXX")"
        printf '%s' "$body" >"$tmp"
        mv "$tmp" "$file"
    )
    printf '%s' "$file"
}

capture_claude_env_prefix() {
    local pid="$1"
    local entry key value entries=() sorted prefix=""
    # Byte semantics for reading /proc/<pid>/environ; see
    # write_claude_secret_env_file.
    local LC_ALL=C

    [ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 0

    while IFS= read -r -d '' entry; do
        key="${entry%%=*}"
        value="${entry#*=}"
        if [ "$(classify_claude_env_entry "$key" "$value")" = inline ]; then
            entries+=("${key}=$(printf '%q' "$value")")
        fi
    done <"/proc/$pid/environ"

    [ "${#entries[@]}" -gt 0 ] || return 0

    # Sorted for deterministic, reviewable output; the sort's own newlines
    # never reach the result, since a literal newline in the prefix would
    # corrupt the resurrect save file's line-based (one-pane-per-line) format.
    sorted="$(printf '%s\n' "${entries[@]}" | sort)"
    while IFS= read -r entry; do
        prefix+="${entry} "
    done <<<"$sorted"

    printf '%s' "$prefix"
}

# Determines the new full_command field for one "pane" line.
# Runs in its own subshell (called via "$(...)"): if anything unexpected
# fails here, only this invocation aborts (set -euo pipefail applies only
# inside the subshell); the caller catches it with "|| " and uses the picker
# fallback—the overall run continues.
process_claude_pane_line() {
    local raw_line="$1"
    local session_name window_number pane_index dir
    local window_id="" pane_id="" match_line pane_dir
    local resolved="" session_id="" pid="" env_prefix="" secret_file=""

    session_name="$(cut -d $'\t' -f2 <<<"$raw_line")"
    window_number="$(cut -d $'\t' -f3 <<<"$raw_line")"
    pane_index="$(cut -d $'\t' -f6 <<<"$raw_line")"
    dir="$(cut -d $'\t' -f8 <<<"$raw_line")"

    match_line="$(awk -F'\t' -v sn="$session_name" -v wn="$window_number" -v pi="$pane_index" \
        '$1 == sn && $2 == wn && $3 == pi { print; exit }' <<<"$PANES_SNAPSHOT")"
    if [ -n "$match_line" ]; then
        window_id="$(cut -d $'\t' -f4 <<<"$match_line")"
        pane_id="$(cut -d $'\t' -f5 <<<"$match_line")"
    fi

    if [ "$LOOKUP_OK" = "1" ] && [ -n "$window_id" ] && [ -n "$pane_id" ]; then
        pane_dir="${dir#:}"
        pane_dir="${pane_dir//\\ / }"
        resolved="$(resolve_session_id "$window_id" "$pane_id" "$pane_dir")"
        session_id="$(cut -d $'\t' -f1 <<<"$resolved")"
        pid="$(cut -d $'\t' -f2 <<<"$resolved")"
    fi

    if [[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        # A failure here (unreadable /proc/<pid>/environ: race, permissions)
        # must not cost us the already-resolved session_id -- caught locally
        # instead of left to the surrounding "set -e", which would otherwise
        # abort this whole subshell and fall back to the bare picker.
        env_prefix="$(capture_claude_env_prefix "$pid" 2>/dev/null)" || env_prefix=""
        secret_file="$(write_claude_secret_env_file "$pid" "$session_id" 2>/dev/null)" || secret_file=""
        if [ -n "$secret_file" ]; then
            # Quoted byte-wise like the values (and like the pruning below
            # expects): a non-ASCII resurrect directory, e.g. under a $HOME
            # with an umlaut, then yields the same pure-ASCII line whatever
            # the tmux server's locale is.
            printf ':%s( . %s; %sclaude --resume %s )' "$CLAUDE_ENV_CLEAR_PREFIX" "$(
                LC_ALL=C
                printf '%q' "$secret_file"
            )" "$env_prefix" "$session_id"
        else
            printf ':%s%sclaude --resume %s' "$CLAUDE_ENV_CLEAR_PREFIX" "$env_prefix" "$session_id"
        fi
    else
        printf ':claude --resume'
    fi
}

RESURRECT_DIR="$(dirname "$RESURRECT_FILE")"
SECRET_ENV_DIR="${RESURRECT_DIR}/claude-env"
TMPFILE="$(mktemp "${RESURRECT_DIR}/.resurrect-claude-hook.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

# Takes a single snapshot of all panes instead of a separate "tmux list-panes"
# call per claude pane: fewer subprocesses, and all lines are resolved against
# the same consistent state rather than N slightly offset states.
snapshot_format="#{session_name}"
snapshot_format+=$'\t'
snapshot_format+="#{window_index}"
snapshot_format+=$'\t'
snapshot_format+="#{pane_index}"
snapshot_format+=$'\t'
snapshot_format+="#{window_id}"
snapshot_format+=$'\t'
snapshot_format+="#{pane_id}"
# "|| PANES_SNAPSHOT=""" instead of an unguarded assignment: if "tmux"
# fails (no server, or—unlike in every normal tmux session—no "tmux" on PATH),
# an unguarded assignment under set -e would immediately terminate the script
# with tmux's exit status (for example, 127) before a single line is processed;
# the save file would remain completely unchanged instead of normalized. An
# empty snapshot leaves window_id/pane_id empty for every claude pane, which
# already makes resolve_session_id fall back to the picker—the guarantee
# documented above ("one of two forms") therefore applies in this case too.
PANES_SNAPSHOT="$(tmux list-panes -a -F "$snapshot_format" 2>/dev/null)" || PANES_SNAPSHOT=""

while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    if [[ "$raw_line" == pane$'\t'* ]]; then
        # Inspect only the final field (full_command), not the entire line—
        # otherwise paths or titles such as "~/projects/claude-x" would match.
        # Anchor at the end rather than using "cut -f11": this remains robust
        # if resurrect (for example, with an empty pane_title) writes a
        # different field count, and operates on the same field as the prefix
        # trim below.
        full_command="${raw_line##*$'\t'}"
        cmd_body="${full_command#:}"
        first_token="${cmd_body%% *}"
        cmd_name="${first_token##*/}"
        # Exact program name ("claude"), not a substring match; otherwise,
        # for example, "claude-code-proxy" (another tool) would incorrectly
        # be treated as a Claude pane.
        if [ "$cmd_name" = "claude" ]; then
            new_full_command="$(process_claude_pane_line "$raw_line" 2>/dev/null)" || new_full_command=""
            [ -n "$new_full_command" ] || new_full_command=":claude --resume"

            # Replace only the final field; preserve all others (including any
            # empty fields) unmodified from the original.
            prefix="${raw_line%$'\t'*}"
            raw_line="${prefix}"$'\t'"${new_full_command}"
        fi
    fi
    printf '%s\n' "$raw_line"
done <"$RESURRECT_FILE" >"$TMPFILE"

mv "$TMPFILE" "$RESURRECT_FILE"

# An env file is only stale once no save file in the directory references it:
# tmux-resurrect keeps older tmux_resurrect_*.txt files (and "last" may be
# pointed at one), and pruning against the current save alone would leave
# those with a dangling env path. References are matched in the byte-wise
# quoting process_claude_pane_line writes, and also in the current locale's
# quoting that save files from before that change may still contain.
if [ -d "$SECRET_ENV_DIR" ]; then
    rm -f "$SECRET_ENV_DIR"/.env.*
    for stale_file in "$SECRET_ENV_DIR"/*.env; do
        [ -e "$stale_file" ] || continue
        quoted_stale="$(
            LC_ALL=C
            printf '%q' "$stale_file"
        )"
        quoted_stale_locale="$(printf '%q' "$stale_file")"
        grep -qF -e "$quoted_stale" -e "$quoted_stale_locale" \
            "$RESURRECT_FILE" "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null ||
            rm -f "$stale_file"
    done
fi
