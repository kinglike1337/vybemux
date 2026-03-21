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
VSCODE_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
VSCODE_SETTINGS_DESKTOP="$HOME/.config/Code/User/settings.json"
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

# Parse mode argument
MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*|-m=*)
            MODE="${1#*=}"
            shift
            ;;
        --help|-h)
        echo "Usage: $0 --mode={auto|profile|manual}"
        echo "       $0 --status"
        echo ""
        echo "Modes:"
        echo "  auto    - Auto-attach active (VS Code terminals start tmux automatically)"
        echo "  profile - VS Code profile mode (tmux selectable from terminal menu)"
        echo "  manual  - Aliases only, no auto-activation"
        echo ""
        echo "Options:"
        echo "  --status - Shows current installation status"
        exit 0
        ;;
    --status)
        echo ""
        echo -e "${BLUE}============================================================================${NC}"
        echo -e "${BLUE}vybemux Installation Status${NC}"
        echo -e "${BLUE}============================================================================${NC}"
        echo ""
        
        INSTALLED=false
        AUTO_ATTACH="unknown"
        VYBEMUX_PROFILE="unknown"
        
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
        echo -e "${BLUE}--- Configuration Mode ---${NC}"
        
        if [ -f "$TMUX_BASH" ]; then
            if grep -q "DISABLED" "$TMUX_BASH"; then
                AUTO_ATTACH="disabled"
                echo_warning "Auto-Attach: Disabled"
            else
                AUTO_ATTACH="enabled"
                echo_success "Auto-Attach: Enabled"
            fi
        else
            echo_warning "Auto-Attach: Cannot determine (tmux.bash not found)"
        fi
        
        VSCODE_SETTINGS_FILE=""
        if [ -f "$VSCODE_SETTINGS" ]; then
            VSCODE_SETTINGS_FILE="$VSCODE_SETTINGS"
        elif [ -f "$VSCODE_SETTINGS_DESKTOP" ]; then
            VSCODE_SETTINGS_FILE="$VSCODE_SETTINGS_DESKTOP"
        fi
        
        if [ -n "$VSCODE_SETTINGS_FILE" ]; then
            if grep -q '"vybemux"' "$VSCODE_SETTINGS_FILE"; then
                VYBEMUX_PROFILE="installed"
                echo_success "VS Code vybemux profile: Installed ($VSCODE_SETTINGS_FILE)"
            else
                VYBEMUX_PROFILE="not installed"
                echo_warning "VS Code vybemux profile: Not found"
            fi
        else
            echo_warning "VS Code settings not found"
        fi
        
        echo ""
        echo -e "${BLUE}--- Inferred Mode ---${NC}"
        
        if [ "$AUTO_ATTACH" = "enabled" ] && [ "$VYBEMUX_PROFILE" != "installed" ]; then
            echo_info "Mode: auto"
        elif [ "$AUTO_ATTACH" = "disabled" ] && [ "$VYBEMUX_PROFILE" = "installed" ]; then
            echo_info "Mode: profile"
        elif [ "$AUTO_ATTACH" = "disabled" ] && [ "$VYBEMUX_PROFILE" != "installed" ]; then
            echo_info "Mode: manual"
        else
            echo_warning "Mode: Cannot determine (configuration may be mixed)"
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
            echo "Usage: $0 --mode={auto|profile|manual} or $0 --status"
            echo "See $0 --help for details"
            exit 1
            ;;
    esac
done

if [ -z "$MODE" ]; then
    echo_error "No mode specified!"
    echo ""
    echo "Usage: $0 --mode={auto|profile|manual} or $0 --status"
    echo "See $0 --help for details"
    exit 1
fi

if [ "$MODE" != "auto" ] && [ "$MODE" != "profile" ] && [ "$MODE" != "manual" ]; then
    echo_error "Invalid mode: $MODE"
    echo "Allowed modes: auto, profile, manual"
    exit 1
fi

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

# Mode-specific modifications
if [ "$MODE" = "profile" ] || [ "$MODE" = "manual" ]; then
    echo_info "Disabling Auto-Attach in ~/.tmux.bash..."
    sed -i '/Auto-attach for Code-Server/,/^fi$/s/^/# DISABLED: /' "$TMUX_BASH"
    echo_success "Auto-Attach disabled (Mode: $MODE)"
fi

if [ "$MODE" = "profile" ]; then
    echo_info "Configuring VS Code vybemux profile..."
    VSCODE_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
    
    if [ -f "$VSCODE_SETTINGS" ]; then
        echo_info "Backing up: $VSCODE_SETTINGS"
        cp "$VSCODE_SETTINGS" "$BACKUP_DIR/settings.json"
    fi
    
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    if [ ! -f "$VSCODE_SETTINGS" ]; then
        echo '{}' > "$VSCODE_SETTINGS"
    fi

    python3 <<EOF
import json
import sys

try:
    with open("$VSCODE_SETTINGS", "r") as f:
        settings = json.load(f)

    if "terminal.integrated.profiles.linux" not in settings:
        settings["terminal.integrated.profiles.linux"] = {}

    settings["terminal.integrated.profiles.linux"]["vybemux"] = {
        "path": "tmux",
        "args": ["new-session", "-A", "-s", "\${workspaceFolderBasename}"]
    }

    if "terminal.integrated.defaultProfile.linux" not in settings:
        settings["terminal.integrated.defaultProfile.linux"] = "bash"

    with open("$VSCODE_SETTINGS", "w") as f:
        json.dump(settings, f, indent=4)
        f.write("\n")
except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON in settings.json: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print(f"ERROR: File not found: $VSCODE_SETTINGS", file=sys.stderr)
    sys.exit(1)
EOF

    echo_success "VS Code vybemux profile installed"
    echo "  Open in VS Code: Terminal > Create New Terminal (vybemux)"
fi

# Check if .bashrc sources tmux.bash
echo_info "Checking ~/.bashrc..."

    if [ -f "$BASHRC" ]; then
        if grep -q "$SOURCE_LINE" "$BASHRC"; then
            echo_success "\$HOME/.bashrc already sources \$HOME/.tmux.bash"
        else
            echo_warning "\$HOME/.bashrc does not source \$HOME/.tmux.bash"
        echo ""
        echo "Please add this line to ~/.bashrc (after the interactive check, before SDKMAN):"
        echo ""
        echo -e "${GREEN}$SOURCE_LINE${NC}"
        echo ""
        echo "Example location: after 'case $- in *i*) ;; esac' and before tools requiring end-of-file placement"
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
echo_success "vybemux installed successfully (Modus: $MODE)!"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""

if [ "$MODE" = "auto" ]; then
    echo "Auto-Attach is active - VS Code terminals start tmux automatically"
elif [ "$MODE" = "profile" ]; then
    echo "vybemux profile installed - Select 'vybemux' in VS Code terminal menu"
elif [ "$MODE" = "manual" ]; then
    echo "Auto-Attach disabled - Start tmux manually with: tmux new-session"
fi

echo ""
echo "To apply changes:"
echo "  1. Start a new shell or run: source ~/.bashrc"
echo "  2. Reload tmux config: Press Ctrl+a, then 'r'"
echo ""
echo "Keybinding reference: See README.md in the vybemux repository"
