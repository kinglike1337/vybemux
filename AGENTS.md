# AGENTS.md

This file provides guidance for agentic coding assistants working in this repository.

## Project Overview

vybemux is a tmux configuration optimized for AI-assisted coding (Claude Code/OpenCode). tmux runs on a remote host reached via SSH; Ghostty is the local terminal client.

**Key Design Decision:** Plugins are bundled as git submodules (not fetched dynamically via TPM) to enable offline installation and reproducible deployments.

## Language Policy

English is the only language for maintained first-party project content.

- **MUST** use English whenever the project controls the wording or name of a
  new or modified element. This includes user-visible labels, messages, prompts,
  help text, documentation, agent instructions, code identifiers, comments,
  section headings, test names, test descriptions, fixtures, configuration
  descriptions, filenames, paths, branch names, commit messages, PRs, issues,
  reviews, workflow labels, and release notes.
- **MUST** translate non-English first-party text that is directly edited, plus
  nearby text needed to keep the result coherent. Untouched legacy content may
  wait for its migration phase. Editing an existing identifier's behavior does
  not require renaming it; new or intentionally renamed identifiers must be
  English.
- **MUST NOT** copy non-English legacy wording or names into new content, extend
  them with more non-English content, or use them as the pattern for new work.
- Existing historical records, including commits, merged PRs, closed issues, and
  published releases, **MUST NOT** be rewritten solely to translate them.
- Verbatim externally defined technical terms, proper names, externally authored
  quotations, and generated output whose wording the project cannot control are
  exempt. Project-controlled templates, generator configuration, metadata,
  identifiers, commands, filenames, paths, and surrounding text are not exempt.
- External submodules are outside this policy. All first-party references to
  them must still be English.
- Submit every migration change through a dedicated PR linked to
  the internal Gitea issue #26,
  which tracks the phased cleanup of untouched legacy content. Do not combine
  separate migration phases in one PR.

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

### Renovate-Managed Updates
`renovate.json` keeps the 5 submodules, CI Actions, and third-party
pre-commit hooks current via scheduled PRs (Mon before 6am, Europe/Berlin)
— there is no update script; merge the PRs Renovate opens instead of bumping
things by hand.

**Submodules** — two different tracking modes, matching how each
submodule is meant to move:
- **The 4 tmux plugins** (`plugins/tpm`, `plugins/tmux-resurrect`,
  `plugins/tmux-continuum`, `plugins/tmux-yank`): branch-head tracking,
  no `branch =` set in `.gitmodules`, so Renovate follows each plugin's
  default branch tip and bundles all 4 into one grouped PR (see the
  `packageRules` entry in `renovate.json`, scoped to these 4 submodules via
  `matchDepNames` — not `matchFileNames`, which matches the packageFile
  path (`.gitmodules`) rather than the submodule name and would silently
  match nothing here). Deliberately *not* tag-pinned like `bats-core`
  below: these upstreams barely tag releases (`tmux-continuum`'s last
  tag is from 2015 despite commits landing as late as 2024; the others
  are 1-3+ years stale), so tag-tracking would freeze Renovate on an
  ancient release instead of surfacing real updates.
- **`test/bats-core`**: tag tracking. `.gitmodules` pins it with
  `branch = v1.14.0` — pointing Renovate's `branch` field at a tag
  instead of a real branch makes it propose updates only to newer tags
  (via Renovate's default `git` versioning), not to `master`'s HEAD.
  This is deliberate: bats-core is a test-runner dependency that should
  move by reviewed release, not by arbitrary upstream commit, and it's
  excluded from the "tmux plugin submodules" group so it always gets its
  own PR. To bump it manually anyway (e.g. between Renovate runs):
  ```bash
  cd test/bats-core && git fetch --tags && git checkout <new-tag> && cd ../..
  git add test/bats-core .gitmodules   # also update the branch = pin
  git commit -m "test: bump bats-core to <new-tag>"
  ```
  Update the `branch = <tag>` line in `.gitmodules` to match, or Renovate
  will keep proposing the same jump back to the old pin's successor.

**GitHub Actions** — `actions/checkout` (the only third-party Action used,
in `.gitea/workflows/ci.yml` and `release.yml`) is pinned to a commit
digest, not a mutable tag, via a `pinDigests: true` packageRule
(supply-chain hardening: a tag can be moved to point at different code
after the fact, a commit SHA can't — same pattern already used in
`ci-images`). Renovate rewrites `actions/checkout@v7` to
`actions/checkout@<sha> # v7.x.y` and keeps the digest current from
there; don't hand-edit those `uses:` lines to a bare tag again.

**Pre-commit hooks** — external hook repositories in
`.pre-commit-config.yaml` are pinned to immutable commit SHAs with the
corresponding release tag retained as a `# frozen: vX.Y.Z` comment. Renovate's
opt-in `pre-commit` manager updates the tag and SHA together; do not replace a
frozen revision with a mutable tag. For a manual update, run
`pre-commit autoupdate --freeze`; plain `pre-commit autoupdate` replaces frozen
SHAs with mutable tags and must not be used.

### Versioning & Releases
`VERSION` at the repo root holds the current SemVer string (e.g. `1.2.3`);
`install.sh` copies it to `~/.tmux/VERSION` and `--status` shows both the
repo and installed value, warning if they differ (i.e. the repo has moved
on since the last `./install.sh`). It also freezes `git describe --tags
--always` into `~/.tmux/VERSION_GIT` at install time, so `--status` and
the About popup (`scripts/about.sh`, key `i`) can show a "dev" suffix
(`0.0.1 (dev: v0.0.1-5-gd1b1c3b)`) distinguishing "same released version,
but N commits landed since the last install" from an actual stale
install — the bare `VERSION` string alone can't tell those apart between
releases. Prepare the next patch, minor, or major version on a dedicated
release branch, using `1.0.0` as an example:
```bash
git switch -c release/v1.0.0
printf '1.0.0\n' > VERSION
git add VERSION
git commit -m 'chore(release): bump version to v1.0.0'
git push -u origin release/v1.0.0
tea pr create --base main --head release/v1.0.0 \
  --title 'chore(release): bump version to v1.0.0'
```
The release-branch commit subject must be exactly
`chore(release): bump version to vX.Y.Z`. The pull request must pass CI and be
merged into `main` before dispatching the manual `Release` Gitea Actions
workflow (`.gitea/workflows/release.yml`). Normal, rebase, and Gitea squash
merges are supported:
```bash
tea actions workflows dispatch release.yml --ref main --input version=1.0.0 --follow
# or: trigger it from the Gitea web UI (Actions tab)
```
The workflow never writes `main`. It runs the complete pre-commit and unit-test
gates, validates the version-bump commit already merged into `main`, tags the
checked-out `main` commit as `vX.Y.Z`, and creates a Gitea Release whose notes
are the non-merge commit messages since the previous tag. If the tag already
exists, its commit remains the release target so a resumed run cannot move the
release. The attached
`vybemux-vX.Y.Z.tar.gz` and checksum include all recursively checked-out
submodules; Gitea's generated source archives do not. Re-dispatching the same
target safely resumes a run that already created its tag or release assets.
Never create a `vX.Y.Z` tag by hand; let the workflow keep the tag, archive,
checksum, and release notes consistent.

### Uninstallation
```bash
./uninstall.sh    # Removes installed files/backups; preserves ~/.tmux.conf.local
```

### tmux Operations
```bash
# Reload configuration after changes
tmux source-file ~/.tmux.conf

# Validate configuration syntax
./scripts/validate-tmux-conf.sh tmux.conf
```

`tmux -f conf start-server \; kill-server` looks like a syntax check but is
not one: with no session attached, the server exits before a config error can
surface, so it returns 0 even for a nonexistent command. Use
`scripts/validate-tmux-conf.sh` instead, which sources the config against a
running isolated server (`source-file`) and reports the real error.

## Architecture

### Core Structure
```
vybemux/
├── tmux.conf          # Main tmux configuration (color, bindings, menus)
├── tmux.bash          # Bash integration (aliases, functions)
├── install.sh         # Installer (single mode) + --status/--help
├── uninstall.sh       # Uninstaller; preserves the personal override file
├── LICENSE            # MIT license for maintained first-party content
├── VERSION            # Current SemVer string; bumped through a release pull request
├── renovate.json      # Keeps submodules, CI actions, and pre-commit hooks current via PRs
├── scripts/           # Runtime, status-bar, and release helper scripts
│   ├── shorten-path.sh
│   ├── sessions.sh        # all-sessions list for status-left (current highlighted)
│   ├── ai-tools-menu.sh   # "AI Tools" submenu: only installed agents get an entry
│   ├── about.sh           # "About" popup: vybemux + plugin versions and origin URLs
│   ├── harden-resurrect-permissions.sh # restricts saved layouts/pane contents to the current user
│   ├── build-release-archive.sh # deterministic archive with recursive submodules
│   ├── prepare-release.sh # validates new and resumable target-version state
│   └── publish-gitea-release.sh # idempotent release/asset publication
├── plugins/           # Git submodules (not dynamically fetched)
│   ├── tpm/           # tmux Plugin Manager (orchestrates other plugins)
│   ├── tmux-resurrect/    # Session save/restore
│   ├── tmux-continuum/    # Auto-save (every 15 min)
│   └── tmux-yank/         # Clipboard integration
└── test/              # bats-core unit tests + bats-core submodule
    ├── bats-core/         # Git submodule (test runner, not a runtime plugin)
    ├── shorten_path.bats
    ├── resurrect_claude_hook.bats
    ├── resurrect_permissions.bats
    ├── sessions.bats
    ├── tui_tab.bats
    ├── ai_tools_menu.bats
    ├── install.bats
    ├── publish_release.bats
    ├── release_archive.bats
    ├── release_version.bats
    ├── release_workflow.bats
    ├── tmux_bash_functions.bats
    ├── validate_tmux_conf.bats
    └── sync_mirror.bats
```

### Clipboard Architecture (Important)

tmux runs remotely over SSH, so vybemux relies on OSC 52 rather than X11 clipboard tools:

1. **OSC 52 passthrough**: `set-clipboard on` + `allow-passthrough on` enables nested OSC 52 (vim → tmux → Ghostty)
2. **tmux-yank**: `@custom_copy_command` forces OSC 52 so yanks reach the local clipboard without X11 tools
3. **Mouse selection**: Mouse is always on (clickable menus, pane resize, copy mode); hold Shift while dragging for Ghostty's native text selection

**Mouse Toggle:** `Ctrl+a Ctrl+t` (toggles between tmux mouse mode and Ghostty native selection)

### Status Bar Components

The status bar uses clickable menus and displays:
- All sessions (left; current shown as an accent badge, others muted; clickable → session menu)
- Windows list (clickable to switch)
- `[+]` button (right, clickable → quick actions)
- `[+]` menu and `Prefix+m` include a "Cheat-Sheet" entry (key `?`) that opens a `display-popup` reference of all shortcuts (`scripts/cheatsheet.sh`)
- `[+]` menu and `Prefix+m` also include an "About" entry (key `i`) showing
  vybemux's version plus each bundled plugin's version and origin URL
  (`scripts/about.sh`) — kept separate from the Cheat-Sheet since it's
  version/install info, not a shortcut reference
- Shortened path, git branch, hostname, date

## Public Mirror

`sync-mirror.sh` copies a filtered snapshot of this repository into a separate
mirror clone (default `~/projects/vybemux-github`, override with
`VYBEMUX_MIRROR_DIR`) and commits it there. Never push this repository itself
to a public remote: its history contains the maintainer's real email address
and internal hostnames.

- The mirror clone must use a noreply commit identity
  (`<id>+<user>@users.noreply.github.com`); set it repo-locally before the
  first sync.
- Do not force-push or rewrite the mirror's history after it has been
  published.
- The script aborts if a mirrored file mentions an internal hostname or
  address (`INTERNAL_REFS_PATTERN`) and leaves merge commits and subjects
  naming such hosts out of the sync commit message. Genericize the wording
  in the source instead of bypassing the check.

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

**WSL2 + Windows Terminal:** the chain above is Ghostty-specific. Windows
Terminal sends Shift+Enter identical to Enter, so add `sendInput` actions
binding `shift+enter` (and optionally `alt+enter`) to `"\n"` in Windows
Terminal's `settings.json`. `/terminal-setup` only configures the VS Code
terminal. See the "WSL2 + Windows Terminal" section in `README.md`.

## Key Files

| File | Purpose |
|------|---------|
| `tmux.conf` | All tmux settings: colors, bindings, menus, plugin config |
| `tmux.bash` | Aliases, tmux-dev/project functions |
| `install.sh` | Validation, backup, file copying |
| `scripts/shorten-path.sh` | Path shortening for status bar (e.g., `~/p/vybemux`) |
| `scripts/sessions.sh` | All-sessions list for status-left (current highlighted) |
| `scripts/ai-tools-menu.sh` | Builds the "AI Tools" submenu (Quick Actions + `Prefix m`) with entries only for tools present on `$PATH` |
| `scripts/about.sh` | "About" popup (Quick Actions + `Prefix m`, key `i`): vybemux version plus each plugin's version/origin URL |
| `scripts/resurrect-claude-hook.sh` | `@resurrect-hook-post-save-layout`: rewrites saved `claude` panes to `claude --resume <sessionId>` (picker-less restore) using `~/.claude/sessions/<PID>.json` (also scanned under `~/.claude*/sessions` for alternate `CLAUDE_CONFIG_DIR` profiles); also unsets the full `ANTHROPIC_*`/`CLAUDE_CODE_*`/`CLAUDE_CONFIG_DIR` namespace in the restored pane's shell and re-prepends only the resolved process's own allowlisted vars from that namespace, so a non-default provider/model is restored too and a variable the process deliberately did *not* have set can't leak back in from that shell's own startup files (e.g. a global default exported in `~/.bashrc`) |
| `scripts/harden-resurrect-permissions.sh` | `@resurrect-hook-post-save-all`: applies private permissions to the active tmux-resurrect directory and its known layout/pane-content artifacts without changing unrelated files; follows the plugin's legacy, XDG, and explicit `@resurrect-dir` path selection |
| `scripts/validate-tmux-conf.sh` | tmux.conf syntax check via `source-file` against an isolated server; used by pre-commit and CI |

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

## Configuration Patterns

### Adding AI Tool Commands
Currently supported: Claude Code, OpenCode, Codex, Pi. A new tool touches
three places (must be updated in sync):
1. `scripts/ai-tools-menu.sh`: add a `command -v <tool>` block appending its
   menu items (resume/continue/new, whichever the tool supports) to the
   `items` array. The Quick Actions menu (`MouseUp1StatusRight`) and the
   Window/Pane menu (`Prefix m`) both call this one script via their "AI
   Tools" submenu entry, so a tool not on `$PATH` simply gets no entry
   instead of a dead/greyed-out one — this replaced two duplicated inline
   `display-menu` blocks that always listed every tool regardless of
   whether it was installed.
2. `tmux.bash`: Aliases (`tw-claude`, `tw-opencode`, `tw-codex`, `tw-pi`,
   etc.) and the `claude opencode codex pi` loop in `tmux-dev()`.
3. If the tool supports resuming its own last session by directory
   (verify empirically — see the comment above `@resurrect-processes` in
   `tmux.conf`), add a `"tool->tool <continue-flag>"` entry there so
   `tmux-resurrect` restores it. Prefer the non-tilde anchored form
   (`"tool->..."`) over the tilde substring form (`"~tool->..."`) unless
   you've confirmed the saved process name can't collide with an unrelated
   command's substring (e.g. a `~pi` pattern would misfire on `pip
   install`).

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
./scripts/validate-tmux-conf.sh tmux.conf

# Reload in active session
Press Ctrl+a, then r
```

For shell script changes:
```bash
shellcheck --shell=bash install.sh uninstall.sh sync-mirror.sh scripts/*.sh tmux.bash
```

Plugin tests live in the `plugins/` submodules and are run from their own
directories.

### Unit tests (bats-core)

`test/*.bats` covers scripts with non-trivial logic —
`scripts/resurrect-claude-hook.sh` (proc/PID matching, session-index
resolution, picker fallback), `scripts/harden-resurrect-permissions.sh`,
`scripts/shorten-path.sh`, `scripts/sessions.sh`,
`scripts/tui-tab.sh`, `scripts/ai-tools-menu.sh`, `scripts/validate-tmux-conf.sh`,
the release preparation/archive/publication helpers, installer safety,
the `tmux-dev`/`tmux-project` functions in `tmux.bash`, and the guard conditions
of `sync-mirror.sh` — using
[bats-core](https://github.com/bats-core/bats-core), bundled as a git
submodule at `test/bats-core` (same offline/reproducible-install pattern as
`plugins/`), pinned to a release tag (currently `v1.14.0`) rather than a
branch and bumped via Renovate PR — see "Plugin Submodule Updates
(Renovate)" above for how the tag pin works and how to bump it by hand.

```bash
test/bats-core/bin/bats test/    # run all unit tests
```

Requires `jq` on PATH (the hook's dependency; tests exercise both the
present and missing case). Runs in the `unit-tests` job of Gitea CI
(`.gitea/workflows/ci.yml`).

**tmux mocking, except one file.** Every test that exercises a
tmux-calling script mocks `tmux` via a PATH stub written per-file (never a
shared `setup()`) — except `validate_tmux_conf.bats`, which needs the
*real* binary because the script under test verifies a real `source-file`
error message; that's why the `unit-tests` CI job installs tmux even
though most tests don't need it. Locally without tmux installed, those 5
tests `skip` rather than fail — a green local run isn't proof they ran.
Adding a test for a tmux-calling script: copy the stub pattern from an
existing `*.bats` file, don't hoist it into a helper.

**Scripts that resolve their own directory via `BASH_SOURCE`**
(`sync-mirror.sh`'s `MAIN_REPO`) can't be tested by overriding `HOME`
or `cd`-ing elsewhere — the script's source-side path stays the real repo
either way. Copy the script into a fixture directory and run it from there
(see `test/sync_mirror.bats`).

**`sync-mirror.sh` is covered for guard conditions only**
(not-a-git-repo, dirty working tree, missing/invalid target, the
sensitive-data prompt) plus one non-interactive happy path. The
network/interactive core — the `git commit -e` editor path, any real
`push` — is deliberately out of scope: faking it costs more than it's
worth, and `install-smoke-test` already covers submodule correctness
end-to-end.

`scripts/cheatsheet.sh` and `scripts/about.sh` have no bats test: both are
read-only display scripts (static shortcut text; version/plugin info read
from `~/.tmux/VERSION` and each plugin's git metadata) with no state to
change and no interesting failure mode beyond "value missing, line
omitted" — verified manually (with and without the files/plugins present)
rather than adding fixture-heavy git-repo test scaffolding for it.

### Local CI (pre-commit)

`.pre-commit-config.yaml` runs shellcheck, the tmux.conf syntax check, mdl,
and yamllint locally; the same command runs in the `pre-commit` job of Gitea
CI (`.gitea/workflows/ci.yml`), so a passing local run predicts a passing
`pre-commit` job. `.bats` files aren't matched by any hook (no linter
configured for them), and unit tests aren't part of this job — run them
separately as shown above.

```bash
pre-commit install         # once, installs the git hook
pre-commit run --all-files # run everything on demand
```

CI also runs a separate `install-smoke-test` job that `pre-commit` does not
cover: `install.sh`/`uninstall.sh` end-to-end (including the backup path on a
second install) plus a real isolated tmux server (`tmux -L`) started with the
installed config, asserting TPM's plugin autostart actually completed. There
is no local equivalent for that job; it only runs in CI.

## Important Notes

- **Plugins**: Never modify plugin submodules directly; merge the Renovate PR
- **Installation**: single mode (`./install.sh`); no auto-activation, start tmux via aliases
