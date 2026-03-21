# vybemux

A tmux configuration optimized for AI-assisted coding with Claude Code and OpenCode.
Designed for Code-Server (coder/code-server) environments, also works via SSH.

## Features

- **Tokyo Night** color scheme
- **Clickable status bar** with [+] menu button, shortened path, git branch, hostname, and date
- **AI tool integration**: Launch Claude Code and OpenCode directly from tmux menus and aliases (resume/continue/new)
- **Session persistence**: tmux-resurrect + tmux-continuum (auto-save every 15 minutes, auto-restart Claude/OpenCode after reboot)
- **Flexible installation modes**: Auto-attach, VS Code profile, or manual activation
- **Mouse support**: Clickable menus, pane resize, copy mode
- **Vi-keybindings**: Copy mode with vi keys
- **Offline installation**: All plugins bundled as git submodules

## Clipboard Integration

vybemux is optimized for **Code-Server environments** where traditional X11/Wayland clipboard tools (xsel/xclip) may not be available.

### OSC 52 Support

The configuration enables **OSC 52** — a terminal escape sequence that allows tmux and applications (vim/neovim) to copy directly to the browser/VS Code clipboard without X11:

- `set-clipboard on` — enables OSC 52 clipboard passthrough
- `allow-passthrough on` — allows nested OSC 52 sequences (e.g., vim inside tmux inside xterm.js)
- `tmux-yank fallback` — configured with OSC 52 as fallback when no clipboard tools available

**How it works:**
- **SSH with X11:** Uses `xsel`/`xclip` if installed (preferred)
- **Code-Server:** Falls back to OSC 52 (works in browser terminals)
- **macOS:** Uses `pbcopy` if available

### Code-Server Mouse Support

**Important:** Mouse support is **disabled** in Code-Server environments to enable native xterm.js selection and prevent the "0/0" selection indicator issue.

This means:
- **Code-Server:** Use native browser selection (drag with mouse, copy via context menu or Ctrl+C)
- **SSH:** Full tmux mouse support enabled (pane resize, window switching, copy mode with mouse)

To enable mouse support in Code-Server (not recommended, breaks native selection):
```bash
Ctrl+a Ctrl+t
```
Or permanently in `tmux.conf`:
```bash
set -g mouse on
```

### Manual Testing

Run the clipboard test script:
```bash
bash ~/.tmux/scripts/test-clipboard.sh
```

**For Code-Server:**
1. Use native mouse selection (drag to select)
2. Copy with context menu or Ctrl+C
3. Paste with Ctrl+V

**For SSH or with mouse enabled:**
1. Enter copy mode: `Ctrl+a [`
2. Select text: `v` (vi) or mouse drag
3. Yank: `y`
4. Paste with Ctrl+V

### Troubleshooting

If clipboard doesn't work:
1. Run the test script to verify configuration
2. For SSH access, install `xsel` or `xclip` for native X11 clipboard support: `sudo apt install xsel`
3. Check VS Code settings: `"terminal.integrated.allowClipboardOperations": true` (default: true)
4. If you see "0/0" selection indicator in Code-Server, mouse support may be enabled — disable it with `Ctrl+a Ctrl+t`

**How it works:**
- **macOS:** Uses `pbcopy` if available
- **WSL:** Uses `clip.exe` automatically (Windows clipboard integration)
- **Linux X11:** Uses `xsel`/`xclip` if installed (preferred)
- **Linux Wayland:** Uses `wl-copy` if installed
- **Code-Server:** Falls back to OSC 52 (works in browser terminals)

## Requirements

- tmux >= 3.2 (tested with 3.5a)
- bash
- git

## Installation

```bash
git clone --recurse-submodules <repo-url>
cd vybemux
./install.sh --mode=<mode>
```

Replace `<repo-url>` with the URL of this repository, for example:

- SSH: `ssh://git@github.com/username/vybemux.git`
- HTTPS: `https://github.com/username/vybemux.git`

### Installation Modes

Choose one of the following modes:

| Mode | Auto-Attach | VS Code Profile | Description |
|------|-------------|-----------------|-------------|
| `auto` | ✅ | ❌ | VS Code terminals automatically start tmux (default behavior) |
| `profile` | ❌ | ✅ vybemux | tmux can be selected from VS Code terminal menu |
| `manual` | ❌ | ❌ | Only aliases, no auto-activation |

**Examples:**

```bash
./install.sh --mode=auto      # Auto-attach active (default behavior)
./install.sh --mode=profile    # VS Code vybemux profile
./install.sh --mode=manual     # Aliases only, manual tmux start
./install.sh --status          # Shows current installation status
./install.sh --help            # Shows all options
```

After installation, add this to `~/.bashrc` (after the interactive shell check, **before** tools like SDKMAN that require end-of-file placement):

```bash
[ -f ~/.tmux.bash ] && . ~/.tmux.bash
```

### Check Installation Status

To check the current installation status and mode:

```bash
cd vybemux
./install.sh --status
```

This will show:
- Installation status (files, plugins)
- Configuration mode (auto/profile/manual)
- Auto-Attach status
- VS Code vybemux profile status
- tmux version and plugin status

**Example output:**
```
============================================================================
vybemux Installation Status
============================================================================

[SUCCESS] tmux config found: ~/.tmux.conf
[SUCCESS] tmux.bash found: ~/.tmux.bash
[SUCCESS] Plugins directory found: ~/.tmux/plugins

--- Configuration Mode ---
[WARNING] Auto-Attach: Disabled
[SUCCESS] VS Code vybemux profile: Installed

--- Inferred Mode ---
[INFO] Mode: profile

--- tmux Information ---
[INFO] tmux version: 3.5a
[SUCCESS] TPM plugin: installed
[SUCCESS] tmux-resurrect plugin: installed
[SUCCESS] tmux-continuum plugin: installed
[SUCCESS] tmux-yank plugin: installed

============================================================================
[SUCCESS] vybemux is installed
============================================================================
```

## Uninstallation

To completely remove vybemux from your system:

```bash
cd vybemux
./uninstall.sh
```

The uninstall script will:
- Remove `~/.tmux.conf`
- Remove `~/.tmux.bash`
- Remove `~/.tmux/` directory
- Remove vybemux source line from `~/.bashrc`
- Remove `vybemux` profile from VS Code settings.json (if installed with `--mode=profile`)
- Optionally remove `~/.vybemux-backup/` directory
- Backup your `.bashrc` before modification

**Note:** After uninstall, restart your shell or run `tmux kill-server` if tmux is still running.

## Plugin Updates

The plugins are bundled as git submodules and can be updated:

```bash
cd vybemux
./update.sh
```

The script:
- Fetches the latest commits from all 4 plugins
- Merges the updates
- Shows which commits were pulled
- Updates `.gitmodules` (automatically staged)

Then commit and push:

```bash
git commit -m 'Update submodules'
git push
```

## Usage

### Status Bar

```
┌─ Session ──── Windows ──────────────── [+] Path | Branch | Host | Date ─┐
│ myproject  1:shell* 2:claude 3:opencode  + ~/p/myproject | main | host | … │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Keybindings

| Keybinding          | Action                        |
|---------------------|-------------------------------|
| Ctrl+a              | Prefix                        |
| Ctrl+a r            | Reload configuration           |
| Ctrl+a \|           | Vertical split                 |
| Ctrl+a -            | Horizontal split               |
| Ctrl+a c            | New window                    |
| Ctrl+a m            | Window/Pane menu              |
| Ctrl+a M            | Session menu                  |
| Ctrl+a Ctrl+t       | Toggle mouse on/off           |
| Alt+h/j/k/l         | Pane navigation               |
| Shift+Left/Right    | Switch windows                |
| Ctrl+Shift+Left/Right | Move windows               |
| Click [+] button     | Quick actions (Claude, OpenCode) |
| Click session name   | Session menu                  |

### Aliases (after sourcing ~/.tmux.bash)

| Alias             | Action                        |
|-------------------|-------------------------------|
| ta <name>         | tmux attach                   |
| tl                | List sessions                 |
| tk <name>         | Kill session                 |
| tn <name>         | New session                   |
| tw-claude         | Claude Code (resume)          |
| tw-claude-cont    | Claude Code (continue)        |
| tw-claude-new     | Claude Code (new)             |
| tw-opencode        | OpenCode (continue)           |
| tw-opencode-new    | OpenCode (new)                |
| tw-shell          | New shell window              |
| tmux-dev [name]   | Dev session (shell+claude+opencode) |
| tmux-project <p>  | Project session in custom project directory |

## Configuration

### Customize AI Tools

Edit the menu entries in `tmux.conf` (6 `display-menu` blocks) and the aliases in `tmux.bash`.

### Disable Auto-Attach

Use `--mode=profile` or `--mode=manual` during installation to disable auto-attach.

Alternatively, you can manually comment out or remove the `exec tmux new-session -A -s ...` line in `tmux.bash`, or adjust the `TERM_PROGRAM` condition.

### VS Code Profile Mode

When installed with `--mode=profile`, a `vybemux` terminal profile is added to VS Code:

1. Click the `+` button in the VS Code terminal panel
2. Select `vybemux` from the profile dropdown
3. A new tmux session will be created (or attached) using the workspace name

**Benefits:**
- Default `bash` profile remains available
- tmux is only activated when explicitly needed
- Works seamlessly with existing terminal configurations

**Note:** This modifies `~/.local/share/code-server/User/settings.json` (or `~/.config/Code/User/settings.json` for VS Code Desktop). A backup is created in `~/.vybemux-backup/`.

### Manual Mode

With `--mode=manual`, vybemux installs tmux configuration and aliases without any auto-activation. Use the provided aliases to start tmux:

```bash
tn <session-name>    # Create new session
ta <session-name>    # Attach to existing session
tmux new-session     # Start tmux with default session
```

### Customize Theme

Modify the Tokyo Night colors in `tmux.conf` (under "Status Bar" section):
- #1a1b26 — Background (dark)
- #7aa2f7 — Accent (blue)
- #e0af68 — Button (gold)
- #a9b1d6 — Text (light)
- #565f89 — Text (muted)
- #3b4261 — Separator (dark)

### Customize Project Path

The `tmux-project` function uses a default project directory. Edit the `project_dir` line in `tmux.bash` to match your preferred location:

```bash
local project_dir="$HOME/projects/$project"
```

## Plugins

The 4 plugins are bundled as submodules under `plugins/`:

| Submodule       | Source                                           | Commit |
|---|---|---|
| `plugins/tpm`  | `https://github.com/tmux-plugins/tpm`          | `99469c4` |
| `plugins/tmux-resurrect` | `https://github.com/tmux-plugins/tmux-resurrect` | `cff343c` |
| `plugins/tmux-continuum` | `https://github.com/tmux-plugins/tmux-continuum` | `0698e8f` |
| `plugins/tmux-yank` | `https://github.com/tmux-plugins/tmux-yank` | `acfd36e` |

## License

MIT
