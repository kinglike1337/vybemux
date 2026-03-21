# vybemux

A tmux configuration optimized for AI-assisted coding with Claude Code and OpenCode.
Designed for Code-Server (coder/code-server) environments, also works via SSH.

## Features

- **Tokyo Night** color scheme
- **Clickable status bar** with [+] menu button, shortened path, git branch, hostname, and date
- **AI tool integration**: Launch Claude Code and OpenCode directly from tmux menus and aliases (resume/continue/new)
- **Session persistence**: tmux-resurrect + tmux-continuum (auto-save every 15 minutes, auto-restart Claude/OpenCode after reboot)
- **Auto-attach**: New Code-Server terminals automatically attach to a workspace-based tmux session
- **Mouse support**: Clickable menus, pane resize, copy mode
- **Vi-keybindings**: Copy mode with vi keys
- **Offline installation**: All plugins bundled as git submodules

## Requirements

- tmux >= 3.2 (tested with 3.5a)
- bash
- git

## Installation

```bash
git clone --recurse-submodules <repo-url>
cd vybemux
./install.sh
```

Replace `<repo-url>` with the URL of this repository, for example:

- SSH: `ssh://git@github.com/username/vybemux.git`
- HTTPS: `https://github.com/username/vybemux.git`

After installation, add this to `~/.bashrc` (after the interactive shell check, **before** tools like SDKMAN that require end-of-file placement):

```bash
[ -f ~/.tmux.bash ] && . ~/.tmux.bash
```

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

Comment out or remove the `exec tmux new-session -A -s ...` line in `tmux.bash`, or adjust the `TERM_PROGRAM` condition.

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
