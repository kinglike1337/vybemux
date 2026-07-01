# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

vybemux is a tmux configuration optimized for AI-assisted coding with Claude Code and OpenCode. tmux runs on a remote host reached via SSH; Ghostty is the local terminal client.

**Key Design Decision:** Plugins are bundled as git submodules (not fetched dynamically via TPM) to enable offline installation and reproducible deployments.

## Commands

### Installation
```bash
# Clone with submodules (required)
git clone --recurse-submodules <repo-url>
cd vybemux

# Install
./install.sh

# Check installation status
./install.sh --status
```

After installation, add this to `~/.bashrc` (after the interactive shell check):
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
./uninstall.sh    # Removes all config files and backups
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
├── tmux.bash          # Bash integration (aliases, functions)
├── install.sh         # Installer (single mode) + --status/--help
├── uninstall.sh       # Complete uninstaller
├── update.sh          # Submodule update script
├── scripts/           # Helper scripts for tmux status bar
│   └── shorten-path.sh
└── plugins/           # Git submodules (not dynamically fetched)
    ├── tpm/           # tmux Plugin Manager (orchestrates other plugins)
    ├── tmux-resurrect/    # Session save/restore
    ├── tmux-continuum/    # Auto-save (every 15 min)
    └── tmux-yank/         # Clipboard integration
```

### Clipboard Architecture (Important)

tmux runs remotely over SSH, so vybemux relies on OSC 52 rather than X11 clipboard tools:

1. **OSC 52 passthrough**: `set-clipboard on` + `allow-passthrough on` enables nested OSC 52 (vim → tmux → Ghostty)
2. **tmux-yank**: `@custom_copy_command` forces OSC 52 so yanks reach the local clipboard without X11 tools
3. **Mouse selection**: Mouse is always on (clickable menus, pane resize, copy mode); hold Shift while dragging for Ghostty's native text selection

**Mouse Toggle:** `Ctrl+a Ctrl+t` (toggles between tmux mouse mode and Ghostty native selection)

### Status Bar Components

The status bar uses clickable menus and displays:
- Session name (left, clickable → session menu)
- Windows list (clickable to switch)
- `[+]` button (right, clickable → quick actions)
- Shortened path, git branch, hostname, date

## Ghostty Setup (Client Side)

tmux runs on the remote host; Ghostty is the local client. Enable Ghostty's
SSH integration in `~/.config/ghostty/config` so the terminfo and environment
reach the remote host:

```
shell-integration-features = ssh-env,ssh-terminfo
```

- `ssh-terminfo` installs `xterm-ghostty` on the remote host via `tic` on
  first connect (cached per user@host); falls back to `xterm-256color`.
- `ssh-env` forwards `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `COLORTERM`.

Clipboard uses OSC 52 (the only reliable path over SSH); Ghostty supports
OSC 52 writes natively.

### Claude Code Compatibility

The Kitty keyboard protocol (`extended-keys always`, `extended-keys-format
csi-u`, `terminal-features xterm*:extkeys`) forwards extended key events
through tmux, which is what allows Shift+Enter to work as a newline (not
submit) in Claude Code running inside tmux.

## Key Files

| File | Purpose |
|------|---------|
| `tmux.conf` | All tmux settings: colors, bindings, menus, plugin config |
| `tmux.bash` | Aliases, tmux-dev/project functions |
| `install.sh` | Validation, backup, file copying |
| `scripts/shorten-path.sh` | Path shortening for status bar (e.g., `~/p/vybemux`) |

## Configuration Patterns

### Adding AI Tool Commands
AI tool commands appear in two places (must be updated in sync):
1. `tmux.conf`: the Quick Actions menu (`MouseUp1StatusRight`) and the Window/Pane menu (`Prefix m`)
2. `tmux.bash`: Aliases (`tw-claude`, `tw-opencode`, etc.)

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

For shell script changes:
```bash
shellcheck install.sh uninstall.sh update.sh scripts/*.sh
```
