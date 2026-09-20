#!/bin/bash
# =============================================================================
# Prepare Release
# Validates an explicit target version and detects resumable release state
# =============================================================================

set -euo pipefail

require_committed=false
if [[ "${1:-}" == "--require-committed" ]]; then
    require_committed=true
    shift
fi
target="${1:?Usage: prepare-release.sh [--require-committed] <target-version>}"
if [[ $# -ne 1 ]]; then
    echo "Usage: prepare-release.sh [--require-committed] <target-version>" >&2
    exit 1
fi
repo_dir="$(git rev-parse --show-toplevel)"
current="$(cat "$repo_dir/VERSION")"

if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Current VERSION is not valid SemVer: $current" >&2
    exit 1
fi
if [[ ! "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Target version is not valid SemVer: $target" >&2
    exit 1
fi

IFS='.' read -r major minor patch <<<"$current"
next_patch="$major.$minor.$((patch + 1))"
next_minor="$major.$((minor + 1)).0"
next_major="$((major + 1)).0.0"
tag="v$target"
needs_commit=true
tag_exists=false
release_commit=""
version_commit=""

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tag_exists=true
fi

if [[ "$current" == "$target" ]]; then
    expected_subject="chore(release): bump version to $tag"
    if [[ "$tag_exists" == true ]]; then
        release_commit="$(git rev-list -n 1 "$tag")"
    else
        release_commit="$(git rev-parse HEAD)"
    fi
    version_commit="$(git log -1 --format=%H --fixed-strings \
        --grep="$expected_subject" "$release_commit" -- VERSION)"
    if [[ -z "$version_commit" ]]; then
        echo "Could not find the version commit for $target" >&2
        exit 1
    fi
    actual_subject="$(git log -1 --format=%s "$version_commit")"
    if [[ "$actual_subject" != "$expected_subject" ]]; then
        squash_suffix="${actual_subject#"$expected_subject"}"
        if [[ ! "$squash_suffix" =~ ^\ \(#[1-9][0-9]*\)$ ]]; then
            echo "The version commit for $target has an unexpected subject" >&2
            exit 1
        fi
    fi
    version_at_commit="$(git show "${version_commit}:VERSION")"
    if [[ "$version_at_commit" != "$target" ]]; then
        echo "The version commit does not contain VERSION $target" >&2
        exit 1
    fi
    if ! git merge-base --is-ancestor "$version_commit" "$release_commit"; then
        echo "The version commit for $target is not part of the release target" >&2
        exit 1
    fi
    version_at_release="$(git show "${release_commit}:VERSION")"
    if [[ "$version_at_release" != "$target" ]]; then
        echo "The release target does not contain VERSION $target" >&2
        exit 1
    fi
    if ! git merge-base --is-ancestor "$release_commit" HEAD; then
        echo "The release target for $target is not an ancestor of HEAD" >&2
        exit 1
    fi
    needs_commit=false
elif [[ "$target" != "$next_patch" && "$target" != "$next_minor" && "$target" != "$next_major" ]]; then
    echo "Target $target must be the next patch, minor, or major version after $current" >&2
    exit 1
elif [[ "$tag_exists" == true ]]; then
    echo "Tag $tag already exists before the version commit" >&2
    exit 1
fi

if [[ "$require_committed" == true && "$needs_commit" == true ]]; then
    echo "VERSION $target must be committed through a release pull request before publication" >&2
    exit 1
fi

previous_tag="$(git describe --tags --abbrev=0 --exclude="$tag" 2>/dev/null || true)"

printf 'current=%s\n' "$current"
printf 'next=%s\n' "$target"
printf 'tag=%s\n' "$tag"
printf 'previous_tag=%s\n' "$previous_tag"
printf 'needs_commit=%s\n' "$needs_commit"
printf 'tag_exists=%s\n' "$tag_exists"
printf 'release_commit=%s\n' "$release_commit"
