#!/usr/bin/env bats
# =============================================================================
# Tests for the release workflow security boundaries
# =============================================================================

bats_require_minimum_version 1.5.0

WORKFLOW="$BATS_TEST_DIRNAME/../.gitea/workflows/release.yml"

@test "workflow passes the untrusted target version through the environment" {
    run grep -F 'TARGET_VERSION: ${{ inputs.version }}' "$WORKFLOW"

    [ "$status" -eq 0 ]
    run grep -E 'run:.*\$\{\{[[:space:]]*inputs\.version' "$WORKFLOW"
    [ "$status" -eq 1 ]
}

@test "workflow checks out and verifies main before release writes" {
    run grep -F 'ref: main' "$WORKFLOW"

    [ "$status" -eq 0 ]
    run grep -F 'EVENT_REF: ${{ github.ref }}' "$WORKFLOW"
    [ "$status" -eq 0 ]
    run grep -F '[[ "$EVENT_REF" == "refs/heads/main" ]]' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow checks out the resolved release target before tagging and packaging" {
    run grep -F 'RELEASE_COMMIT: ${{ steps.version.outputs.release_commit }}' "$WORKFLOW"

    [ "$status" -eq 0 ]
    run grep -F 'git checkout --detach "$RELEASE_COMMIT"' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow verifies the remote tag after a concurrent push failure" {
    run grep -F 'if ! git push origin "$RELEASE_TAG"; then' "$WORKFLOW"

    [ "$status" -eq 0 ]
    run grep -F 'git ls-remote --refs origin' "$WORKFLOW"
    [ "$status" -eq 0 ]
    run grep -F '[[ "$remote_tag_commit" == "$RELEASE_COMMIT" ]]' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow requires the target version to be committed before publication" {
    run grep -F './scripts/prepare-release.sh --require-committed "$TARGET_VERSION"' "$WORKFLOW"
    [ "$status" -eq 0 ]
}

@test "workflow never commits or pushes to main" {
    run grep -F 'git commit' "$WORKFLOW"
    [ "$status" -eq 1 ]
    run grep -E 'git[[:space:]]+push.*main' "$WORKFLOW"
    [ "$status" -eq 1 ]
    run grep -F 'Bump and commit VERSION' "$WORKFLOW"
    [ "$status" -eq 1 ]
}
