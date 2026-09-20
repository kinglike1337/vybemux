#!/usr/bin/env bats
# =============================================================================
# Tests for scripts/publish-gitea-release.sh
# =============================================================================

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../scripts/publish-gitea-release.sh"

setup() {
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    FORM_LOG="$BATS_TEST_TMPDIR/form.log"
    HEADER_LOG="$BATS_TEST_TMPDIR/header.log"
    MOCK_CREATED_MARKER="$BATS_TEST_TMPDIR/release-created"
    REQUEST_PAYLOAD="$BATS_TEST_TMPDIR/request.json"
    RELEASE_RESPONSE="$BATS_TEST_TMPDIR/release.json"
    NOTES_FILE="$BATS_TEST_TMPDIR/notes.md"
    ARCHIVE_FILE="$BATS_TEST_TMPDIR/vybemux-v1.0.0.tar.gz"
    CHECKSUM_FILE="$ARCHIVE_FILE.sha256"
    MISMATCH_FILE="$BATS_TEST_TMPDIR/mismatched-asset"
    mkdir -p "$STUB_BIN"
    : >"$CURL_LOG"
    : >"$FORM_LOG"
    : >"$HEADER_LOG"
    printf 'Release notes\n' >"$NOTES_FILE"
    printf 'archive\n' >"$ARCHIVE_FILE"
    printf 'checksum\n' >"$CHECKSUM_FILE"
    printf 'different content\n' >"$MISMATCH_FILE"

    cat >"$STUB_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
method=GET
output_file=""
status_format=""
url=""
fail_on_http=false
follow_redirects=false
download_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -X)
            method="$2"
            shift 2
            ;;
        -o)
            output_file="$2"
            shift 2
            ;;
        -w)
            status_format="$2"
            shift 2
            ;;
        -H)
            printf '%s\n' "$2" >>"$HEADER_LOG"
            shift 2
            ;;
        -d)
            printf '%s\n' "$2" >"$REQUEST_PAYLOAD"
            shift 2
            ;;
        -F)
            printf '%s\n' "$2" >>"$FORM_LOG"
            shift 2
            ;;
        -f|-sf|-fs)
            fail_on_http=true
            shift
            ;;
        -L)
            follow_redirects=true
            shift
            ;;
        http://*|https://*)
            url="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done
printf '%s %s\n' "$method" "$url" >>"$CURL_LOG"
status=200
body=""
case "$url" in
    */downloads/*)
        status="${MOCK_DOWNLOAD_STATUS:-200}"
        if [[ -n "${MOCK_DOWNLOAD_FILE:-}" ]]; then
            download_file="$MOCK_DOWNLOAD_FILE"
        elif [[ "$url" == */downloads/mismatched/* ]]; then
            download_file="$MISMATCH_FILE"
        elif [[ "$url" == */"$(basename "$ARCHIVE_FILE")" ]]; then
            download_file="$ARCHIVE_FILE"
        elif [[ "$url" == */"$(basename "$CHECKSUM_FILE")" ]]; then
            download_file="$CHECKSUM_FILE"
        else
            exit 2
        fi
        if [[ -n "${MOCK_REDIRECT_URL:-}" && "$status" -ge 300 && "$status" -lt 400 \
            && "$follow_redirects" == true ]]; then
            printf 'GET %s\n' "$MOCK_REDIRECT_URL" >>"$CURL_LOG"
            status=200
        fi
        ;;
    */releases/tags/*)
        status="${MOCK_RELEASE_STATUS:-404}"
        if [[ -f "$MOCK_CREATED_MARKER" ]]; then
            status=200
        fi
        if [[ "$status" == "200" ]]; then
            body="$(cat "$RELEASE_RESPONSE")"
        fi
        ;;
    */releases/*/assets*)
        if [[ "$method" == "DELETE" ]]; then
            status="${MOCK_DELETE_STATUS:-204}"
        else
            status="${MOCK_UPLOAD_STATUS:-201}"
            body='{"id":101,"name":"uploaded"}'
            if [[ "$status" == "201" \
                || ( "${MOCK_CONCURRENT_ASSET:-false}" == true \
                    && ( "$status" == "409" || "$status" == "422" ) ) ]]; then
                asset_name="${url##*name=}"
                asset_content="${MOCK_UPLOADED_CONTENT:-matching}"
                jq --arg name "$asset_name" --arg content "$asset_content" '
                    (.assets | map(.id) | max // 100) as $id
                    | .assets += [{
                        id: ($id + 1),
                        name: $name,
                        browser_download_url: (
                            "https://gitea.example.invalid/downloads/" + $content + "/"
                            + (($id + 1) | tostring) + "/" + $name
                        )
                    }]
                ' "$RELEASE_RESPONSE" >"$RELEASE_RESPONSE.next"
                mv "$RELEASE_RESPONSE.next" "$RELEASE_RESPONSE"
            fi
        fi
        ;;
    */releases)
        status="${MOCK_CREATE_STATUS:-201}"
        if [[ "$status" == "201" || "$status" == "409" || "$status" == "422" ]]; then
            touch "$MOCK_CREATED_MARKER"
        fi
        body="$(cat "$RELEASE_RESPONSE")"
        ;;
    *)
        exit 2
        ;;
esac
if [[ -n "$output_file" ]]; then
    if [[ -n "$download_file" ]]; then
        cp "$download_file" "$output_file"
    else
        printf '%s\n' "$body" >"$output_file"
    fi
elif [[ -n "$body" ]]; then
    printf '%s\n' "$body"
fi
if [[ -n "$status_format" ]]; then
    printf '%s' "$status"
fi
if [[ "$fail_on_http" == true && "$status" -ge 400 ]]; then
    exit 22
fi
EOF
    chmod +x "$STUB_BIN/curl"
    export PATH="$STUB_BIN:/usr/bin:/bin"
    export ARCHIVE_FILE CHECKSUM_FILE MISMATCH_FILE CURL_LOG FORM_LOG HEADER_LOG
    export MOCK_CREATED_MARKER RELEASE_RESPONSE REQUEST_PAYLOAD
    export GITHUB_API_URL="https://gitea.example.invalid/api/v1"
    export GITHUB_REPOSITORY="public/vybemux"
    export GITHUB_TOKEN="test-token"
}

write_release_response() {
    local assets="$1"
    printf '{"id":42,"tag_name":"v1.0.0","name":"v1.0.0","body":"Release notes","draft":false,"prerelease":false,"assets":%s}\n' \
        "$assets" >"$RELEASE_RESPONSE"
}

release_asset() {
    local id="$1"
    local name="$2"
    local content="${3:-matching}"
    jq -cn \
        --argjson id "$id" \
        --arg name "$name" \
        --arg url "https://gitea.example.invalid/downloads/$content/$id/$name" \
        '{id: $id, name: $name, browser_download_url: $url}'
}

@test "a missing release is created before both assets are uploaded" {
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=404

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE" "$CHECKSUM_FILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Created release: v1.0.0"* ]]
    [[ "$output" == *"Uploaded asset: $(basename "$ARCHIVE_FILE")"* ]]
    [[ "$output" == *"Uploaded asset: $(basename "$CHECKSUM_FILE")"* ]]
    [ "$(grep -c 'POST .*/releases$' "$CURL_LOG")" -eq 1 ]
    [ "$(grep -c 'POST .*/assets?name=' "$CURL_LOG")" -eq 2 ]
    [ "$(grep -c '^GET https://gitea.example.invalid/downloads/' "$CURL_LOG")" -eq 2 ]
    grep -Fx 'Authorization: token test-token' "$HEADER_LOG"
    grep -Fx "attachment=@$ARCHIVE_FILE" "$FORM_LOG"
    grep -Fx "attachment=@$CHECKSUM_FILE" "$FORM_LOG"
    run jq -e '
        .tag_name == "v1.0.0"
        and .name == "v1.0.0"
        and .body == "Release notes\n"
        and .draft == false
        and .prerelease == false
    ' "$REQUEST_PAYLOAD"
    [ "$status" -eq 0 ]
}

@test "an existing release asset is reused only after its content is verified" {
    local existing_asset
    existing_asset="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$existing_asset")]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE" "$CHECKSUM_FILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Release already exists: v1.0.0"* ]]
    [[ "$output" == *"Verified existing asset: $existing_asset"* ]]
    [[ "$output" == *"Uploaded asset: $(basename "$CHECKSUM_FILE")"* ]]
    [ "$(grep -c 'POST .*/releases$' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c 'POST .*/assets?name=' "$CURL_LOG")" -eq 1 ]
    grep -Fx "GET https://gitea.example.invalid/downloads/matching/100/$existing_asset" \
        "$CURL_LOG"
}

@test "an existing asset with different content aborts without a write" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$asset_name")]"
    export MOCK_RELEASE_STATUS=200
    export MOCK_DOWNLOAD_FILE="$MISMATCH_FILE"

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset content does not match: $asset_name"* ]]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "an existing asset download failure aborts without a write" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$asset_name")]"
    export MOCK_RELEASE_STATUS=200
    export MOCK_DOWNLOAD_STATUS=503

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset download failed with HTTP 503: $asset_name"* ]]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "an existing asset with an untrusted download URL aborts before download" {
    local asset_name
    local asset
    asset_name="$(basename "$ARCHIVE_FILE")"
    asset="$(release_asset 100 "$asset_name" \
        | jq -c '.browser_download_url = "https://attacker.example/asset"')"
    write_release_response "[$asset]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Asset download URL is outside the Gitea origin: $asset_name"* ]]
    [ "$(grep -c 'attacker.example' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "an existing asset redirect is rejected without following it" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$asset_name")]"
    export MOCK_RELEASE_STATUS=200
    export MOCK_DOWNLOAD_STATUS=302
    export MOCK_REDIRECT_URL="https://attacker.example/asset"

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset download failed with HTTP 302: $asset_name"* ]]
    [ "$(grep -c 'attacker.example' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "an existing asset with incomplete metadata aborts without a write" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[{\"id\":100,\"name\":\"$asset_name\"}]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset metadata is incomplete: $asset_name"* ]]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "an unexpected release lookup response aborts without a write" {
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=500

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Release lookup failed with HTTP 500"* ]]
    [ "$(grep -c '^POST ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "a concurrent release creation conflict is recovered by refetching" {
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=404
    export MOCK_CREATE_STATUS=409

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Release was created concurrently: v1.0.0"* ]]
    [[ "$output" == *"Uploaded asset: $(basename "$ARCHIVE_FILE")"* ]]
}

@test "duplicate assets from a concurrent run are reduced deterministically" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 101 "$asset_name"),$(release_asset 100 "$asset_name")]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed duplicate asset: $asset_name (101)"* ]]
    [[ "$output" == *"Verified existing asset: $asset_name"* ]]
    grep -Eq 'DELETE .*/releases/42/assets/101$' "$CURL_LOG"
}

@test "a mismatched older duplicate aborts before deleting a valid newer asset" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$asset_name" mismatched),$(release_asset 101 "$asset_name")]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset content does not match: $asset_name"* ]]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "a mismatched newer duplicate is not discarded before verification" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response "[$(release_asset 100 "$asset_name"),$(release_asset 101 "$asset_name" mismatched)]"
    export MOCK_RELEASE_STATUS=200

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset content does not match: $asset_name"* ]]
    [ "$(grep -c '^DELETE ' "$CURL_LOG" || true)" -eq 0 ]
}

@test "a matching concurrent upload is verified before recovery succeeds" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=200
    export MOCK_UPLOAD_STATUS=422
    export MOCK_CONCURRENT_ASSET=true

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Asset was uploaded concurrently: $asset_name"* ]]
    [ "$(grep -c '^GET https://gitea.example.invalid/downloads/' "$CURL_LOG")" -eq 1 ]
}

@test "a mismatched concurrent upload aborts recovery" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=200
    export MOCK_UPLOAD_STATUS=409
    export MOCK_CONCURRENT_ASSET=true
    export MOCK_UPLOADED_CONTENT=mismatched

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset content does not match: $asset_name"* ]]
}

@test "a corrupted successful upload fails publication verification" {
    local asset_name
    asset_name="$(basename "$ARCHIVE_FILE")"
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=200
    export MOCK_UPLOAD_STATUS=201
    export MOCK_UPLOADED_CONTENT=mismatched

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Existing asset content does not match: $asset_name"* ]]
}

@test "an upload conflict fails when the requested asset is still missing" {
    write_release_response '[]'
    export MOCK_RELEASE_STATUS=200
    export MOCK_UPLOAD_STATUS=422

    run bash "$SCRIPT" v1.0.0 "$NOTES_FILE" "$ARCHIVE_FILE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Asset is missing after upload attempt"* ]]
}
