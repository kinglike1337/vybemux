# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

vybemux is a tmux configuration optimized for AI-assisted coding with Claude Code and OpenCode. Designed primarily for Code-Server (coder/code-server) environments, also works via SSH.

**Key Design Decision:** Plugins are bundled as git submodules (not fetched dynamically via TPM) to enable offline installation and reproducible deployments.

## Commands

### Installation
```bash
# Clone with submodules (required)
git clone --recurse-submodules <repo-url>
cd vybemux

# Install with mode selection
./install.sh --mode=auto      # Auto-attach in VS Code terminals
./install.sh --mode=profile    # VS Code profile mode (selectable)
./install.sh --mode=manual     # Aliases only, manual tmux start

# Check installation status
./install.sh --status
```

After installation, add this to `~/.bashrc` (after interactive check, before tools requiring end-of-file placement like SDKMAN):
```bash
[ -f ~/.tmux.bash ] && . ~/.tmux.bash
```

### Update Plugins
```bash
./update.sh    # Updates all 4 plugin submodules, stages .gitmodules
git commit -m 'Update submodules'
git push
```

### Uninstallation
```bash
./uninstall.sh    # Removes all config files, backups, VS Code profile
```

### tmux Operations
```bash
# Reload configuration after changes
tmux source-file ~/.tmux.conf

# Validate configuration syntax
tmux -f ~/.tmux.conf start-server \; kill-server
```

## Architecture

### Core Structure
```
vybemux/
├── tmux.conf          # Main tmux configuration (color, bindings, menus)
├── tmux.bash          # Bash integration (auto-attach, aliases, functions)
├── install.sh         # Installer with 3 modes (auto/profile/manual)
├── uninstall.sh       # Complete uninstaller
├── update.sh          # Submodule update script
├── scripts/           # Helper scripts for tmux status bar
│   ├── shorten-path.sh
│   └── test-clipboard.sh
└── plugins/           # Git submodules (not dynamically fetched)
    ├── tpm/           # tmux Plugin Manager (orchestrates other plugins)
    ├── tmux-resurrect/    # Session save/restore
    ├── tmux-continuum/    # Auto-save (every 15 min)
    └── tmux-yank/         # Clipboard integration
```

### Installation Modes

The installer supports three distinct modes that affect how tmux is activated:

| Mode | Auto-Attach | VS Code Profile | Use Case |
|------|-------------|-----------------|----------|
| `auto` | ✅ | ❌ | Primary development machine |
| `profile` | ❌ | ✅ | Multi-environment setup |
| `manual` | ❌ | ❌ | Occasional tmux usage |

**Implementation:** `--mode=profile` and `--mode=manual` comment out the auto-attach block in `~/.tmux.bash` using sed.

### Clipboard Architecture (Important)

vybemux is optimized for **Code-Server** where X11 tools may not be available:

1. **OSC 52 passthrough**: `set-clipboard on` + `allow-passthrough on` enables nested OSC 52 (vim → tmux → xterm.js)
2. **Mouse handling**: Disabled in Code-Server (`TERM_PROGRAM=vscode` check) to enable native browser selection
3. **tmux-yank**: Configured with OSC 52 fallback when no clipboard tools detected

**Mouse Toggle:** `Ctrl+a Ctrl+t` (useful for testing clipboard behavior)

### Status Bar Components

The status bar uses clickable menus and displays:
- Session name (left, clickable → session menu)
- Windows list (clickable to switch)
- `[+]` button (right, clickable → quick actions)
- Shortened path, git branch, hostname, date

## Key Files

| File | Purpose |
|------|---------|
| `tmux.conf` | All tmux settings: colors, bindings, menus, plugin config |
| `tmux.bash` | Auto-attach logic (lines 12-18), aliases, tmux-dev/project functions |
| `install.sh` | Validation, backup, file copying, mode-specific modifications |
| `scripts/shorten-path.sh` | Path shortening for status bar (e.g., `~/p/vybemux`) |

## Configuration Patterns

### Adding AI Tool Commands
AI tool commands appear in two places (must be updated in sync):
1. `tmux.conf`: 6 `display-menu` blocks (lines 170-340)
2. `tmux.bash`: Aliases (lines 34-40)

### Tokyo Night Theme Colors
Located in `tmux.conf` under "Status Bar" section:
- Background: `#1a1b26`
- Accent: `#7aa2f7`
- Button: `#e0af68`
- Text: `#a9b1d6`
- Text muted: `#565f89`
- Separator: `#3b4261`

## Testing Changes

After modifying configuration:
```bash
# Syntax check
tmux -f ~/.tmux.conf start-server \; kill-server

# Reload in active session
Press Ctrl+a, then r
```

For clipboard testing:
```bash
bash ~/.tmux/scripts/test-clipboard.sh
```
