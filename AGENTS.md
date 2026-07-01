# AGENTS.md

This file provides guidance for agentic coding assistants working in this repository.

## Project Overview

vybemux is a tmux configuration optimized for AI-assisted coding (Claude Code/OpenCode). tmux runs on a remote host reached via SSH; Ghostty is the local terminal client. Plugins are bundled as git submodules for offline installation.

## Build/Lint/Test Commands

### Configuration Validation

```bash
# Validate tmux.conf syntax
tmux -f ~/.tmux.conf start-server \; kill-server

# Reload configuration in active session
# Press: Ctrl+a, then r
```

### Testing

```bash
# Lint shell scripts
shellcheck install.sh uninstall.sh update.sh scripts/*.sh

# Check installation status
./install.sh --status

# Run plugin tests (external submodules)
# Note: Plugin tests are in plugins/ submodules, run from their directories
```

### Plugin Management

```bash
# Update all submodules
./update.sh

# Commit submodule updates
git commit -m 'Update submodules'
git push

# Install/uninstall vybemux
./install.sh
./uninstall.sh
```

## Code Style Guidelines

### Shell Scripts

**Shebang and Headers:**
- Main scripts: `#!/bin/bash`
- Test scripts: `#!/usr/bin/env bash`
- Include double-hash separator: `# ============` with descriptive title
- Include set strict mode: `set -euo pipefail`

**Error Handling:**
- Always use `set -euo pipefail` for error propagation
- Redirect stderr to null for optional checks: `command >/dev/null 2>&1`

**Colors and Output:**
- Define standard color variables at top:
  ```bash
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
  ```
- Use consistent echo functions:
  - `echo_info()` - informational messages
  - `echo_success()` - success messages
  - `echo_error()` - error messages
  - `echo_warning()` - warnings

**Variables and Constants:**
- Constants: UPPER_CASE with underscores
- Local variables: lowercase_with_underscores
- Paths: Use absolute paths or `$HOME` explicitly, never `~` in scripts
- Default values: `${VAR:-default}` or `${VAR=default}`

**Functions:**
- Function names: lowercase_with_underscores
- Group related functions with section headers
- Use descriptive names: `echo_info()` not `info()`

**Quoting:**
- Always quote variables: `"$VAR"` not `$VAR`
- Use double quotes for strings with variables, single quotes for literal strings

**Conditionals:**
- Use `[[ ]]` for bash tests (not `[ ]`)
- String comparison: `[[ "$VAR" == "value" ]]`
- Integer comparison: `[[ $VAR -eq 5 ]]`
- Check command existence: `if command -v tmux &>/dev/null; then`

**Loops:**
- Use `for var in list; do` or `while condition; do`
- Always quote array elements with spaces

**Comments:**
- No inline comments unless explicitly requested
- Section headers with double-hash separators

### tmux Configuration (tmux.conf)

**Structure:**
- Organize into clear sections with double-hash separators
- Order: General Settings → Keybindings → Status Bar → Menus → Plugins
- Keep TPM initialization at the very bottom

**Style:**
- Use tmux syntax consistently
- Colors: Tokyo Night theme (hex codes)
- Keybindings: Group by purpose (pane, window, session)
- Comments: Section headers only

**Adding AI Tool Commands:**
Must update in sync across two files:
1. `tmux.conf`: the Quick Actions menu (`MouseUp1StatusRight`) and the Window/Pane menu (`Prefix m`)
2. `tmux.bash`: Aliases (`tw-claude`, `tw-opencode`, etc.)

### tmux Bash Integration (tmux.bash)

**Sourcing:**
- Contains only aliases and functions; no auto-activation logic
- Source in `~/.bashrc` after the interactive shell check

**Aliases:**
- Group related aliases with section headers
- Descriptive names: `tw-claude` (tmux-window-claude)

**Functions:**
- Use `local` for all function variables
- Validate required arguments: `local arg="${1:?Usage: func <arg>}"`

## File Organization

```
vybemux/
├── tmux.conf          # Main tmux configuration
├── tmux.bash          # Bash integration and aliases
├── install.sh         # Installer (single mode) + --status/--help
├── uninstall.sh       # Uninstaller
├── update.sh          # Submodule updates
├── scripts/           # Helper scripts (shorten-path)
└── plugins/           # Git submodules (tpm, tmux-resurrect, tmux-continuum, tmux-yank)
```

## Important Notes

- **Clipboard**: OSC 52 only (tmux runs remotely over SSH; no X11 tools on the remote host); Ghostty supports OSC 52 natively
- **Mouse**: Always on (`set -g mouse on`); Shift+drag gives Ghostty's native text selection
- **Plugins**: Never modify plugin submodules directly; use `./update.sh`
- **Installation**: single mode (`./install.sh`); no auto-activation, start tmux via aliases
- **Tokyo Night Colors**: Background #1a1b26, Accent #7aa2f7, Button #e0af68
