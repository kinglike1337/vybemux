#!/bin/bash
# =============================================================================
# vybemux Submodules Update Script
# Updates all tmux plugin submodules to their latest commits
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_submodule() {
    echo -e "${CYAN}[SUBMODULE]${NC} $1"
}

# Check if in git repo
if [ ! -d "$REPO_DIR/.git" ]; then
    echo_error "Not in a git repository"
    exit 1
fi

cd "$REPO_DIR"

echo_info "Updating vybemux submodules..."
echo ""

# Fetch latest changes from remote for main repo
echo_info "Fetching main repository..."
git fetch origin

# Check if main repo is clean
if [ -n "$(git status --porcelain)" ]; then
    echo_error "Working directory is not clean. Please commit or stash changes first."
    git status --short
    exit 1
fi

# Update all submodules
echo_info "Updating submodules..."
git submodule update --remote --merge

# Show status of submodules
echo ""
echo_info "Submodule status:"
git submodule status

# Check if any submodules were updated
if git diff --quiet --exit-code .gitmodules; then
    echo ""
    echo_success "No submodule updates available."
    exit 0
fi

# Show commits that were pulled
echo ""
echo_info "Commits pulled for each submodule:"
echo ""

for submodule in plugins/*/; do
    name=$(basename "$submodule")
    if [ -d "$submodule/.git" ]; then
        cd "$submodule"
        old_head=$(git rev-parse "HEAD@{1}" 2>/dev/null || echo "none")
        new_head=$(git rev-parse HEAD)

        if [ "$old_head" != "$new_head" ]; then
            echo_submodule "$name:"
            echo "  Before: $old_head"
            echo "  After:  $new_head"
            echo ""
            echo "  Recent commits:"
            git log --oneline -5 --no-decorate "$old_head..$new_head" || echo "  (New submodule)"
            echo ""
        fi
        cd "$REPO_DIR"
    fi
done

echo_success "Submodules updated!"
echo ""
echo_info "Changes are staged in .gitmodules"
echo ""
echo "To commit and push:"
echo "  git add .gitmodules"
echo "  git commit -m 'Update submodules'"
echo "  git push"
