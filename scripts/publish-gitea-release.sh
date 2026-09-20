#!/bin/bash
# =============================================================================
# Publish Gitea Release
# Creates or resumes a release and uploads any missing assets
# =============================================================================

set -euo pipefail

tag="${1:?Usage: publish-gitea-release.sh <tag> <notes-file> <asset> [asset ...]}"
notes_file="${2:?Usage: publish-gitea-release.sh <tag> <notes-file> <asset> [asset ...]}"
shift 2

: "${GITHUB_API_URL:?GITHUB_API_URL is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid release tag: $tag" >&2
    exit 1
fi
if [[ ! -f "$notes_file" ]]; then
    echo "Release notes file not found: $notes_file" >&2
    exit 1
fi
if [[ $# -eq 0 ]]; then
    echo "At least one release asset is required" >&2
    exit 1
fi
for asset_file in "$@"; do
    if [[ ! -f "$asset_file" ]]; then
        echo "Release asset not found: $asset_file" >&2
        exit 1
    fi
done

api_base="${GITHUB_API_URL%/}"
gitea_origin="${api_base%/api/v1}"
if [[ "$gitea_origin" == "$api_base" ]]; then
    echo "GITHUB_API_URL must end with /api/v1" >&2
    exit 1
fi
api_root="$api_base/repos/$GITHUB_REPOSITORY"
release_response="$(mktemp)"
release_update="$release_response.next"
asset_download="$(mktemp)"
cleanup() {
    rm -f "$release_response" "$release_update" "$asset_download"
}
trap cleanup EXIT

fetch_release() {
    curl -sS \
        -o "$release_response" \
        -w '%{http_code}' \
        -H "Authorization: token $GITHUB_TOKEN" \
        "$api_root/releases/tags/$tag"
}

validate_release() {
    release_id="$(jq -er --arg tag "$tag" '
        select(.tag_name == $tag)
        | select((.assets | type) == "array")
        | .id
    ' "$release_response")"
}

remove_duplicate_assets() {
    local asset_name="$1"
    local duplicate_id
    local delete_status
    while read -r duplicate_id; do
        [[ -n "$duplicate_id" ]] || continue
        delete_status="$(curl -sS \
            -o /dev/null \
            -w '%{http_code}' \
            -X DELETE \
            -H "Authorization: token $GITHUB_TOKEN" \
            "$api_root/releases/$release_id/assets/$duplicate_id")"
        if [[ "$delete_status" != "204" && "$delete_status" != "404" ]]; then
            echo "Duplicate asset cleanup failed with HTTP $delete_status" >&2
            exit 1
        fi
        jq --argjson id "$duplicate_id" \
            '.assets |= map(select(.id != $id))' \
            "$release_response" >"$release_update"
        mv "$release_update" "$release_response"
        echo "Removed duplicate asset: $asset_name ($duplicate_id)"
    done < <(jq -r --arg name "$asset_name" '
        .assets
        | map(select(.name == $name))
        | sort_by(.id)
        | .[1:][]?.id
    ' "$release_response")
}

verify_asset_content() {
    local asset_file="$1"
    local asset_name="$2"
    local asset_urls_json
    local -a asset_urls
    local asset_url
    local download_status
    local expected_digest
    local published_digest

    if ! asset_urls_json="$(jq -ce --arg name "$asset_name" '
        [.assets[] | select(.name == $name)]
        | select(length > 0)
        | select(all(.[]; (
            .browser_download_url | type == "string" and length > 0
        )))
        | map(.browser_download_url)
    ' "$release_response")"; then
        echo "Existing asset metadata is incomplete: $asset_name" >&2
        exit 1
    fi
    mapfile -t asset_urls < <(jq -r '.[]' <<<"$asset_urls_json")
    expected_digest="$(sha256sum "$asset_file" | awk '{print $1}')"
    for asset_url in "${asset_urls[@]}"; do
        if [[ "$asset_url" != "$gitea_origin/"* ]]; then
            echo "Asset download URL is outside the Gitea origin: $asset_name" >&2
            exit 1
        fi
        if ! download_status="$(curl -sS \
            -o "$asset_download" \
            -w '%{http_code}' \
            -H "Authorization: token $GITHUB_TOKEN" \
            "$asset_url")"; then
            echo "Existing asset download failed: $asset_name" >&2
            exit 1
        fi
        if [[ "$download_status" != "200" ]]; then
            echo "Existing asset download failed with HTTP $download_status: $asset_name" >&2
            exit 1
        fi

        published_digest="$(sha256sum "$asset_download" | awk '{print $1}')"
        if [[ "$published_digest" != "$expected_digest" ]]; then
            echo "Existing asset content does not match: $asset_name" >&2
            exit 1
        fi
    done
}

http_status="$(fetch_release)"

case "$http_status" in
    200)
        echo "Release already exists: $tag"
        ;;
    404)
        release_payload="$(jq -n \
            --arg tag "$tag" \
            --rawfile body "$notes_file" \
            '{tag_name: $tag, name: $tag, body: $body, draft: false, prerelease: false}')"
        http_status="$(curl -sS \
            -o "$release_response" \
            -w '%{http_code}' \
            -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$release_payload" \
            "$api_root/releases")"
        case "$http_status" in
            201)
                echo "Created release: $tag"
                ;;
            409|422)
                http_status="$(fetch_release)"
                if [[ "$http_status" != "200" ]]; then
                    echo "Concurrent release lookup failed with HTTP $http_status" >&2
                    exit 1
                fi
                echo "Release was created concurrently: $tag"
                ;;
            *)
                echo "Release creation failed with HTTP $http_status" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Release lookup failed with HTTP $http_status" >&2
        exit 1
        ;;
esac

validate_release

for asset_file in "$@"; do
    asset_name="$(basename "$asset_file")"
    http_status="$(fetch_release)"
    if [[ "$http_status" != "200" ]]; then
        echo "Release refresh failed with HTTP $http_status" >&2
        exit 1
    fi
    validate_release
    if jq -e --arg name "$asset_name" '.assets | any(.name == $name)' \
        "$release_response" >/dev/null; then
        verify_asset_content "$asset_file" "$asset_name"
        remove_duplicate_assets "$asset_name"
        echo "Verified existing asset: $asset_name"
        continue
    fi
    encoded_name="$(jq -rn --arg name "$asset_name" '$name | @uri')"
    http_status="$(curl -sS \
        -o /dev/null \
        -w '%{http_code}' \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -F "attachment=@$asset_file" \
        "$api_root/releases/$release_id/assets?name=$encoded_name")"
    case "$http_status" in
        201)
            upload_message="Uploaded asset: $asset_name"
            ;;
        409|422)
            upload_message="Asset was uploaded concurrently: $asset_name"
            ;;
        *)
            echo "Asset upload failed with HTTP $http_status: $asset_name" >&2
            exit 1
            ;;
    esac
    http_status="$(fetch_release)"
    if [[ "$http_status" != "200" ]]; then
        echo "Release refresh failed with HTTP $http_status" >&2
        exit 1
    fi
    validate_release
    asset_count="$(jq --arg name "$asset_name" \
        '[.assets[] | select(.name == $name)] | length' "$release_response")"
    if [[ "$asset_count" -eq 0 ]]; then
        echo "Asset is missing after upload attempt: $asset_name" >&2
        exit 1
    fi
    verify_asset_content "$asset_file" "$asset_name"
    remove_duplicate_assets "$asset_name"
    echo "$upload_message"
done
