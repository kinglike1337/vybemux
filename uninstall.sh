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
VSCODE_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
VSCODE_SETTINGS_DESKTOP="$HOME/.config/Code/User/settings.json"

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
if [ -f "$VSCODE_SETTINGS" ] || [ -f "$VSCODE_SETTINGS_DESKTOP" ]; then
    echo "  - vybemux profile from VS Code settings.json"
fi
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

# Remove vybemux profile from VS Code settings.json
VSCODE_SETTINGS_FILE=""
if [ -f "$VSCODE_SETTINGS" ]; then
    VSCODE_SETTINGS_FILE="$VSCODE_SETTINGS"
elif [ -f "$VSCODE_SETTINGS_DESKTOP" ]; then
    VSCODE_SETTINGS_FILE="$VSCODE_SETTINGS_DESKTOP"
fi

if [ -n "$VSCODE_SETTINGS_FILE" ]; then
    echo_info "Checking VS Code settings for vybemux profile..."
    
    if grep -q '"vybemux"' "$VSCODE_SETTINGS_FILE"; then
        echo_info "Removing vybemux profile from VS Code settings..."
        
        python3 <<EOF
import json
import sys

try:
    with open("$VSCODE_SETTINGS_FILE", "r") as f:
        settings = json.load(f)

    if "terminal.integrated.profiles.linux" in settings:
        if "vybemux" in settings["terminal.integrated.profiles.linux"]:
            del settings["terminal.integrated.profiles.linux"]["vybemux"]

            if len(settings["terminal.integrated.profiles.linux"]) == 0:
                del settings["terminal.integrated.profiles.linux"]

        with open("$VSCODE_SETTINGS_FILE", "w") as f:
            json.dump(settings, f, indent=4)
            f.write("\n")

    print("SUCCESS")
except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON in settings.json: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print(f"ERROR: File not found: $VSCODE_SETTINGS_FILE", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        
        echo_success "Removed vybemux profile from: $VSCODE_SETTINGS_FILE"
    else
        echo_info "No vybemux profile found in VS Code settings"
    fi
fi

# Check if tmux is running
if pgrep -x tmux > /dev/null; then
    echo ""
    echo_warning "tmux is still running"
    echo_info "Please restart your shell or run: tmux kill-server"
fi

echo ""
echo_success "vybemux uninstalled successfully!"
echo ""
echo "Note: You may need to restart your shell for changes to take effect"
