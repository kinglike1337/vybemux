#!/usr/bin/env bats
# =============================================================================
# Tests for the CI workflow token boundaries
# =============================================================================

bats_require_minimum_version 1.5.0

WORKFLOW="$BATS_TEST_DIRNAME/../.gitea/workflows/ci.yml"

@test "workflow grants the token read-only repository access" {
    run awk '
        /^permissions:$/ {
            getline
            read_only = ($0 == "  contents: read")
            getline
            read_only = read_only && ($0 == "")
            getline
            read_only = read_only && ($0 == "jobs:")
        }
        END { exit !read_only }
    ' "$WORKFLOW"

    [ "$status" -eq 0 ]
}

@test "every checkout avoids persisting the workflow token" {
    run awk '
        /^      - / {
            if (in_checkout) {
                checkout_count++
                if (!credentials_disabled) {
                    invalid = 1
                }
            }
            in_checkout = ($0 ~ /uses: actions\/checkout@/)
            credentials_disabled = 0
            next
        }
        in_checkout && /^          persist-credentials: false$/ {
            credentials_disabled = 1
        }
        END {
            if (in_checkout) {
                checkout_count++
                if (!credentials_disabled) {
                    invalid = 1
                }
            }
            exit invalid || checkout_count == 0
        }
    ' "$WORKFLOW"

    [ "$status" -eq 0 ]
}
