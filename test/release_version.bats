#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/prepare-release.sh
# =============================================================================

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/prepare-release.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email "test@test.com"
    git -C "$REPO" config user.name "test"
    printf '0.0.1\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "initial release"
    git -C "$REPO" tag --no-sign -a v0.0.1 -m v0.0.1
}

run_prepare_release() {
    local version="$1"
    run bash -c "cd '$REPO' && bash '$SCRIPT' '$version'"
}

run_prepare_committed_release() {
    local version="$1"
    run bash -c "cd '$REPO' && bash '$SCRIPT' --require-committed '$version'"
}

@test "a valid next major version is prepared for a new release" {
    run_prepare_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"current=0.0.1"* ]]
    [[ "$output" == *"next=1.0.0"* ]]
    [[ "$output" == *"tag=v1.0.0"* ]]
    [[ "$output" == *"previous_tag=v0.0.1"* ]]
    [[ "$output" == *"needs_commit=true"* ]]
    [[ "$output" == *"tag_exists=false"* ]]
}

@test "committed mode rejects a version that has not passed through a pull request" {
    run_prepare_committed_release 1.0.0

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be committed through a release pull request"* ]]
}

@test "committed mode accepts a linear version-bump commit" {
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    local release_commit
    release_commit="$(git -C "$REPO" rev-parse HEAD)"

    run_prepare_committed_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_commit=false"* ]]
    [[ "$output" == *"release_commit=$release_commit"* ]]
}

@test "committed mode releases the merged main commit" {
    git -C "$REPO" switch -q -c release
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    git -C "$REPO" switch -q main
    printf 'important feature\n' >"$REPO/feature.txt"
    git -C "$REPO" add feature.txt
    git -C "$REPO" commit -q -m "feat: add important feature"
    git -C "$REPO" merge --no-gpg-sign --no-ff -q -m \
        "Merge pull request 'chore(release): bump v1.0.0' (#99)" release
    local release_commit
    release_commit="$(git -C "$REPO" rev-parse HEAD)"

    run_prepare_committed_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"release_commit=$release_commit"* ]]
}

@test "committed mode accepts Gitea's squash subject suffix" {
    git -C "$REPO" switch -q -c release
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    git -C "$REPO" switch -q main
    git -C "$REPO" merge --squash -q release
    git -C "$REPO" commit -q -m \
        "chore(release): bump version to v1.0.0 (#99)"
    local release_commit
    release_commit="$(git -C "$REPO" rev-parse HEAD)"

    run_prepare_committed_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"release_commit=$release_commit"* ]]
}

@test "a target that skips semantic-version increments is rejected" {
    run_prepare_release 1.2.0

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be the next patch, minor, or major version"* ]]
}

@test "the same target can resume after the version commit and tag" {
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    git -C "$REPO" tag --no-sign -a v1.0.0 -m v1.0.0

    run_prepare_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"previous_tag=v0.0.1"* ]]
    [[ "$output" == *"needs_commit=false"* ]]
    [[ "$output" == *"tag_exists=true"* ]]
}

@test "recovery resolves the tagged release commit after later main commits" {
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    local release_commit
    release_commit="$(git -C "$REPO" rev-parse HEAD)"
    git -C "$REPO" tag --no-sign -a v1.0.0 -m v1.0.0
    printf 'later change\n' >"$REPO/README.md"
    git -C "$REPO" add README.md
    git -C "$REPO" commit -q -m "docs: add later change"

    run_prepare_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_commit=false"* ]]
    [[ "$output" == *"tag_exists=true"* ]]
    [[ "$output" == *"release_commit=$release_commit"* ]]
}

@test "an untagged release includes later main commits" {
    printf '1.0.0\n' >"$REPO/VERSION"
    git -C "$REPO" add VERSION
    git -C "$REPO" commit -q -m "chore(release): bump version to v1.0.0"
    printf 'later change\n' >"$REPO/README.md"
    git -C "$REPO" add README.md
    git -C "$REPO" commit -q -m "docs: add later change"
    local release_commit
    release_commit="$(git -C "$REPO" rev-parse HEAD)"

    run_prepare_release 1.0.0

    [ "$status" -eq 0 ]
    [[ "$output" == *"needs_commit=false"* ]]
    [[ "$output" == *"tag_exists=false"* ]]
    [[ "$output" == *"release_commit=$release_commit"* ]]
}

@test "an existing target tag on another commit is rejected" {
    git -C "$REPO" tag --no-sign -a v1.0.0 -m v1.0.0

    run_prepare_release 1.0.0

    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists before the version commit"* ]]
}
