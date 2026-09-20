#!/usr/bin/env bats
# =============================================================================
# Tests for sync-mirror.sh — guard conditions plus one limited
# happy path (initial sync, automatic commit message). The interactive
# editor path ("git commit -e") and a real "push" are deliberately NOT
# tested -- only the "n" answer path of the edit prompt.
#
# sync-mirror.sh resolves MAIN_REPO via BASH_SOURCE and hardcodes
# MIRROR_REPO as "${VYBEMUX_MIRROR_DIR:-$HOME/projects/vybemux-github}" -- which is why the
# script is copied per test into a fixture MAIN_REPO and HOME is pointed
# at a fixture directory, instead of touching the real repo or the real
# public mirror. All destructive operations (rm -f, git commit, git add -A)
# run exclusively inside $BATS_TEST_TMPDIR.
# =============================================================================

SYNC_SCRIPT="$BATS_TEST_DIRNAME/../sync-mirror.sh"

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    # git >= 2.38.1 blocks submodule file:// URLs by default (CVE-2022-39253).
    # The submodule tests below use local bare repos as fake upstreams instead
    # of hitting the network, so this needs to be allowed in the fixture HOME.
    git config --global protocol.file.allow always
    git config --global user.email "test@test.com"
    git config --global user.name "test"
}

setup_main_repo() {
    local repo="$1"
    mkdir -p "$repo"
    (
        cd "$repo" || exit 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "test"
    )
    cp "$SYNC_SCRIPT" "$repo/sync-mirror.sh"
}

setup_mirror_repo() {
    local repo="$HOME/projects/vybemux-github"
    mkdir -p "$repo"
    (
        cd "$repo" || exit 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "test"
    )
}

@test "target directory missing -> error" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"

    run bash "$main_repo/sync-mirror.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Mirror directory not found"* ]]
}

@test "VYBEMUX_MIRROR_DIR overrides the default target directory" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    local custom_dir="$BATS_TEST_TMPDIR/custom-mirror"
    setup_main_repo "$main_repo"

    VYBEMUX_MIRROR_DIR="$custom_dir" run bash "$main_repo/sync-mirror.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Mirror directory not found: $custom_dir"* ]]
}

@test "target directory is not a git repository -> error" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    mkdir -p "$HOME/projects/vybemux-github"

    run bash "$main_repo/sync-mirror.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Target is not a git repository"* ]]
}

@test "sensitive data in the repo -> abort on 'n' before any commit" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    printf 'api_key=abc123\n' >"$main_repo/secret.conf"

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Potentially sensitive content found"* ]]
    [ -z "$(cd "$HOME/projects/vybemux-github" && git log --oneline 2>/dev/null)" ]
}

@test "internal hostname in a mirrored file -> hard abort before any commit" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    printf 'See https://gitea.int.example.test/issues/1\n' >"$main_repo/NOTES.md"

    run bash "$main_repo/sync-mirror.sh" <<<"y"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Internal hostnames or addresses would be published"* ]]
    [[ "$output" == *"NOTES.md"* ]]
    [ -z "$(cd "$HOME/projects/vybemux-github" && git log --oneline 2>/dev/null)" ]
}

@test "sync commit message omits merge commits and subjects naming internal hosts" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    local mirror_repo="$HOME/projects/vybemux-github"

    printf '#!/bin/bash\necho hi\n' >"$main_repo/a.sh"
    (
        cd "$main_repo" || exit 1
        git add -A
        git commit -q -m "feat: public change"
        git commit -q --allow-empty -m "chore(deps): update gitea.int.example.test/img tag"
        git switch -q -c topic
        git commit -q --allow-empty -m "feat: topic work"
        git switch -q -
        git merge -q --no-ff topic -m "Merge pull request 'topic' (#7) from topic into main"
    )

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 0 ]

    run git -C "$mirror_repo" log -1 --format=%B
    [[ "$output" == *"feat: public change"* ]]
    [[ "$output" == *"feat: topic work"* ]]
    [[ "$output" != *"gitea.int"* ]]
    [[ "$output" != *"Merge pull request"* ]]
}

@test "first sync copies files, removes obsolete leftovers, and commits automatically" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    local mirror_repo="$HOME/projects/vybemux-github"

    printf '#!/bin/bash\necho hi\n' >"$main_repo/scripts_test.sh"
    printf '# Docs\n' >"$main_repo/README.md"
    printf '1.2.3\n' >"$main_repo/VERSION"
    printf 'MIT License\n' >"$main_repo/LICENSE"
    printf '{}\n' >"$main_repo/renovate.json"
    printf 'repos: []\n' >"$main_repo/.pre-commit-config.yaml"
    mkdir -p "$main_repo/test"
    printf '#!/usr/bin/env bats\n' >"$main_repo/test/example.bats"
    (cd "$main_repo" && git add -A && git commit -q -m init)

    printf 'obsolete leftover\n' >"$mirror_repo/old-leftover.sh"
    (cd "$mirror_repo" && git add -A && git commit -q -m "pre-existing leftover")

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mirror synchronization complete!"* ]]

    [ -f "$mirror_repo/scripts_test.sh" ]
    [ -f "$mirror_repo/README.md" ]
    [ ! -f "$mirror_repo/old-leftover.sh" ]

    # Root-metadata files (matched by exact name, not extension) and the
    # extension-based *.bats addition must survive the same run that copied
    # them — regression test for the copy-then-delete asymmetry between the
    # copy step and the obsolete-file removal step.
    [ -f "$mirror_repo/VERSION" ]
    [ -f "$mirror_repo/LICENSE" ]
    [ -f "$mirror_repo/renovate.json" ]
    [ -f "$mirror_repo/.pre-commit-config.yaml" ]
    [ -f "$mirror_repo/test/example.bats" ]

    local main_head mirror_sha
    main_head="$(cd "$main_repo" && git rev-parse HEAD)"
    mirror_sha="$(cat "$mirror_repo/.last-sync-sha")"
    [ "$main_head" = "$mirror_sha" ]

    run bash -c "cd '$mirror_repo' && git log --oneline | wc -l"
    [ "$output" -eq 2 ]
}

# Creates a local bare repo with two commits to stand in for a plugin's
# upstream, avoiding a real network dependency in these tests. Echoes
# "<first-commit-sha> <bare-repo-path>".
setup_bare_submodule_source() {
    local name="$1"
    local src="$BATS_TEST_TMPDIR/${name}-src"
    local bare="$BATS_TEST_TMPDIR/${name}.git"
    mkdir -p "$src"
    (
        cd "$src" || exit 1
        git init -q
        printf 'v1\n' >file.txt
        git add -A && git commit -q -m v1
    )
    local sha1
    sha1="$(cd "$src" && git rev-parse HEAD)"
    (
        cd "$src" || exit 1
        printf 'v2\n' >file.txt
        git add -A && git commit -q -m v2
    )
    git clone -q --bare "$src" "$bare"
    echo "$sha1 $bare"
}

@test "vendored submodule copy is converted to a real gitlink pinned to the main repo's commit" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    local mirror_repo="$HOME/projects/vybemux-github"

    local sha1 bare
    read -r sha1 bare < <(setup_bare_submodule_source demo)

    (
        cd "$main_repo" || exit 1
        git submodule add -q "$bare" plugins/demo
        (cd plugins/demo && git checkout -q "$sha1")
        git add -A && git commit -q -m "init with submodule"
    )

    # Simulate the pre-existing vendored-copy state: a plain tracked file at
    # the submodule's path, not a gitlink.
    mkdir -p "$mirror_repo/plugins/demo"
    printf 'v1\n' >"$mirror_repo/plugins/demo/file.txt"
    (cd "$mirror_repo" && git add -A && git commit -q -m "vendored copy")

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Converting plugins/demo to a real submodule..."* ]]

    run git -C "$mirror_repo" ls-files -s -- plugins/demo
    [[ "$output" == 160000* ]]
    [[ "$output" == *"$sha1"* ]]

    run git -C "$mirror_repo/plugins/demo" rev-parse HEAD
    [ "$output" = "$sha1" ]
}

@test "submodule pointer bump in main repo advances the mirror's gitlink" {
    local main_repo="$BATS_TEST_TMPDIR/main-repo"
    setup_main_repo "$main_repo"
    setup_mirror_repo
    local mirror_repo="$HOME/projects/vybemux-github"

    local sha1 bare
    read -r sha1 bare < <(setup_bare_submodule_source demo)
    local sha2
    sha2="$(git -C "$bare" rev-parse HEAD)"

    (
        cd "$main_repo" || exit 1
        git submodule add -q "$bare" plugins/demo
        (cd plugins/demo && git checkout -q "$sha1")
        git add -A && git commit -q -m "init with submodule at v1"
    )

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 0 ]

    (
        cd "$main_repo" || exit 1
        (cd plugins/demo && git checkout -q "$sha2")
        git add -A && git commit -q -m "bump submodule to v2"
    )

    run bash "$main_repo/sync-mirror.sh" <<<"n"
    [ "$status" -eq 0 ]

    run git -C "$mirror_repo" ls-files -s -- plugins/demo
    [[ "$output" == *"$sha2"* ]]
    run git -C "$mirror_repo/plugins/demo" rev-parse HEAD
    [ "$output" = "$sha2" ]
}
