#!/bin/bash
# =============================================================================
# tmux Cheat-Sheet
# Prints a colored, two-column reference of the keyboard shortcuts defined in
# this tmux configuration, plus the two menus reachable via Ctrl+a m / M.
# Shown via display-popup + less -R (see tmux.conf).
# Plain ASCII keeps columns aligned in any font/locale.
#
# Layout: the sheet is a sequence of BLOCKS. Each block pairs one left-column
# section with one right-column section and MUST have the same number of body
# rows on both sides -- that is what keeps a section header lined up with the
# other column's header instead of drifting next to an unrelated data row
# from a longer section (which is what used to happen here once one side
# grew past the other). Add rows to both sides of a block together, or pad
# the shorter side with an empty row.
# =============================================================================

# Tokyo Night colors (true-color ANSI; plain text on non-true-color terminals).
A='\033[1;38;2;122;161;247m'   # accent, bold  (title, section headers)
T='\033[38;2;169;177;214m'     # default text
M='\033[38;2;86;95;137m'       # muted         (hints, notes, standard marker)
S='\033[38;2;59;66;97m'        # separator     (rules, column pipe, blanks)
Y='\033[38;2;224;175;104m'     # yellow        (shortcut keys)
R='\033[0m'                    # reset

# Layout: 2-space indent, 23-wide left cell, " | ", 14-wide right key, then
# description. Padding (%-23s / %-14s) applies to PLAIN arguments; colors wrap
# the fields inside the double-quoted format string, so escape codes never
# disturb visible column alignment. Blank cells pad to width too.

# Installed VERSION file (~/.tmux/VERSION, copied by install.sh)
# is optional -- if missing (old installation, manually deleted), the version
# line is simply omitted instead of aborting the popup.
version=""
[ -f "$HOME/.tmux/VERSION" ] && version="$(cat "$HOME/.tmux/VERSION")"
version_suffix=""
[ -n "$version" ] && version_suffix="  ${S}·${R} ${M}vybemux v${version}${R}"

printf '%b\n\n' "${A}                        tmux Cheat-Sheet${R}"
printf '%b\n' "${M}   Prefix = Ctrl+a: press Prefix first, then the command${R}${version_suffix}"
printf '%b\n\n' "${M}   Without 'Ctrl+a': no Prefix needed (Alt+, Shift+, Ctrl+Shift+...)${R}"

# --- Block 1: BASICS | PANES (4 rows) ----------------------------------------
printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "BASICS" "PANES"
printf "  ${S}%-23s${R} ${S}|${R} ${S}%-14s${R}\n" "-----------------------" "--------------"

printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Session > Window > Pane"  "Ctrl+a |"        "split vertically"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a d  detach"         "Ctrl+a -"        "split horizontally"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "tmux attach  reattach"    "Alt+h j k l"     "switch pane"
printf "  ${M}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "(session keeps running)"  "Ctrl+a H J K L"  "resize pane"
printf "  ${S}%-23s${R} ${S}|${R}\n" ""

# --- Block 2: SESSIONS | WINDOWS (5 rows) -----------------------------------
printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "SESSIONS" "WINDOWS"

printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a s  session list"  "Ctrl+a c"        "new window"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a ( )  prev/next"   "Ctrl+a 1-9"      "go to window N"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a w  overview"     "Ctrl+a l"        "last window"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a Tab  next"       "S-Left/Right"    "switch window"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a S-Tab  previous" "C-S-Left/Right"  "swap window"
printf "  ${S}%-23s${R} ${S}|${R}\n" ""

# --- Block 3: COPY-MODE | MISCELLANEOUS (6 rows) -----------------------------
printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "COPY-MODE" "MISCELLANEOUS"

printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a [  start"          "Ctrl+a g"        "Git (lazygit)"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "v   start selection"      "Ctrl+a F"        "Files (yazi)"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+v  rectangle mode"   "Ctrl+a r"        "reload config"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "y   copy -> clipboard"    "Ctrl+a Ctrl+t"   "mouse on/off"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Ctrl+a ]  paste"          "Ctrl+a S"        "sync panes"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Esc leave copy mode"      "Shift+drag"      "terminal selection"
printf "  ${S}%-23s${R} ${S}|${R}\n" ""

# --- Block 4: MENUS | MOUSE (2 rows) -----------------------------------------
printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "MENUS" "MOUSE"

printf "  ${T}%-23s${R} ${S}|${R} ${T}%s${R}\n" "Ctrl+a m  window menu"  "Click [+] button on right"
printf "  ${T}%-23s${R} ${S}|${R} ${T}%s${R}\n" "Ctrl+a M  session menu" "Click session name on left"

printf '\n%b\n' "${A}Menu contents:${R} ${Y}Ctrl+a m${R} ${T}-> AI Tools, Git, Files, Swap, Rename/close window, Zoom${R}"
printf '%b\n' "${M}              ${R} ${Y}Ctrl+a M${R} ${T}-> Session List, Next/Previous, New, Rename, Kill${R}"
printf '%b\n' "${M}              ${R} ${T}Save/Restore Session with mouse only: ${R}${Y}[+]${R}${T} button on right (Quick Actions)${R}"

printf '\n%b\n' "${M}S- = Shift, C-S- = Ctrl+Shift (without Prefix)${R}"
printf '%b\n' "${M}s, ( ), w, 1-9, l are tmux default bindings, not defined in tmux.conf${R}"
printf '\n%b\n' "${M}q = close     Up/Down, PageUp/PageDown = scroll${R}"
