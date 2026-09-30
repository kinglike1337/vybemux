#!/bin/bash
# =============================================================================
# validate-tmux-conf.sh — tmux.conf syntax validation for pre-commit and CI.
#
# `tmux -f tmux.conf start-server \; kill-server` (a commonly suggested
# method) does NOT reliably detect syntax errors: even a
# completely invented command name returns exit status 0 because start-server
# immediately exits without an attached session (exit-empty), before an error
# can become visible. Instead, the reliable approach starts an empty isolated
# server and loads the config with `source-file` as an active command AGAINST
# that server—this produces "file:line: unknown command: ..." and a real
# non-zero error exit status.
#
# The server starts with -f /dev/null so the user's own ~/.tmux.conf (or XDG
# config) is not loaded first: the result must depend only on the file under
# test, not on whatever happens to be installed in $HOME.
#
# The server runs with a temporary, empty HOME (and XDG_CONFIG_HOME): the
# project tmux.conf sources ~/.tmux.conf.local and starts the plugins of an
# existing installation (TPM, tmux-continuum, which may even start a restore)
# when they exist, and none of that belongs in a syntax check of one file.
#
# Usage: validate-tmux-conf.sh [--label TEXT] [config-file]
#   --label TEXT  names the file in the messages (default "tmux.conf"), e.g.
#                 a user override file validated on its own.
#
# The socket name is unique to the PID and is never shared with the real,
# potentially running tmux server of this development session.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

echo_error() { echo -e "${RED}✗ $1${NC}" >&2; }
echo_success() { echo -e "${GREEN}✓ $1${NC}"; }

LABEL="tmux.conf"
if [[ "${1:-}" == "--label" ]]; then
    LABEL="${2:?Usage: validate-tmux-conf.sh [--label TEXT] [config-file]}"
    shift 2
fi

readonly LABEL
readonly CONF_FILE="${1:-$(dirname "$0")/../tmux.conf}"
readonly SOCKET_NAME="vybemux-conf-validate-$$"
VALIDATION_HOME=""

cleanup() {
    tmux -L "$SOCKET_NAME" kill-server >/dev/null 2>&1 || true
    if [[ -n "$VALIDATION_HOME" ]]; then
        rm -rf "$VALIDATION_HOME"
    fi
}
trap cleanup EXIT

if [[ ! -f "$CONF_FILE" ]]; then
    echo_error "Config file not found: $CONF_FILE"
    exit 1
fi

CONF_FILE_ABS="$(cd "$(dirname "$CONF_FILE")" && pwd)/$(basename "$CONF_FILE")"
VALIDATION_HOME="$(mktemp -d)"
mkdir -p "$VALIDATION_HOME/.config"

HOME="$VALIDATION_HOME" XDG_CONFIG_HOME="$VALIDATION_HOME/.config" \
    tmux -L "$SOCKET_NAME" -f /dev/null new-session -d -s validate >/dev/null

if ! tmux -L "$SOCKET_NAME" source-file "$CONF_FILE_ABS"; then
    echo_error "$LABEL contains syntax errors (see message above): $CONF_FILE"
    exit 1
fi

echo_success "$LABEL is syntactically valid: $CONF_FILE"
