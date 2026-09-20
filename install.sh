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
BACKUP_ROOT="$HOME/.vybemux-backup"
BACKUP_DIR=""
TMUX_CONF="$INSTALL_DIR/.tmux.conf"
TMUX_BASH="$INSTALL_DIR/.tmux.bash"
TMUX_SCRIPTS_DIR="$INSTALL_DIR/.tmux/scripts"
TMUX_PLUGINS_DIR="$INSTALL_DIR/.tmux/plugins"
INSTALLED_VERSION_FILE="$INSTALL_DIR/.tmux/VERSION"
INSTALLED_GIT_FILE="$INSTALL_DIR/.tmux/VERSION_GIT"
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

        # git describe shows "vX.Y.Z" exactly at the tag; otherwise "vX.Y.Z-N-gHASH"
        # -- how far a checkout is ahead of the last release tag (dev
        # state after the tag, before the next release workflow run).
        # REPO_DEV_DESCRIBE is live from the current checkout; INSTALLED_GIT
        # is the state frozen during the last ./install.sh run -- the two
        # can diverge if the repo has moved on since then without the bare
        # VERSION number changing.
        REPO_VERSION=""
        [ -f "$REPO_DIR/VERSION" ] && REPO_VERSION="$(cat "$REPO_DIR/VERSION")"
        REPO_DEV_DESCRIBE="$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null)" || true
        [ "$REPO_DEV_DESCRIBE" = "v$REPO_VERSION" ] && REPO_DEV_DESCRIBE=""

        INSTALLED_VERSION=""
        [ -f "$INSTALLED_VERSION_FILE" ] && INSTALLED_VERSION="$(cat "$INSTALLED_VERSION_FILE")"
        INSTALLED_DEV_DESCRIBE=""
        [ -f "$INSTALLED_GIT_FILE" ] && INSTALLED_DEV_DESCRIBE="$(cat "$INSTALLED_GIT_FILE")"
        [ "$INSTALLED_DEV_DESCRIBE" = "v$INSTALLED_VERSION" ] && INSTALLED_DEV_DESCRIBE=""

        REPO_LABEL="$REPO_VERSION"
        [ -n "$REPO_DEV_DESCRIBE" ] && REPO_LABEL="$REPO_VERSION (dev: $REPO_DEV_DESCRIBE)"
        INSTALLED_LABEL="$INSTALLED_VERSION"
        [ -n "$INSTALLED_DEV_DESCRIBE" ] && INSTALLED_LABEL="$INSTALLED_VERSION (dev: $INSTALLED_DEV_DESCRIBE)"

        if [ -n "$REPO_VERSION" ]; then
            echo_info "Repo version: $REPO_LABEL"
        fi
        if [ -n "$INSTALLED_VERSION" ]; then
            if [ "$INSTALLED_VERSION" = "$REPO_VERSION" ] && [ "$INSTALLED_DEV_DESCRIBE" = "$REPO_DEV_DESCRIBE" ]; then
                echo_success "Installed version: $INSTALLED_LABEL (up to date)"
            else
                echo_warning "Installed version: $INSTALLED_LABEL (repo has $REPO_LABEL — run ./install.sh to update)"
            fi
        else
            echo_warning "Installed version: unknown (no $INSTALLED_VERSION_FILE — run ./install.sh)"
        fi
        echo ""

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
            echo_info "tmux version: $TMUX_VERSION ($(command -v tmux))"
        else
            echo_warning "tmux not installed"
        fi

        if [ -d "$TMUX_PLUGINS_DIR" ]; then
            for plugin_name in tpm tmux-resurrect tmux-continuum tmux-yank; do
                plugin_path="$TMUX_PLUGINS_DIR/$plugin_name"
                if [ ! -d "$plugin_path" ]; then
                    echo_warning "$plugin_name plugin: not found"
                    continue
                fi
                # || true: without it, set -e treats a failed command
                # substitution (e.g. no tags reachable in a shallow/CI
                # checkout) as fatal for the whole script -- a missing
                # version/URL should just fall back to "?" below, not
                # abort --status entirely (broke install-smoke-test, PR #19).
                plugin_version="$(git -C "$plugin_path" describe --tags --always 2>/dev/null)" || true
                plugin_url="$(git -C "$plugin_path" remote get-url origin 2>/dev/null)" || true
                echo_success "$plugin_name plugin: installed (${plugin_version:-?}, ${plugin_url:-?})"
            done
        fi

        if [ -x "$TMUX_SCRIPTS_DIR/resurrect-claude-hook.sh" ]; then
            echo_success "resurrect-claude-hook.sh: installed and executable"
        elif [ -f "$TMUX_SCRIPTS_DIR/resurrect-claude-hook.sh" ]; then
            echo_warning "resurrect-claude-hook.sh: found but not executable"
        else
            echo_warning "resurrect-claude-hook.sh: not found"
        fi

        if [ -x "$TMUX_SCRIPTS_DIR/about.sh" ]; then
            echo_success "about.sh: installed and executable"
        elif [ -f "$TMUX_SCRIPTS_DIR/about.sh" ]; then
            echo_warning "about.sh: found but not executable"
        else
            echo_warning "about.sh: not found"
        fi

        if [ -x "$TMUX_SCRIPTS_DIR/ai-tools-menu.sh" ]; then
            echo_success "ai-tools-menu.sh: installed and executable"
        elif [ -f "$TMUX_SCRIPTS_DIR/ai-tools-menu.sh" ]; then
            echo_warning "ai-tools-menu.sh: found but not executable"
        else
            echo_warning "ai-tools-menu.sh: not found"
        fi

        echo ""
        echo -e "${BLUE}--- AI Coding Agents (shown in the \"AI Tools\" menu) ---${NC}"

        for tool in claude opencode codex pi; do
            if command -v "$tool" &>/dev/null; then
                echo_success "$tool: found ($(command -v "$tool"))"
            else
                echo_warning "$tool: not found on \$PATH"
            fi
        done

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

# Check if plugin submodules are populated
echo_info "Checking plugins..."
required_plugin_files=(
    "plugins/tpm/tpm"
    "plugins/tmux-resurrect/scripts/save.sh"
    "plugins/tmux-continuum/continuum.tmux"
    "plugins/tmux-yank/yank.tmux"
)
for plugin_file in "${required_plugin_files[@]}"; do
    if [ -f "$REPO_DIR/$plugin_file" ]; then
        continue
    fi
    echo_error "Plugin content missing: $plugin_file"
    echo "  git clone --recurse-submodules <repo-url>"
    echo "  git submodule update --init --recursive"
    exit 1
done

# Create backup directory
echo_info "Creating backup of existing files..."
mkdir -p "$BACKUP_ROOT"
BACKUP_DIR="$(mktemp -d "$BACKUP_ROOT/$(date +%Y-%m-%d_%H%M%S).XXXXXX")"

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
backup_if_exists "$INSTALLED_VERSION_FILE"
backup_if_exists "$INSTALLED_GIT_FILE"

# Copy configuration files
echo_info "Installing configuration files..."
cp "$REPO_DIR/tmux.conf" "$TMUX_CONF"
cp "$REPO_DIR/tmux.bash" "$TMUX_BASH"
# Create the personal override file once (never overwrite).
# ~/.tmux.conf.local is sourced optionally (source-file -q); a missing
# example file must therefore not abort the installation.
if [ ! -f "$HOME/.tmux.conf.local" ] && [ -f "$REPO_DIR/tmux.conf.local.example" ]; then
    cp "$REPO_DIR/tmux.conf.local.example" "$HOME/.tmux.conf.local"
    echo_info "Override file created: ~/.tmux.conf.local (customizable)"
fi
mkdir -p "$TMUX_SCRIPTS_DIR"
if [ -f "$REPO_DIR/VERSION" ]; then
    cp "$REPO_DIR/VERSION" "$INSTALLED_VERSION_FILE"
fi
# Freeze the git state at installation time (see --status/about.sh):
# without this, "Installed version: 0.0.1" could not be distinguished from
# "0.0.1 + N untagged commits" if no exact release tag was checked out during
# installation. || true: a non-git repo (e.g. a tarball installation
# without .git) must not abort the installation.
git -C "$REPO_DIR" describe --tags --always >"$INSTALLED_GIT_FILE" 2>/dev/null || true
cp "$REPO_DIR/scripts/shorten-path.sh" "$TMUX_SCRIPTS_DIR/shorten-path.sh"
chmod +x "$TMUX_SCRIPTS_DIR/shorten-path.sh"
cp "$REPO_DIR/scripts/cheatsheet.sh" "$TMUX_SCRIPTS_DIR/cheatsheet.sh"
chmod +x "$TMUX_SCRIPTS_DIR/cheatsheet.sh"
cp "$REPO_DIR/scripts/tui-tab.sh" "$TMUX_SCRIPTS_DIR/tui-tab.sh"
chmod +x "$TMUX_SCRIPTS_DIR/tui-tab.sh"
cp "$REPO_DIR/scripts/sessions.sh" "$TMUX_SCRIPTS_DIR/sessions.sh"
chmod +x "$TMUX_SCRIPTS_DIR/sessions.sh"
cp "$REPO_DIR/scripts/ai-tools-menu.sh" "$TMUX_SCRIPTS_DIR/ai-tools-menu.sh"
chmod +x "$TMUX_SCRIPTS_DIR/ai-tools-menu.sh"
cp "$REPO_DIR/scripts/about.sh" "$TMUX_SCRIPTS_DIR/about.sh"
chmod +x "$TMUX_SCRIPTS_DIR/about.sh"
cp "$REPO_DIR/scripts/resurrect-claude-hook.sh" "$TMUX_SCRIPTS_DIR/resurrect-claude-hook.sh"
chmod +x "$TMUX_SCRIPTS_DIR/resurrect-claude-hook.sh"
cp "$REPO_DIR/scripts/harden-resurrect-permissions.sh" "$TMUX_SCRIPTS_DIR/harden-resurrect-permissions.sh"
chmod +x "$TMUX_SCRIPTS_DIR/harden-resurrect-permissions.sh"
for resurrect_dir in \
    "$HOME/.tmux/resurrect" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"; do
    if [[ -d "$resurrect_dir" ]]; then
        "$TMUX_SCRIPTS_DIR/harden-resurrect-permissions.sh" "$resurrect_dir"
    fi
done
"$TMUX_SCRIPTS_DIR/harden-resurrect-permissions.sh"

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
# Use a private socket (-L) so we never touch the user's running server:
# a plain `start-server \; kill-server` on the default socket would kill an
# active tmux session during install.
echo_info "Validating tmux configuration..."
if "$REPO_DIR/scripts/validate-tmux-conf.sh" "$TMUX_CONF"; then
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
