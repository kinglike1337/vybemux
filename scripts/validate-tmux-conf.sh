#!/bin/bash
# =============================================================================
# validate-tmux-conf.sh — tmux.conf syntax validation for pre-commit and CI.
#
# `tmux -f tmux.conf start-server \; kill-server` (the method previously
# documented in AGENTS.md) does NOT reliably detect syntax errors: even a
# completely invented command name returns exit status 0 because start-server
# immediately exits without an attached session (exit-empty), before an error
# can become visible. Instead, the reliable approach starts an empty isolated
# server and loads the config with `source-file` as an active command AGAINST
# that server—this produces "file:line: unknown command: ..." and a real
# non-zero error exit status.
#
# The socket name is unique to the PID and is never shared with the real,
# potentially running tmux server of this development session.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

echo_error() { echo -e "${RED}✗ $1${NC}" >&2; }
echo_success() { echo -e "${GREEN}✓ $1${NC}"; }

readonly CONF_FILE="${1:-$(dirname "$0")/../tmux.conf}"
readonly SOCKET_NAME="vybemux-conf-validate-$$"

cleanup() {
    tmux -L "$SOCKET_NAME" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -f "$CONF_FILE" ]]; then
    echo_error "Config file not found: $CONF_FILE"
    exit 1
fi

tmux -L "$SOCKET_NAME" new-session -d -s validate >/dev/null

if ! tmux -L "$SOCKET_NAME" source-file "$CONF_FILE"; then
    echo_error "tmux.conf contains syntax errors (see message above): $CONF_FILE"
    exit 1
fi

echo_success "tmux.conf is syntactically valid: $CONF_FILE"
