#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/build-release-archive.sh
# =============================================================================

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    git clone -q "$PROJECT_ROOT" "$REPO"
    cp "$PROJECT_ROOT/scripts/build-release-archive.sh" \
        "$REPO/scripts/build-release-archive.sh"
    git -C "$REPO" config user.email "test@test.com"
    git -C "$REPO" config user.name "test"
    git -C "$REPO" add scripts/build-release-archive.sh
    if ! git -C "$REPO" diff --cached --quiet; then
        git -C "$REPO" commit -q -m "test: use current archive builder"
    fi
    while read -r key path; do
        local name="${key#submodule.}"
        name="${name%.path}"
        git -C "$REPO" config "submodule.$name.url" "$PROJECT_ROOT/$path"
    done < <(git config -f "$REPO/.gitmodules" --get-regexp '^submodule\..*\.path$')
    git -C "$REPO" -c protocol.file.allow=always submodule update --init -q
    while read -r _ parent_path; do
        local nested_modules="$REPO/$parent_path/.gitmodules"
        [[ -f "$nested_modules" ]] || continue
        while read -r nested_key nested_path; do
            local nested_name="${nested_key#submodule.}"
            nested_name="${nested_name%.path}"
            git -C "$REPO/$parent_path" config \
                "submodule.$nested_name.url" \
                "$PROJECT_ROOT/$parent_path/$nested_path"
        done < <(git config -f "$nested_modules" \
            --get-regexp '^submodule\..*\.path$')
    done < <(git config -f "$REPO/.gitmodules" \
        --get-regexp '^submodule\..*\.path$')
    git -C "$REPO" -c protocol.file.allow=always submodule update \
        --init --recursive -q
    SCRIPT="$REPO/scripts/build-release-archive.sh"
    VERSION="$(cat "$REPO/VERSION")"
}

@test "release archive includes the recursively checked-out submodules" {
    local archive="$BATS_TEST_TMPDIR/vybemux.tar.gz"

    run bash "$SCRIPT" "$archive"

    [ "$status" -eq 0 ]
    [ -f "$archive" ]
    run tar -tzf "$archive"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vybemux-v$VERSION/plugins/tpm/tpm"* ]]
    [[ "$output" == *"vybemux-v$VERSION/plugins/tmux-resurrect/scripts/restore.sh"* ]]
    [[ "$output" == *"vybemux-v$VERSION/test/bats-core/bin/bats"* ]]
    [[ "$output" == *"vybemux-v$VERSION/LICENSE"* ]]
    [[ "$output" != *"/.git/"* ]]
}

@test "two release archive builds from the same checkout are identical" {
    local first="$BATS_TEST_TMPDIR/first.tar.gz"
    local second="$BATS_TEST_TMPDIR/second.tar.gz"

    run bash "$SCRIPT" "$first"
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" "$second"
    [ "$status" -eq 0 ]

    run cmp "$first" "$second"
    [ "$status" -eq 0 ]
}

@test "release archive rejects tracked working-tree changes" {
    local archive="$BATS_TEST_TMPDIR/dirty.tar.gz"
    printf 'dirty\n' >>"$REPO/README.md"

    run bash "$SCRIPT" "$archive"

    [ "$status" -eq 1 ]
    [[ "$output" == *"working tree must be clean"* ]]
    [ ! -e "$archive" ]
}
