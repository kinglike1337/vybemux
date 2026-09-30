#!/bin/bash
# =============================================================================
# Harden tmux-resurrect Data Permissions
# Restricts saved layouts and captured pane contents to the current user
# =============================================================================

set -euo pipefail

: "${HOME:?HOME is required}"

run_user_hook=false
if [[ "${1:-}" == "--run-user-hook" ]]; then
    run_user_hook=true
    shift
fi
if [[ $# -gt 1 ]]; then
    echo "Usage: harden-resurrect-permissions.sh [--run-user-hook] [resurrect-directory]" >&2
    exit 1
fi

resurrect_dir="${1:-}"
if [[ -z "$resurrect_dir" ]] && command -v tmux >/dev/null 2>&1; then
    resurrect_dir="$(tmux show-option -gqv @resurrect-dir 2>/dev/null || true)"
fi
if [[ -z "$resurrect_dir" ]]; then
    if [[ -d "$HOME/.tmux/resurrect" ]]; then
        resurrect_dir="$HOME/.tmux/resurrect"
    else
        resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    fi
fi
resurrect_dir="${resurrect_dir//\$HOME/$HOME}"
if [[ "$resurrect_dir" == *"\$HOSTNAME"* ]]; then
    host_name="$(hostname 2>/dev/null || true)"
    resurrect_dir="${resurrect_dir//\$HOSTNAME/$host_name}"
fi
resurrect_dir="${resurrect_dir//\~/$HOME}"

mkdir -p "$resurrect_dir"

unexpected_entry="$(find -H "$resurrect_dir" -mindepth 1 -maxdepth 1 \
    ! -name 'tmux_resurrect_*.txt' \
    ! -name 'pane_contents.tar.gz' \
    ! -name 'last' \
    ! -name 'claude-env' \
    ! -name 'save' \
    ! -name 'restore' \
    -print -quit)"
dedicated_root=false
if [[ -z "$unexpected_entry" ]]; then
    dedicated_root=true
    chmod 700 "$resurrect_dir"
fi

for operation in save restore; do
    operation_dir="$resurrect_dir/$operation"
    pane_dir="$operation_dir/pane_contents"
    if [[ "$dedicated_root" == true ]]; then
        if [[ -d "$operation_dir" ]]; then
            chmod 700 "$operation_dir"
        fi
        if [[ -d "$pane_dir" ]]; then
            chmod 700 "$pane_dir"
        fi
    fi
    if [[ -d "$pane_dir" ]]; then
        find -H "$pane_dir" -maxdepth 1 -type f -name 'pane-*' \
            -exec chmod 600 {} +
    fi
done

secret_env_dir="$resurrect_dir/claude-env"
if [[ -d "$secret_env_dir" ]]; then
    chmod 700 "$secret_env_dir"
    find -H "$secret_env_dir" -maxdepth 1 -type f -exec chmod 600 {} +
fi

find -H "$resurrect_dir" -mindepth 1 -maxdepth 1 -type f \
    \( -name 'tmux_resurrect_*.txt' -o -name 'pane_contents.tar.gz' \) \
    -exec chmod 600 {} +

if [[ "$run_user_hook" == true ]] && command -v tmux >/dev/null 2>&1; then
    user_hook="$(tmux show-option -gqv \
        @vybemux-resurrect-hook-post-save-all 2>/dev/null || true)"
    if [[ -n "$user_hook" ]]; then
        bash -c "$user_hook"
    fi
fi
