#!/bin/bash
# =============================================================================
# tmux Cheat-Sheet
# Prints a colored, two-column reference of the keyboard shortcuts defined in
# this tmux configuration. Shown via display-popup + less -R (see tmux.conf).
# Plain ASCII keeps columns aligned in any font/locale.
# =============================================================================

# Tokyo Night colors (true-color ANSI; plain text on non-true-color terminals).
A='\033[1;38;2;122;161;247m'   # accent, bold  (title, section headers)
T='\033[38;2;169;177;214m'     # default text
M='\033[38;2;86;95;137m'       # muted         (hints, notes)
S='\033[38;2;59;66;97m'        # separator     (rules, column pipe, blanks)
Y='\033[38;2;224;175;104m'     # yellow        (shortcut keys)
R='\033[0m'                    # reset

# Layout: 2-space indent, 23-wide left cell, " | ", 14-wide right key, then
# description. Padding (%-23s / %-14s) applies to PLAIN arguments; colors wrap
# the fields inside the double-quoted format string, so escape codes never
# disturb visible column alignment. Blank cells pad to width too.

printf '%b\n\n' "${A}                        tmux Cheat-Sheet${R}"
printf '%b\n\n' "${M}   Prefix = Strg+a: erst Prefix druecken, dann den Befehl${R}"

printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "GRUNDLAGEN" "PANES"
printf "  ${S}%-23s${R} ${S}|${R} ${S}%-14s${R}\n" "-----------------------" "--------------"

printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Session > Window > Pane"  "Strg+a |"        "vertikal teilen"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+a d  abhaengen"      "Strg+a -"        "horizontal teilen"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "tmux attach  anhaengen"   "Alt+h j k l"     "Pane wechseln"
printf "  ${M}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "(Session laeuft weiter)"  "Strg+a H J K L"  "Pane vergroessern"
printf "  ${S}%-23s${R} ${S}|${R}\n" ""
printf "  ${A}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "SESSIONS" "WINDOWS"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+a s  Session-Liste"  "Strg+a c"        "neues Fenster"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+a ( )  vor/zurueck"  "Strg+a 1-9"      "zu Fenster N"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+a w  Uebersicht"     "Strg+a l"        "letztes Fenster"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" ""                         "Shift+< >"       "Fenster wechseln"
printf "  ${A}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "COPY-MODE"                "Strg+Shift+< >"  "tauschen"
printf "  ${T}%-23s${R} ${S}|${R}\n" "Strg+a [  starten"
printf "  ${T}%-23s${R} ${S}|${R} ${A}%-14s${R}\n" "v   Auswahl beginnen"  "SONSTIGES"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+v  Rechteck-Ausw."   "Strg+a r"        "Config neu laden"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "y   kopieren -> Ablage"   "Strg+a Strg+t"   "Mouse an/aus"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Strg+a ]  einfuegen"      "Strg+a S"        "Sync-Panes"
printf "  ${T}%-23s${R} ${S}|${R} ${Y}%-14s${R} ${T}%s${R}\n" "Esc Copy-Mode verlassen"  "Shift+Ziehen"    "Terminal-Auswahl"

printf '\n%b\n' "${A}NEU:${R} ${Y}Strg+a Tab${R} ${T}naechste Session${R}  ${Y}Shift+Tab${R} ${T}vorige${R}  ${Y}Strg+a g${R} ${T}Git (lazygit)${R}  ${Y}Strg+a F${R} ${T}Files (yazi)${R}"
printf '\n%b\n' "${M}q = schliessen     Pfeil hoch/runter, BildAuf/BildAb = blaettern${R}"
