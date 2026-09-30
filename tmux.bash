# =============================================================================
# tmux Configuration for Bash — Aliases
# Source from .bashrc:  [ -f ~/.tmux.bash ] && . ~/.tmux.bash
# =============================================================================

# ---------------------------------------------------------------------------
# tmux Quick Access
# ---------------------------------------------------------------------------

alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'
alias tn='tmux new-session -s'

# ---------------------------------------------------------------------------
# AI Tool Windows (run inside an active tmux session)
# ---------------------------------------------------------------------------

# Claude Code windows
alias tw-claude='tmux new-window -n claude "claude --resume"'
alias tw-claude-cont='tmux new-window -n claude "claude --continue"'
alias tw-claude-new='tmux new-window -n claude "claude"'

# OpenCode windows
alias tw-opencode='tmux new-window -n opencode "opencode --continue"'
alias tw-opencode-new='tmux new-window -n opencode "opencode"'

# Codex windows
alias tw-codex='tmux new-window -n codex "codex resume --last"'
alias tw-codex-new='tmux new-window -n codex "codex"'

# Pi windows
alias tw-pi='tmux new-window -n pi "pi --continue"'
alias tw-pi-new='tmux new-window -n pi "pi"'

# Open a plain shell in a new tmux window
alias tw-shell='tmux new-window -n shell'

# Singleton TUI tabs (Start or switch — like Prefix+g / Prefix+F, without duplicates)
alias tw-git='~/.tmux/scripts/tui-tab.sh git'
alias tw-files='~/.tmux/scripts/tui-tab.sh files'
