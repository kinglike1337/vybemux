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
BACKUP_DIR="$HOME/.vybemux-backup"
BASHRC="$HOME/.bashrc"
SOURCE_LINE="[ -f ~/.tmux.bash ] && . ~/.tmux.bash"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}vybemux Uninstaller${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Check if any vybemux files exist
FILES_EXIST=false
if [ -f "$TMUX_CONF" ] || [ -f "$TMUX_BASH" ] || [ -d "$TMUX_DIR" ]; then
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
if [ -f "$TMUX_CONF" ]; then     echo "  - $TMUX_CONF"; fi
if [ -f "$TMUX_BASH" ]; then echo "  - $TMUX_BASH"; fi
if [ -d "$TMUX_DIR" ]; then echo "  - $TMUX_DIR (directory)"; fi
echo ""

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

if [ -d "$TMUX_DIR" ]; then
    rm -rf "$TMUX_DIR"
    echo_success "Removed: $TMUX_DIR"
fi

# Remove source line from .bashrc
if [ -f "$BASHRC" ]; then
    if grep -q "$SOURCE_LINE" "$BASHRC"; then
        echo_info "Removing vybemux source line from ~/.bashrc..."

        # Create backup of .bashrc
        cp "$BASHRC" "${BASHRC}.vybemux-uninstall-backup"

        # Remove the source line
        sed -i '/\[ -f ~\/\.tmux\.bash \] && \. ~\/\.tmux\.bash/d' "$BASHRC"

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
