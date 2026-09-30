#!/usr/bin/env bats
# =============================================================================
# Property-based tests for scripts/resurrect-claude-hook.sh.
#
# resurrect_claude_hook.bats pins individual, hand-picked examples; this file
# instead checks invariants that must hold for EVERY input, against many
# generated hostile values (shell metacharacters, command substitutions,
# history-expansion triggers, control characters, newlines, tabs, invalid
# UTF-8, multibyte characters). The hook generates shell code that a restored
# pane later executes, so the invariants are:
#
#   - executing the restored line (through the same extraction tmux-resurrect
#     performs, in an interactive bash so history expansion is active)
#     reproduces the saved process's allowlisted environment byte for byte,
#     clears leaked defaults, and executes nothing else;
#   - the save file keeps its one-pane-per-line, tab-separated structure;
#   - secret values and non-allowlisted variables never reach the save file;
#   - a session id outside [A-Za-z0-9_-]+ always falls back to the picker.
#
# Every iteration picks the locale of the hook and of the pane shell
# independently (C and, if available, a UTF-8 locale), because the tmux
# server that runs the hook and the restored pane's shell need not share one,
# and printf '%q' output depends on it.
#
# Reproducible: the generator draws only from $RANDOM in the current shell
# (never inside "$(...)", which would reseed it and strip trailing newlines),
# seeded from FUZZ_SEED. CI runs a fixed default seed; a deeper local run:
#   FUZZ_SEED=$RANDOM FUZZ_ITERATIONS=500 test/bats-core/bin/bats \
#       test/resurrect_claude_hook_properties.bats
# A failure prints the seed and iteration; rerunning with that FUZZ_SEED on
# the same bash version replays the same inputs.
#
# Helpers are copied from resurrect_claude_hook.bats on purpose: every test
# file keeps its own stubs rather than sharing a helper.
# =============================================================================

SCRIPT="$BATS_TEST_DIRNAME/../scripts/resurrect-claude-hook.sh"
RESURRECT_SCRIPTS="$BATS_TEST_DIRNAME/../plugins/tmux-resurrect/scripts"
BASH_BIN="$(command -v bash)"

FUZZ_SEED="${FUZZ_SEED:-1337}"
FUZZ_ITERATIONS="${FUZZ_ITERATIONS:-25}"

# Duplicated (not sourced) from CLAUDE_ENV_CLEAR_PREFIX in the script under
# test, as in resurrect_claude_hook.bats.
CLEAR_PREFIX='unset "${!ANTHROPIC_@}" CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK; '

# Variables the hook replays inline (or, for a URL with userinfo, via the
# private env file).
INLINE_KEYS=(
    ANTHROPIC_MODEL
    ANTHROPIC_SMALL_FAST_MODEL
    ANTHROPIC_BASE_URL
    ANTHROPIC_DEFAULT_OPUS_MODEL
    CLAUDE_CONFIG_DIR
    CLAUDE_CODE_AUTO_COMPACT_WINDOW
    CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK
)
# Variables whose non-empty value must only ever reach the private env file.
SECRET_KEYS=(
    ANTHROPIC_API_KEY
    ANTHROPIC_AUTH_TOKEN
    ANTHROPIC_CUSTOM_HEADERS
)

# Hostile building blocks. Every PWNED entry would create a file named PWNED
# in the working directory if any stage ever executed a value.
FUZZ_CORPUS=(
    "'" '"' '\' '$' '`' '!' '!!' '!$' '!-1' '^x^y' '#' ';' '&' '|' '<' '>'
    '(' ')' '{' '}' '[' ']' '*' '?' '~' '=' '%' ' ' '  '
    '$(touch PWNED)' '`touch PWNED`' '; touch PWNED' '&& touch PWNED'
    '| touch PWNED' "'; touch PWNED; '" '"; touch PWNED; "' '$(<PWNED)'
    '${IFS}' '$HOME' '${!ANTHROPIC_@}' '\n' '-n' '-e' '--' 'claude --resume x'
    '#[fg=red]' '#(touch PWNED)' '://user:pass@' 'http://u:p@h/'
    $'\n' $'\t' $'\r' $'\e[31m' $'\x7f' $'\x01' $'\x1b]52;c;eA==\a'
    'é' '€' '𝄞' $'\xff' $'\xc3' $'\xe2\x82'
)

# Characters a valid session id is built from, spelled out so the expected
# outcome is known by construction rather than by re-running the hook's own
# regex (whose ranges are locale-dependent).
ID_CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
# Each entry contains at least one character outside ID_CHARS.
ID_HOSTILE=(
    ' ' ';' '$(touch PWNED)' '`touch PWNED`' "'" '"' '\' '!' '|' '&' '.' '/'
    ':' '@' '+' '=' '*' $'\n' $'\t' $'\r' $'\x01' 'é' 'Ä' 'ı' 'ǅ' '０' $'\xff'
)

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$STUB_BIN" "$WORK_DIR"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
    mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
    export PATH="$STUB_BIN:$PATH"
    make_tmux_stub $'sess\t0\t0\t@1\t%1'
    install_claude_dump_stub

    FUZZ_LOCALES=(C)
    local utf8_locale
    utf8_locale="$(locale -a 2>/dev/null | grep -ixE 'C\.utf-?8|en_US\.utf-?8' | head -n 1)" || true
    [ -n "$utf8_locale" ] && FUZZ_LOCALES+=("$utf8_locale")
}

teardown() {
    if [ -f "$BATS_TEST_TMPDIR/claude.pids" ]; then
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null || true
        done <"$BATS_TEST_TMPDIR/claude.pids"
    fi
}

# =============================================================================
# Fixture helpers (copied from resurrect_claude_hook.bats)
# =============================================================================

claude_env_allowlist_names() {
    compgen -v | grep -E '^(ANTHROPIC_[A-Z0-9_]*|CLAUDE_CONFIG_DIR|CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC|CLAUDE_CODE_AUTO_COMPACT_WINDOW|CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK)$' || true
}

claude_env_unset_args() {
    local v
    while IFS= read -r v; do
        [ -n "$v" ] && printf -- '-u\n%s\n' "$v"
    done < <(claude_env_allowlist_names)
}

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
    local pid="$1" session_id="$2" tmux_field="$3" cwd="$4" proc_start="$5"
    jq -n \
        --arg sessionId "$session_id" \
        --arg tmux "$tmux_field" \
        --arg cwd "$cwd" \
        --arg procStart "$proc_start" \
        '{sessionId: $sessionId, tmux: $tmux, cwd: $cwd, procStart: $procStart, updatedAt: 100}' \
        >"$CLAUDE_CONFIG_DIR/sessions/${pid}.json"
}

# Unlike the example-based file, the claude stub dumps its environment and
# argv NUL-separated, so values containing newlines stay unambiguous.
install_claude_dump_stub() {
    cat >"$STUB_BIN/claude" <<'EOF'
#!/bin/bash
env -0 >"$CLAUDE_ENV_DUMP"
printf '%s\0' "$@" >"$CLAUDE_ARGV_DUMP"
EOF
    chmod +x "$STUB_BIN/claude"
}

# =============================================================================
# Generators (set globals; never call them inside "$(...)")
# =============================================================================

# Appends one random byte in 0x01..0xff to FUZZ_VALUE.
fuzz_append_byte() {
    local oct byte
    printf -v oct '%03o' $((RANDOM % 255 + 1))
    printf -v byte "\\$oct"
    FUZZ_VALUE+="$byte"
}

# Sets FUZZ_VALUE to 0..6 tokens drawn from the corpus, random bytes and
# alphanumeric runs.
fuzz_gen_value() {
    local n=$((RANDOM % 7)) kind
    FUZZ_VALUE=""
    while ((n-- > 0)); do
        kind=$((RANDOM % 4))
        if ((kind < 2)); then
            FUZZ_VALUE+="${FUZZ_CORPUS[RANDOM % ${#FUZZ_CORPUS[@]}]}"
        elif ((kind == 2)); then
            fuzz_append_byte
        else
            FUZZ_VALUE+="v$RANDOM"
        fi
    done
}

# Sets FUZZ_ID and FUZZ_ID_VALID: either a string of ID_CHARS only (valid),
# the empty string (invalid) or a valid string with one ID_HOSTILE entry
# inserted at a random position (invalid).
fuzz_gen_session_id() {
    local len=$((RANDOM % 12 + 1)) pos hostile
    FUZZ_ID=""
    while ((len-- > 0)); do
        FUZZ_ID+="${ID_CHARS:RANDOM % ${#ID_CHARS}:1}"
    done
    case $((RANDOM % 5)) in
    0 | 1)
        FUZZ_ID_VALID=1
        ;;
    2)
        FUZZ_ID=""
        FUZZ_ID_VALID=0
        ;;
    *)
        pos=$((RANDOM % (${#FUZZ_ID} + 1)))
        hostile="${ID_HOSTILE[RANDOM % ${#ID_HOSTILE[@]}]}"
        FUZZ_ID="${FUZZ_ID:0:pos}${hostile}${FUZZ_ID:pos}"
        FUZZ_ID_VALID=0
        ;;
    esac
}

fuzz_pick_locale() {
    FUZZ_LOCALE="${FUZZ_LOCALES[RANDOM % ${#FUZZ_LOCALES[@]}]}"
}

# =============================================================================
# Pipeline stages
# =============================================================================

write_resurrect_file() {
    local file="$1" full_command="$2" dir="$3"
    local IFS=$'\t'
    local fields=(pane sess 0 0 ":0" 0 title "$dir" 1 bash ":$full_command")
    printf '%s\n' "${fields[*]}" >"$file"
}

run_hook_in_locale() {
    local locale="$1" file="$2"
    (cd "$WORK_DIR" && LC_ALL="$locale" "$BASH_BIN" "$SCRIPT" "$file")
}

# Extracts the command tmux-resurrect would type into the restored pane.
# Hand copy of the awk/read -r pipeline in restore.sh
# (restore_all_pane_processes); remove_first_char is the plugin's own.
restore_command_of() {
    local file="$1"
    CURRENT_DIR="$RESURRECT_SCRIPTS" bash -c '
        source "$CURRENT_DIR/variables.sh"
        source "$CURRENT_DIR/helpers.sh"
        awk '\''BEGIN { FS="\t"; OFS="\t" } /^pane/ && $11 !~ "^:$" { print $2, $3, $6, $8, $11; }'\'' "$1" |
            while IFS=$d read -r session_name window_number pane_index dir pane_full_command; do
                remove_first_char "$pane_full_command"
            done
    ' _ "$file"
}

# Types the command into an interactive bash (history expansion active, as in
# a real pane that tmux-resurrect drives via send-keys) that already carries
# leaked defaults for allowlisted names, as if exported from ~/.bashrc.
run_in_pane_shell() {
    local locale="$1" cmd="$2" unset_args=()
    mapfile -t unset_args < <(claude_env_unset_args)
    (cd "$WORK_DIR" && env "${unset_args[@]}" \
        LC_ALL="$locale" \
        HISTFILE=/dev/null \
        CLAUDE_ENV_DUMP="$BATS_TEST_TMPDIR/env.dump" \
        CLAUDE_ARGV_DUMP="$BATS_TEST_TMPDIR/argv.dump" \
        ANTHROPIC_DEFAULT_SONNET_MODEL=leaked-model \
        ANTHROPIC_API_KEY=leaked-key \
        CLAUDE_CONFIG_DIR=/leaked \
        "$BASH_BIN" --norc --noprofile -i <<<"$cmd" >"$BATS_TEST_TMPDIR/pane.log" 2>&1) || true
}

# Loads the allowlist-namespace entries of the dumped environment into the
# associative array PANE_ENV.
load_pane_env() {
    local entry key
    PANE_ENV=()
    while IFS= read -r -d '' entry; do
        key="${entry%%=*}"
        [[ "$key" =~ ^(ANTHROPIC_.*|CLAUDE_CONFIG_DIR|CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC|CLAUDE_CODE_AUTO_COMPACT_WINDOW|CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK)$ ]] || continue
        PANE_ENV["$key"]="${entry#*=}"
    done <"$BATS_TEST_TMPDIR/env.dump"
}

assert_nothing_executed() {
    [ -z "$(find "$BATS_TEST_TMPDIR" -name PWNED -print -quit)" ]
}

# Prints the reproduction header plus each "label value" pair, values quoted
# with %q so control characters and invalid bytes stay visible.
fuzz_report() {
    local i="$1"
    shift
    echo "property violated: FUZZ_SEED=$FUZZ_SEED iteration=$i (bash $BASH_VERSION)"
    while (($# >= 2)); do
        printf '  %s: %q\n' "$1" "$2"
        shift 2
    done
}

# =============================================================================
# Properties
# =============================================================================

@test "generator: the same seed yields the same values" {
    local first=() second=() i
    RANDOM="$FUZZ_SEED"
    for i in $(seq 50); do
        fuzz_gen_value
        first+=("$FUZZ_VALUE")
    done
    RANDOM="$FUZZ_SEED"
    for i in $(seq 50); do
        fuzz_gen_value
        second+=("$FUZZ_VALUE")
    done
    [ "${#first[@]}" -eq 50 ]
    for i in "${!first[@]}"; do
        [ "${first[i]}" = "${second[i]}" ]
    done
}

@test "property: a restored pane gets exactly the saved allowlisted environment and executes nothing else" {
    local i key pid proc_start iter_dir file hook_locale pane_locale cmd
    local original_line rewritten_line field_count save_prefix
    local spawn_args=() secret_markers=() leak_marker
    local -A expected=()
    local -A PANE_ENV=()

    if [ ! -f "$RESURRECT_SCRIPTS/helpers.sh" ]; then
        skip "tmux-resurrect submodule is not checked out"
    fi

    RANDOM="$FUZZ_SEED"
    for ((i = 1; i <= FUZZ_ITERATIONS; i++)); do
        expected=()
        spawn_args=()
        secret_markers=()

        for key in "${INLINE_KEYS[@]}"; do
            ((RANDOM % 2)) || continue
            fuzz_gen_value
            expected["$key"]="$FUZZ_VALUE"
        done
        for key in "${SECRET_KEYS[@]}"; do
            ((RANDOM % 2)) || continue
            if ((RANDOM % 5 == 0)); then
                expected["$key"]=""
            else
                fuzz_gen_value
                expected["$key"]="SEKRIT${i}x${key}${FUZZ_VALUE}"
                secret_markers+=("SEKRIT${i}x${key}")
            fi
        done
        for key in "${!expected[@]}"; do
            spawn_args+=("${key}=${expected[$key]}")
        done
        leak_marker="LEAKMARK${i}x"
        spawn_args+=(
            "CLAUDE_CODE_SESSION_ID=${leak_marker}sid"
            "CLAUDE_CODE_MESSAGING_TOKEN=${leak_marker}tok"
            "UNRELATED_VAR=${leak_marker}other"
        )

        # The save file's directory is fuzzed too: the env file's quoted path
        # is part of the typed line. Only a trailing newline is excluded: the
        # hook's "$(dirname ...)" strips it, and a user-configured
        # @resurrect-dir ending in a newline is not a realistic input.
        fuzz_gen_value
        iter_dir="$BATS_TEST_TMPDIR/iteration${i}_${FUZZ_VALUE//\//_}"
        [[ "$iter_dir" != *$'\n' ]] || iter_dir+="_"
        mkdir -p "$iter_dir"
        file="$iter_dir/resurrect.txt"
        fuzz_pick_locale
        hook_locale="$FUZZ_LOCALE"
        fuzz_pick_locale
        pane_locale="$FUZZ_LOCALE"

        rm -f "$CLAUDE_CONFIG_DIR/sessions/"*.json "$BATS_TEST_TMPDIR/env.dump" "$BATS_TEST_TMPDIR/argv.dump"
        pid="$(spawn_fake_claude_pid_with_env "${spawn_args[@]}")"
        proc_start="$(proc_start_time_of "$pid")"
        write_session_json "$pid" "session-$i" "sess:@1.%1" "/home/testuser/project" "$proc_start"
        write_resurrect_file "$file" "claude" ":/home/testuser/project"
        original_line="$(cat "$file")"

        run_hook_in_locale "$hook_locale" "$file" || {
            fuzz_report "$i" "hook exited non-zero, locale" "$hook_locale" spawn_env "${spawn_args[*]}" \
                save_file "$file"
            return 1
        }
        kill "$pid" 2>/dev/null || true

        rewritten_line="$(cat "$file")"
        field_count="$(awk -F'\t' '{ print NF }' "$file")"
        save_prefix="${original_line%$'\t'*}"
        [ "$(wc -l <"$file")" -eq 1 ] && [ "$field_count" = 11 ] &&
            [ "${rewritten_line%$'\t'*}" = "$save_prefix" ] || {
            fuzz_report "$i" "save file structure broken" "$rewritten_line" hook_locale "$hook_locale"
            return 1
        }
        for key in "${secret_markers[@]}" "$leak_marker"; do
            ! grep -qF -- "$key" "$file" || {
                fuzz_report "$i" "value leaked into the save file" "$key" line "$rewritten_line"
                return 1
            }
        done
        [[ "$rewritten_line" == *"claude --resume session-$i"* ]] || {
            fuzz_report "$i" "pane was not resolved" "$rewritten_line" hook_locale "$hook_locale"
            return 1
        }

        cmd="$(restore_command_of "$file")"
        run_in_pane_shell "$pane_locale" "$cmd"
        assert_nothing_executed || {
            fuzz_report "$i" "a value was executed; command" "$cmd" hook_locale "$hook_locale" pane_locale "$pane_locale"
            return 1
        }
        [ -f "$BATS_TEST_TMPDIR/env.dump" ] || {
            fuzz_report "$i" "claude never ran; command" "$cmd" hook_locale "$hook_locale" pane_locale "$pane_locale" \
                pane_output "$(cat "$BATS_TEST_TMPDIR/pane.log")"
            return 1
        }
        [ "$(tr '\0' ' ' <"$BATS_TEST_TMPDIR/argv.dump")" = "--resume session-$i " ] || {
            fuzz_report "$i" "wrong claude arguments" "$(tr '\0' ' ' <"$BATS_TEST_TMPDIR/argv.dump")" command "$cmd"
            return 1
        }
        ! grep -qF -- "$leak_marker" "$BATS_TEST_TMPDIR/env.dump" || {
            fuzz_report "$i" "non-allowlisted variable replayed; command" "$cmd"
            return 1
        }

        load_pane_env
        for key in "${!expected[@]}"; do
            [[ -v "PANE_ENV[$key]" && "${PANE_ENV[$key]}" == "${expected[$key]}" ]] || {
                fuzz_report "$i" "variable" "$key" expected "${expected[$key]}" actual "${PANE_ENV[$key]-<unset>}" \
                    command "$cmd" hook_locale "$hook_locale" pane_locale "$pane_locale" \
                    process_env "$(printf '%q ' "${spawn_args[@]}")"
                return 1
            }
        done
        for key in "${!PANE_ENV[@]}"; do
            [[ -v "expected[$key]" ]] || {
                fuzz_report "$i" "leaked default survived" "$key=${PANE_ENV[$key]}" command "$cmd"
                return 1
            }
        done
    done
}

@test "property: a session id outside [A-Za-z0-9_-]+ always falls back to the picker" {
    local i pid proc_start file hook_locale original_line rewritten_line expected_field

    RANDOM="$FUZZ_SEED"
    pid="$(spawn_fake_claude_pid_with_env)"
    proc_start="$(proc_start_time_of "$pid")"
    file="$BATS_TEST_TMPDIR/resurrect.txt"

    for ((i = 1; i <= FUZZ_ITERATIONS * 2; i++)); do
        fuzz_gen_session_id
        fuzz_pick_locale
        hook_locale="$FUZZ_LOCALE"

        write_session_json "$pid" "$FUZZ_ID" "sess:@1.%1" "/home/testuser/project" "$proc_start"
        write_resurrect_file "$file" "claude" ":/home/testuser/project"
        original_line="$(cat "$file")"

        run_hook_in_locale "$hook_locale" "$file" || {
            fuzz_report "$i" "hook exited non-zero for id" "$FUZZ_ID" hook_locale "$hook_locale"
            return 1
        }

        if ((FUZZ_ID_VALID)); then
            expected_field=":${CLEAR_PREFIX}claude --resume ${FUZZ_ID}"
        else
            expected_field=":claude --resume"
        fi
        rewritten_line="$(cat "$file")"
        [ "$(wc -l <"$file")" -eq 1 ] &&
            [ "${rewritten_line%$'\t'*}" = "${original_line%$'\t'*}" ] &&
            [ "${rewritten_line##*$'\t'}" = "$expected_field" ] || {
            fuzz_report "$i" "session id" "$FUZZ_ID" valid "$FUZZ_ID_VALID" hook_locale "$hook_locale" \
                expected "$expected_field" actual "${rewritten_line##*$'\t'}"
            return 1
        }
        assert_nothing_executed || {
            fuzz_report "$i" "the hook executed the session id" "$FUZZ_ID"
            return 1
        }
    done
}
