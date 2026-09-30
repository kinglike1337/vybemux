#!/bin/bash
# =============================================================================
# Build Release Archive
# Creates a deterministic source archive with all submodule contents included
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${1:?Usage: build-release-archive.sh <output.tar.gz>}"
VERSION_FILE="$REPO_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "VERSION file not found: $VERSION_FILE" >&2
    exit 1
fi

version="$(cat "$VERSION_FILE")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version in VERSION: $version" >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_DIR" status --porcelain \
    --untracked-files=no --ignore-submodules=none)" ]]; then
    echo "The working tree must be clean before building a release archive" >&2
    exit 1
fi

submodule_status="$(git -C "$REPO_DIR" submodule status --recursive)"
if grep -qE '^[-+U]' <<<"$submodule_status"; then
    echo "Submodules must be initialized at their recorded commits" >&2
    exit 1
fi

required_files=(
    "plugins/tpm/tpm"
    "plugins/tmux-resurrect/scripts/restore.sh"
    "plugins/tmux-continuum/continuum.tmux"
    "plugins/tmux-yank/yank.tmux"
    "test/bats-core/bin/bats"
)
for required_file in "${required_files[@]}"; do
    if [[ -f "$REPO_DIR/$required_file" ]]; then
        continue
    fi
    echo "Required archive content missing: $required_file" >&2
    exit 1
done

output_dir="$(dirname "$OUTPUT_FILE")"
mkdir -p "$output_dir"
file_list="$(mktemp)"
temporary_archive="$(mktemp "$output_dir/.vybemux-release.XXXXXX")"
cleanup() {
    rm -f "$file_list" "$temporary_archive"
}
trap cleanup EXIT

git -C "$REPO_DIR" ls-files --recurse-submodules -z | LC_ALL=C sort -z >"$file_list"
archive_root="vybemux-v$version"
source_date_epoch="$(git -C "$REPO_DIR" log -1 --format=%ct)"

tar -C "$REPO_DIR" \
    --create \
    --file=- \
    --null \
    --no-recursion \
    --files-from="$file_list" \
    --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --transform="s|^|$archive_root/|" \
    | gzip -n >"$temporary_archive"

mv "$temporary_archive" "$OUTPUT_FILE"
printf '%s\n' "$OUTPUT_FILE"
