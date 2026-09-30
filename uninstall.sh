#!/bin/bash
# =============================================================================
# vybemux Uninstaller Script
# Removes all vybemux configuration files from home directory
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Files to remove
TMUX_CONF="$HOME/.tmux.conf"
TMUX_BASH="$HOME/.tmux.bash"
TMUX_DIR="$HOME/.tmux"
TMUX_SCRIPTS_DIR="$TMUX_DIR/scripts"
BACKUP_DIR="$HOME/.vybemux-backup"
BASHRC="$HOME/.bashrc"
SOURCE_LINE="[ -f ~/.tmux.bash ] && . ~/.tmux.bash"

# True if $1 contains SOURCE_LINE as a whole line (surrounding whitespace
# ignored). A fixed-string comparison: the line is not a regex, a commented-out
# copy or a variant such as "test -f ... && . ..." does not count.
bashrc_has_source_line() {
    awk -v line="$SOURCE_LINE" '
        { gsub(/^[ \t]+|[ \t\r]+$/, ""); if ($0 == line) found = 1 }
        END { exit !found }
    ' "$1"
}

# Kept in sync with the scripts install.sh copies into ~/.tmux/scripts
# (test/uninstall.bats verifies this).
INSTALLED_SCRIPTS=(
    shorten-path.sh git-branch.sh cheatsheet.sh tui-tab.sh sessions.sh
    ai-tools-menu.sh about.sh resurrect-claude-hook.sh
    harden-resurrect-permissions.sh
)

# Everything below ~/.tmux is classified into paths this uninstaller removes
# (exactly what install.sh created) and paths it keeps (anything else: saved
# tmux-resurrect sessions, the user's own files, a real plugins directory).
REMOVE_PATHS=()
KEPT_ENTRIES=()

is_installed_script() {
    local name="$1" script
    for script in "${INSTALLED_SCRIPTS[@]}"; do
        if [[ "$name" == "$script" ]]; then
            return 0
        fi
    done
    return 1
}

classify_tmux_dir() {
    local path name
    if [ -d "$TMUX_DIR" ]; then
        while IFS= read -r -d '' path; do
            name="$(basename "$path")"
            case "$name" in
            VERSION | VERSION_GIT) REMOVE_PATHS+=("$path") ;;
            plugins)
                if [ -L "$path" ]; then
                    REMOVE_PATHS+=("$path")
                else
                    KEPT_ENTRIES+=("$path")
                fi
                ;;
            scripts)
                if [ -d "$path" ] && [ ! -L "$path" ]; then
                    while IFS= read -r -d '' script_path; do
                        if is_installed_script "$(basename "$script_path")"; then
                            REMOVE_PATHS+=("$script_path")
                        else
                            KEPT_ENTRIES+=("$script_path")
                        fi
                    done < <(find "$path" -mindepth 1 -maxdepth 1 -print0)
                else
                    KEPT_ENTRIES+=("$path")
                fi
                ;;
            *) KEPT_ENTRIES+=("$path") ;;
            esac
        done < <(find "$TMUX_DIR" -mindepth 1 -maxdepth 1 -print0)
    fi
}
classify_tmux_dir

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}vybemux Uninstaller${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Check if any vybemux files exist
FILES_EXIST=false
if [ -f "$TMUX_CONF" ] || [ -f "$TMUX_BASH" ] || [ "${#REMOVE_PATHS[@]}" -gt 0 ]; then
    FILES_EXIST=true
fi

if [ "$FILES_EXIST" = false ]; then
    echo_warning "No vybemux files found in home directory"
    echo ""
    read -r -p "Do you want to remove backups as well? (y/n): " remove_backups
    echo ""

    if [[ $remove_backups =~ ^[Yy]$ ]]; then
        if [ -d "$BACKUP_DIR" ]; then
            echo_info "Removing backup directory: $BACKUP_DIR"
            rm -rf "$BACKUP_DIR"
            echo_success "Backups removed"
        else
            echo_warning "No backup directory found"
        fi
    fi

    echo ""
    echo_success "Nothing to uninstall"
    exit 0
fi

# Ask for confirmation
echo_warning "This will remove the following files:"
echo ""
if [ -f "$TMUX_CONF" ]; then echo "  - $TMUX_CONF"; fi
if [ -f "$TMUX_BASH" ]; then echo "  - $TMUX_BASH"; fi
for path in ${REMOVE_PATHS[@]+"${REMOVE_PATHS[@]}"}; do
    echo "  - $path"
done
echo ""

if [ "${#KEPT_ENTRIES[@]}" -gt 0 ]; then
    echo_info "These entries were not installed by vybemux and will be kept"
    echo_info "(including saved tmux-resurrect sessions, if any):"
    echo ""
    for path in "${KEPT_ENTRIES[@]}"; do
        echo "  - $path"
    done
    echo ""
fi

read -r -p "Do you want to continue? (y/n): " confirm
echo ""

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo_info "Uninstall cancelled"
    exit 0
fi

# Remove files
echo_info "Removing vybemux files..."

if [ -f "$TMUX_CONF" ]; then
    rm -f "$TMUX_CONF"
    echo_success "Removed: $TMUX_CONF"
fi

if [ -f "$TMUX_BASH" ]; then
    rm -f "$TMUX_BASH"
    echo_success "Removed: $TMUX_BASH"
fi

for path in ${REMOVE_PATHS[@]+"${REMOVE_PATHS[@]}"}; do
    rm -f "$path"
    echo_success "Removed: $path"
done

if [ -d "$TMUX_SCRIPTS_DIR" ] && [ ! -L "$TMUX_SCRIPTS_DIR" ]; then
    if rmdir "$TMUX_SCRIPTS_DIR" 2>/dev/null; then
        echo_success "Removed: $TMUX_SCRIPTS_DIR (was empty)"
    fi
fi

if [ -d "$TMUX_DIR" ]; then
    if rmdir "$TMUX_DIR" 2>/dev/null; then
        echo_success "Removed: $TMUX_DIR (was empty)"
    else
        echo_warning "Kept: $TMUX_DIR (contains files not installed by vybemux)"
    fi
fi

# Remove source line from .bashrc
if [ -f "$BASHRC" ]; then
    if bashrc_has_source_line "$BASHRC"; then
        echo_info "Removing vybemux source line from ~/.bashrc..."

        # Create backup of .bashrc
        cp "$BASHRC" "${BASHRC}.vybemux-uninstall-backup"

        # Remove only whole-line matches (same rule as bashrc_has_source_line);
        # commented-out or differently written lines stay. An indented match
        # sits inside a block (if/then ... fi): deleting it could leave an
        # empty block and a syntax error, so it becomes an indented no-op
        # instead. The temp file lives next to .bashrc (not in /tmp) and the
        # file is rewritten in place with cat, preserving mode and symlinks.
        filtered="$(mktemp "${BASHRC}.XXXXXX")"
        awk -v line="$SOURCE_LINE" '
            {
                stripped = $0
                gsub(/^[ \t]+|[ \t\r]+$/, "", stripped)
                if (stripped != line) { print; next }
                match($0, /^[ \t]*/)
                if (RLENGTH > 0) print substr($0, 1, RLENGTH) ": # vybemux source line removed"
            }
        ' "$BASHRC" >"$filtered"
        cat "$filtered" >"$BASHRC"
        rm -f "$filtered"

        echo_success "Removed source line from ~/.bashrc"
        echo_warning "Backup saved to: ${BASHRC}.vybemux-uninstall-backup"
    else
        echo_info "No vybemux source line found in ~/.bashrc"
    fi
fi

# Ask about backups
echo ""
read -r -p "Do you want to remove vybemux backups? ($BACKUP_DIR) (y/n): " remove_backups
echo ""

if [[ $remove_backups =~ ^[Yy]$ ]]; then
    if [ -d "$BACKUP_DIR" ]; then
        echo_info "Removing backup directory: $BACKUP_DIR"
        rm -rf "$BACKUP_DIR"
        echo_success "Backups removed"
    else
        echo_warning "No backup directory found"
    fi
else
    echo_info "Backups preserved in: $BACKUP_DIR"
fi

# Check if tmux is running. tmux sets its process title to "tmux: server" /
# "tmux: client" (not plain "tmux"), so match by substring rather than -x.
# pgrep may also be missing in minimal environments (e.g. CI images without
# procps); fall back to ps, and skip the check entirely if neither is
# available rather than failing the uninstall.
tmux_running=""
if command -v pgrep >/dev/null 2>&1; then
    tmux_running=$(pgrep tmux 2>/dev/null || true)
elif command -v ps >/dev/null 2>&1; then
    # shellcheck disable=SC2009 # this branch only runs when pgrep is absent
    tmux_running=$(ps -eo comm 2>/dev/null | grep tmux || true)
fi

if [ -n "$tmux_running" ]; then
    echo ""
    echo_warning "tmux is still running"
    echo_info "Please restart your shell or run: tmux kill-server"
fi

echo ""
echo_success "vybemux uninstalled successfully!"
echo ""
echo "Note: You may need to restart your shell for changes to take effect"
