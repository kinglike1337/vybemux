# =============================================================================
# tmux Configuration for Bash — Aliases, Functions
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

# Open a plain shell in a new tmux window
alias tw-shell='tmux new-window -n shell'

# ---------------------------------------------------------------------------
# Dev Session Setup
# ---------------------------------------------------------------------------

# Create a full dev session with shell + claude + opencode windows
# Usage: tmux-dev [session-name] [project-dir]
tmux-dev() {
    local session="${1:-$(basename "$PWD")}"
    local project_dir="${2:-$PWD}"

    if tmux has-session -t "$session" 2>/dev/null; then
        echo "Session '$session' already exists. Attaching..."
        tmux attach -t "$session"
        return
    fi

    tmux new-session -d -s "$session" -n shell -c "$project_dir"
    tmux new-window -t "$session" -n claude -c "$project_dir"
    tmux new-window -t "$session" -n opencode -c "$project_dir"
    tmux select-window -t "$session":1
    tmux attach -t "$session"
}

# Quick session for a specific project
# Usage: tmux-project <project-name>
# Default project directory: $HOME/projects/ (customize if needed)
tmux-project() {
    local project="${1:?Usage: tmux-project <project-name>}"
    local project_dir="$HOME/projects/$project"

    if [ ! -d "$project_dir" ]; then
        echo "Directory '$project_dir' does not exist."
        return 1
    fi

    tmux-dev "$project" "$project_dir"
}
