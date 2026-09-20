#!/bin/bash
# =============================================================================
# vybemux About
# Prints vybemux's own version plus each bundled plugin's version and origin
# URL. Shown via display-popup + less -R (see tmux.conf), same pattern as
# scripts/cheatsheet.sh. Kept separate from the Cheat-Sheet on purpose: that
# popup is a keyboard-shortcut reference, this is installation/version info.
# =============================================================================

# Tokyo Night colors (true-color ANSI; plain text on non-true-color terminals).
A='\033[1;38;2;122;161;247m'   # accent, bold  (title, section headers)
T='\033[38;2;169;177;214m'     # default text
M='\033[38;2;86;95;137m'       # muted         (hints, notes, URLs)
S='\033[38;2;59;66;97m'        # separator     (rules, blanks)
R='\033[0m'                    # reset

# ~/.tmux/plugins is a symlink to $REPO_DIR/plugins (see install.sh) --
# use it to resolve both the vybemux repository location and each plugin
# directory. Everything here is optional: if something is missing (old
# installation, repository moved/deleted), omit that line instead of aborting
# the popup.
plugins_dir="$HOME/.tmux/plugins"
repo_dir=""
[ -L "$plugins_dir" ] && repo_dir="$(dirname "$(readlink -f "$plugins_dir")")"

version=""
[ -f "$HOME/.tmux/VERSION" ] && version="$(cat "$HOME/.tmux/VERSION")"

repo_url=""
[ -n "$repo_dir" ] && repo_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null)"

# Frozen Git state from the last ./install.sh (~/.tmux/VERSION_GIT), NOT
# determined live from the repository: about.sh should show what is actually
# installed/running, not where the (symlink-accessible) repository currently
# stands -- they can diverge if additional commits landed since installation.
# "vX.Y.Z" exactly on the tag, otherwise "vX.Y.Z-N-gHASH"; only show it when
# it differs from the plain VERSION line.
dev_describe=""
[ -f "$HOME/.tmux/VERSION_GIT" ] && dev_describe="$(cat "$HOME/.tmux/VERSION_GIT")"
[ "$dev_describe" = "v$version" ] && dev_describe=""

tmux_version=""
tmux_path=""
if command -v tmux >/dev/null 2>&1; then
    tmux_version="$(tmux -V | sed 's/^tmux //')"
    tmux_path="$(command -v tmux)"
fi

printf '%b\n\n' "${A}                        vybemux — About${R}"

if [ -n "$version" ]; then
    if [ -n "$dev_describe" ]; then
        printf "  ${T}vybemux v%s${R} ${M}(dev: %s)${R}\n" "$version" "$dev_describe"
    else
        printf "  ${T}vybemux v%s${R}\n" "$version"
    fi
else
    printf '%b\n' "  ${M}vybemux (version unknown -- ~/.tmux/VERSION not found)${R}"
fi
[ -n "$repo_url" ] && printf "  ${M}%s${R}\n" "$repo_url"
[ -n "$repo_dir" ] && printf "  ${M}%s${R}\n" "$repo_dir"

# Own line + muted color: tmux is the runtime environment, not part of
# vybemux itself -- set it apart visually so it does not look like a third
# vybemux version entry directly below the version/repository URL.
if [ -n "$tmux_version" ]; then
    printf '\n  %bRuntime: tmux v%s (%s)%b\n' "$M" "$tmux_version" "$tmux_path" "$R"
fi

echo ""
printf "  ${A}%-16s${R} ${A}%-10s${R} ${A}%s${R}\n" "PLUGIN" "VERSION" "URL"
printf "  ${S}%-16s${R} ${S}%-10s${R} ${S}%s${R}\n" "----------------" "----------" "----------------------------------------"

for name in tpm tmux-resurrect tmux-continuum tmux-yank; do
    plugin_path="$plugins_dir/$name"
    if [ ! -d "$plugin_path" ]; then
        printf "  ${T}%-16s${R} ${M}%s${R}\n" "$name" "not installed"
        continue
    fi
    plugin_version="$(git -C "$plugin_path" describe --tags --always 2>/dev/null)"
    plugin_url="$(git -C "$plugin_path" remote get-url origin 2>/dev/null)"
    printf "  ${T}%-16s${R} ${T}%-10s${R} ${M}%s${R}\n" "$name" "${plugin_version:-?}" "${plugin_url:-?}"
done

printf '\n%b\n' "${M}q = close     Up/Down, PageUp/PageDown = scroll${R}"
