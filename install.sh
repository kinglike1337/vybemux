#!/bin/bash
# =============================================================================
# vybemux Installer Script
# Installs tmux configuration with plugins and bash integration
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME"
BACKUP_DIR="$HOME/.vybemux-backup/$(date +%Y-%m-%d_%H%M%S)"
TMUX_CONF="$INSTALL_DIR/.tmux.conf"
TMUX_BASH="$INSTALL_DIR/.tmux.bash"
TMUX_SCRIPTS_DIR="$INSTALL_DIR/.tmux/scripts"
TMUX_PLUGINS_DIR="$INSTALL_DIR/.tmux/plugins"
BASHRC="$HOME/.bashrc"
SOURCE_LINE="[ -f ~/.tmux.bash ] && . ~/.tmux.bash"

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
        echo "Usage: $0            Install vybemux"
        echo "       $0 --status   Show installation status"
        exit 0
        ;;
    --status)
        echo ""
        echo -e "${BLUE}============================================================================${NC}"
        echo -e "${BLUE}vybemux Installation Status${NC}"
        echo -e "${BLUE}============================================================================${NC}"
        echo ""
        
        INSTALLED=false

        if [ -f "$TMUX_CONF" ]; then
            echo_success "tmux config found: $TMUX_CONF"
            INSTALLED=true
        else
            echo_warning "tmux config not found: $TMUX_CONF"
        fi
        
        if [ -f "$TMUX_BASH" ]; then
            echo_success "tmux.bash found: $TMUX_BASH"
            INSTALLED=true
        else
            echo_warning "tmux.bash not found: $TMUX_BASH"
        fi
        
        if [ -d "$TMUX_PLUGINS_DIR" ]; then
            echo_success "Plugins directory found: $TMUX_PLUGINS_DIR"
            INSTALLED=true
        else
            echo_warning "Plugins directory not found: $TMUX_PLUGINS_DIR"
        fi
        
        if [ -f "$BASHRC" ]; then
            if grep -q "$SOURCE_LINE" "$BASHRC"; then
                echo_success "Source line found in ~/.bashrc"
            else
                echo_warning "Source line NOT found in ~/.bashrc"
            fi
        else
            echo_warning "$HOME/.bashrc not found"
        fi
        
        echo ""
        echo -e "${BLUE}--- tmux Information ---${NC}"
        
        if command -v tmux &>/dev/null; then
            TMUX_VERSION=$(tmux -V | sed 's/tmux //')
            echo_info "tmux version: $TMUX_VERSION"
        else
            echo_warning "tmux not installed"
        fi
        
        if [ -d "$TMUX_PLUGINS_DIR" ]; then
            if [ -d "$TMUX_PLUGINS_DIR/tpm" ]; then
                echo_success "TPM plugin: installed"
            else
                echo_warning "TPM plugin: not found"
            fi
            
            if [ -d "$TMUX_PLUGINS_DIR/tmux-resurrect" ]; then
                echo_success "tmux-resurrect plugin: installed"
            else
                echo_warning "tmux-resurrect plugin: not found"
            fi
            
            if [ -d "$TMUX_PLUGINS_DIR/tmux-continuum" ]; then
                echo_success "tmux-continuum plugin: installed"
            else
                echo_warning "tmux-continuum plugin: not found"
            fi
            
            if [ -d "$TMUX_PLUGINS_DIR/tmux-yank" ]; then
                echo_success "tmux-yank plugin: installed"
            else
                echo_warning "tmux-yank plugin: not found"
            fi
        fi
        
        echo ""
        echo -e "${BLUE}============================================================================${NC}"
        
        if [ "$INSTALLED" = true ]; then
            echo_success "vybemux is installed"
        else
            echo_warning "vybemux is not installed"
        fi
        
        echo -e "${BLUE}============================================================================${NC}"
        echo ""
        exit 0
        ;;
        *)
            echo_error "Unknown parameter: $1"
            echo "Usage: $0  or  $0 --status"
            exit 1
            ;;
    esac
done

# Check if tmux is installed
echo_info "Checking tmux installation..."
if ! command -v tmux &>/dev/null; then
    echo_error "tmux is not installed. Please install it first:"
    echo "  sudo apt install tmux"
    echo "Or use your distribution's package manager."
    exit 1
fi

# Check tmux version (require at least 3.2 for display-menu -OM)
TMUX_VERSION=$(tmux -V | sed 's/tmux //')
echo_info "tmux version: $TMUX_VERSION"
TMUX_MAJOR=$(echo "$TMUX_VERSION" | cut -d. -f1)
TMUX_MINOR=$(echo "$TMUX_VERSION" | cut -d. -f2 | tr -cd '0-9')
if [[ $TMUX_MAJOR -lt 3 ]] || [[ $TMUX_MAJOR -eq 3 && $TMUX_MINOR -lt 2 ]]; then
    echo_warning "vybemux requires tmux >= 3.2. Your version: $TMUX_VERSION"
    echo_warning "Some features may not work correctly (display-menu -OM)."
fi

# Check if plugins submodules are present
echo_info "Checking plugins..."
if [ ! -d "$REPO_DIR/plugins/tpm" ]; then
    echo_error "Plugins not found. Did you clone with --recurse-submodules?"
    echo "  git clone --recurse-submodules <repo-url>"
    exit 1
fi

# Create backup directory
echo_info "Creating backup of existing files..."
mkdir -p "$BACKUP_DIR"

backup_if_exists() {
    local source="$1"
    local backup_path
    backup_path="$BACKUP_DIR/$(basename "$source")"
    if [ -e "$source" ] || [ -L "$source" ]; then
        echo_info "Backing up: $source"
        mv "$source" "$backup_path"
    fi
}

# Backup existing files
backup_if_exists "$TMUX_CONF"
backup_if_exists "$TMUX_BASH"
backup_if_exists "$TMUX_SCRIPTS_DIR"
backup_if_exists "$TMUX_PLUGINS_DIR"

# Copy configuration files
echo_info "Installing configuration files..."
cp "$REPO_DIR/tmux.conf" "$TMUX_CONF"
cp "$REPO_DIR/tmux.bash" "$TMUX_BASH"
mkdir -p "$TMUX_SCRIPTS_DIR"
cp "$REPO_DIR/scripts/shorten-path.sh" "$TMUX_SCRIPTS_DIR/shorten-path.sh"
chmod +x "$TMUX_SCRIPTS_DIR/shorten-path.sh"

# Link or copy plugins
echo_info "Installing plugins..."
mkdir -p "$(dirname "$TMUX_PLUGINS_DIR")"
ln -s "$REPO_DIR/plugins" "$TMUX_PLUGINS_DIR"
echo_success "Plugins linked: $TMUX_PLUGINS_DIR -> $REPO_DIR/plugins"

# Check if .bashrc sources tmux.bash
echo_info "Checking ~/.bashrc..."

    if [ -f "$BASHRC" ]; then
        if grep -q "$SOURCE_LINE" "$BASHRC"; then
            echo_success "\$HOME/.bashrc already sources \$HOME/.tmux.bash"
        else
            echo_warning "\$HOME/.bashrc does not source \$HOME/.tmux.bash"
        echo ""
        echo "Please add this line to ~/.bashrc (after the interactive shell check):"
        echo ""
        echo -e "${GREEN}$SOURCE_LINE${NC}"
        echo ""
        echo "Example location: after 'case $- in *i*) ;; esac'"
    fi
    else
        echo_warning "\$HOME/.bashrc not found. Please create it and add:"
    echo ""
    echo -e "${GREEN}$SOURCE_LINE${NC}"
fi

# Syntax check tmux config
echo_info "Validating tmux configuration..."
if tmux -f "$TMUX_CONF" start-server \; kill-server 2>/dev/null; then
    echo_success "tmux configuration is valid"
else
    echo_error "tmux configuration has syntax errors"
    exit 1
fi

# Restore from backup if available (optional)
echo_info "Restoring previous tmux session if available..."
if [ -d "$HOME/.tmux/resurrect" ] && [ "$(ls -A "$HOME/.tmux/resurrect" 2>/dev/null)" ]; then
    echo_warning "Previous tmux-resurrect data found in ~/.tmux/resurrect/"
    echo "To restore your previous session, press Ctrl+a, then 'R' (Restore Session) in tmux"
fi

# Done
echo ""
echo_success "vybemux installed successfully!"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Start tmux manually with: tmux new-session"
echo ""
echo "To apply changes:"
echo "  1. Start a new shell or run: source ~/.bashrc"
echo "  2. Reload tmux config: Press Ctrl+a, then 'r'"
echo ""
echo "Keybinding reference: See README.md in the vybemux repository"
