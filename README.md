# vybemux

A tmux configuration optimized for AI-assisted coding with Claude Code, OpenCode, Codex, and Pi.
tmux runs on a remote host reached via SSH; [Ghostty](https://ghostty.org) is the
local terminal client.

## Features

- **Tokyo Night** color scheme
- **Clickable status bar** with [+] menu button, shortened path, git branch, hostname, and date
- **AI tool integration**: Launch Claude Code, OpenCode, Codex, or Pi directly from tmux menus and aliases (resume/continue/new); the "AI Tools" menu only lists tools actually installed on the host
- **Session persistence**: tmux-resurrect + tmux-continuum (auto-save every
  15 minutes, auto-restart installed AI tools after reboot); saved layouts and
  captured pane contents are restricted to the current user
- **Mouse support**: Clickable menus, pane resize, copy mode
- **Vi-keybindings**: Copy mode with vi keys
- **Offline installation**: All plugins bundled as git submodules

## Ghostty (client setup)

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

## Claude Code compatibility

The Kitty keyboard protocol (`extended-keys always`) is enabled so Claude Code
running inside tmux can see Shift+Enter as a newline instead of a submit.

### WSL2 + Windows Terminal

The Kitty keyboard protocol chain above is Ghostty-specific. Windows Terminal
sends Shift+Enter byte-identical to Enter (`\r`), so the distinction is lost
before tmux ever sees it — no tmux setting can recover it. Bind the keys in
Windows Terminal's `settings.json` (Settings → Open JSON file) to send a
newline instead, equivalent to Ctrl+J:

```json
{ "command": { "action": "sendInput", "input": "\n" }, "keys": "shift+enter" },
{ "command": { "action": "sendInput", "input": "\n" }, "keys": "alt+enter" }
```

`alt+enter` overrides Windows Terminal's default `toggleFullscreen`. Claude
Code's `/terminal-setup` does not help here — it only configures the VS Code
integrated terminal, not Windows Terminal.

Terminal-independent fallbacks that work in any terminal without setup:
press **Ctrl+J**, or type `\` then Enter.

Ghostty click handling can need 2-3 presses to register on the status bar or
in a pane; vybemux works around this by binding menu clicks and pane
selection to mouse-up instead of mouse-down. If you still see stray clicks,
hold **Shift** while dragging to use Ghostty's native text selection instead
of tmux mouse mode.

## Clipboard Integration

tmux runs on a remote host over SSH, so vybemux relies on **OSC 52** rather than
X11/Wayland clipboard tools on the remote side.

### OSC 52 Support

The configuration enables OSC 52 — a terminal escape sequence that lets tmux and
applications (vim/neovim) copy directly to the local clipboard through the SSH
connection:

- `set-clipboard on` — enables OSC 52 clipboard passthrough
- `allow-passthrough on` — allows nested OSC 52 sequences (e.g., vim inside tmux inside Ghostty)
- `tmux-yank`'s `@custom_copy_command` forces OSC 52 so yanks always reach the local clipboard, without needing `xsel`/`xclip` on the remote host

Ghostty supports OSC 52 writes natively, so no client-side configuration is
needed beyond the SSH integration described in [Ghostty (client setup)](#ghostty-client-setup).

### Mouse Support

Mouse is always on: clickable status-bar menus, click-to-select panes, pane
resize, and copy mode with mouse drag. Toggle with `Ctrl+a Ctrl+t` if you need
to test with mouse mode off.

For Ghostty's native text selection (outside of tmux copy mode), hold **Shift**
while dragging.

**Using tmux copy mode:**
1. Enter copy mode: `Ctrl+a [`
2. Select text: `v` (vi) or mouse drag
3. Yank: `y`
4. Paste with Ctrl+V

### Troubleshooting

If clipboard doesn't work:
1. Confirm `shell-integration-features = ssh-env,ssh-terminfo` is set in `~/.config/ghostty/config`
2. Confirm `set -g set-clipboard on` and `set -g allow-passthrough on` are active (`tmux show -g`)
3. Terminal multiplexers nested over multiple SSH hops can block OSC 52 passthrough — check each hop supports it

## Requirements

- Linux on the remote host
- tmux >= 3.2 (tested with 3.5a)
- bash
- git
- jq (required for picker-free Claude Code resume; without it, restore falls
  back to the interactive session picker)
- Local client machine: [Ghostty](https://ghostty.org) with SSH shell-integration enabled (see [Ghostty (client setup)](#ghostty-client-setup))

## Installation

### From Git

```bash
git clone --recurse-submodules <repo-url>
cd vybemux
./install.sh
```

Replace `<repo-url>` with the URL of this repository, for example:

- SSH: `ssh://git@github.com/kinglike1337/vybemux.git`
- HTTPS: `https://github.com/kinglike1337/vybemux.git`

### From a Release

Download the attached `vybemux-vX.Y.Z.tar.gz` asset from the release page,
extract it, and run `./install.sh` inside it. Do not use Gitea's automatically
generated "Source Code" archives: Git host archives contain empty submodule
directories, while the attached vybemux archive includes every bundled plugin
and the bats-core test runner.

```bash
./install.sh --status          # Shows current installation status
./install.sh --help            # Shows all options
```

After installation, add this to `~/.bashrc` (after the interactive shell check):

```bash
[ -f ~/.tmux.bash ] && . ~/.tmux.bash
```

tmux-resurrect stores data in an existing `~/.tmux/resurrect` directory, or
otherwise in `${XDG_DATA_HOME:-~/.local/share}/tmux/resurrect`. Installation
and every completed save restrict known layout and pane-content artifacts to
the current user. If `@resurrect-dir` points elsewhere and tmux is stopped
during installation, harden existing data once with:

```bash
~/.tmux/scripts/harden-resurrect-permissions.sh /path/to/resurrect
```

Set `@vybemux-resurrect-hook-post-save-all` in `~/.tmux.conf.local` to chain a
custom command after permission hardening. On the first upgrade, an existing
native `@resurrect-hook-post-save-all` value is preserved automatically.

### Check Installation Status

To check the current installation status:

```bash
cd vybemux
./install.sh --status
```

This will show:
- Installation status (files, plugins)
- Source line status in `~/.bashrc`
- tmux version and plugin status

**Example output:**
```
============================================================================
vybemux Installation Status
============================================================================

[SUCCESS] tmux config found: ~/.tmux.conf
[SUCCESS] tmux.bash found: ~/.tmux.bash
[SUCCESS] Plugins directory found: ~/.tmux/plugins
[SUCCESS] Source line found in ~/.bashrc

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

To remove the installed vybemux files from your system:

```bash
cd vybemux
./uninstall.sh
```

The uninstall script will:
- Remove `~/.tmux.conf`
- Remove `~/.tmux.bash`
- Remove `~/.tmux/` directory
- Remove vybemux source line from `~/.bashrc`
- Optionally remove `~/.vybemux-backup/` directory
- Backup your `.bashrc` before modification

The personal `~/.tmux.conf.local` override remains in place so uninstalling or
reinstalling vybemux never deletes user-authored customizations. Remove that
file manually if it is no longer needed.

**Note:** After uninstall, restart your shell or run `tmux kill-server` if tmux is still running.

## Cutting a Release

Releases use a protected two-phase sequence. First, create a dedicated release
branch that changes `VERSION` to the target SemVer and commit it with the exact
subject `chore(release): bump version to vX.Y.Z`. Open a pull request to
`main`, let CI pass, and merge it. Then dispatch the manual Release workflow
with the same version:

```bash
tea actions workflows dispatch release.yml --ref main --input version=1.0.0 --follow
```

The workflow validates the merged version-bump commit, tags the checked-out
`main` commit, and publishes the recursive-submodule archive and checksum
without writing to `main`. If the tag already exists, that tagged commit remains
the release target. Normal, rebase, and Gitea squash merges are supported. Do
not create release tags manually.

## Plugin Updates

The plugins are bundled as git submodules and kept current by
[Renovate](https://docs.renovatebot.com/) (`renovate.json`) instead of a
manual script — merge the PRs it opens:

- The 4 tmux plugins (`tpm`, `tmux-resurrect`, `tmux-continuum`,
  `tmux-yank`) are bundled into one grouped PR, following each plugin's
  default branch tip.
- `test/bats-core` (the test runner) is pinned to a release tag in
  `.gitmodules` and gets its own PR only when a newer tag is published.

To update without Renovate:

```bash
git submodule update --remote --merge -- plugins/tpm plugins/tmux-resurrect plugins/tmux-continuum plugins/tmux-yank
git add plugins/tpm plugins/tmux-resurrect plugins/tmux-continuum plugins/tmux-yank
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
| Ctrl+a &#124;           | Vertical split                 |
| Ctrl+a -            | Horizontal split               |
| Ctrl+a c            | New window                    |
| Ctrl+a m            | Window/Pane menu              |
| Ctrl+a M            | Session menu                  |
| Ctrl+a Ctrl+t       | Toggle mouse on/off           |
| Alt+h/j/k/l         | Pane navigation               |
| Shift+Left/Right    | Switch windows                |
| Ctrl+Shift+Left/Right | Move windows               |
| Click [+] button     | Quick actions (incl. "AI Tools" submenu) |
| Click session name   | Session menu                  |
| [+] or Prefix+m, then ? | Show keyboard shortcut reference (cheat-sheet popup) |
| [+] or Prefix+m, then i | Show About popup (vybemux + plugin versions and origin URLs) |

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
| tw-codex          | Codex (resume last)           |
| tw-codex-new      | Codex (new)                   |
| tw-pi             | Pi (continue)                 |
| tw-pi-new         | Pi (new)                      |
| tw-shell          | New shell window              |
| tmux-dev [name]   | Dev session (shell + one window per installed AI tool) |
| tmux-project <p>  | Project session in custom project directory |

## Configuration

### Customize AI Tools

The "AI Tools" submenu (Quick Actions and `Prefix m`) is generated by
`scripts/ai-tools-menu.sh`, which only lists a tool if it's found on
`$PATH` — add a new tool there (plus the aliases and `tmux-dev()` loop in
`tmux.bash`).

### Starting tmux

vybemux does not start tmux automatically; use the provided aliases:

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

The 4 plugins are bundled as submodules under `plugins/`. Their exact commits
are recorded by the repository's gitlinks and displayed by `./install.sh
--status` after installation.

| Submodule | Source |
|---|---|
| `plugins/tpm` | `https://github.com/tmux-plugins/tpm` |
| `plugins/tmux-resurrect` | `https://github.com/tmux-plugins/tmux-resurrect` |
| `plugins/tmux-continuum` | `https://github.com/tmux-plugins/tmux-continuum` |
| `plugins/tmux-yank` | `https://github.com/tmux-plugins/tmux-yank` |

## License

vybemux's first-party content is licensed under the [MIT License](LICENSE).
Bundled submodules retain their respective upstream licenses.
