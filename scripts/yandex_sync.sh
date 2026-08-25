#!/usr/bin/env bash
# Push/pull the local workspace folder to/from Yandex.Disk via its REST API.
# Requires YANDEX_DISK_TOKEN and YANDEX_DISK_REMOTE_PATH in the environment
# (sourced from .env by the caller). This is trigger-based sync, not a
# continuous daemon — run it from cron or call it from within a session.
#
# Usage:
#   yandex_sync.sh push <local_dir>   # upload every file under local_dir
#   yandex_sync.sh pull <local_dir>   # download everything under the remote path

set -euo pipefail

API="https://cloud-api.yandex.net/v1/disk"
AUTH_HEADER="Authorization: OAuth ${YANDEX_DISK_TOKEN:?YANDEX_DISK_TOKEN not set}"
REMOTE_ROOT="${YANDEX_DISK_REMOTE_PATH:?YANDEX_DISK_REMOTE_PATH not set}"

ensure_remote_dir() {
  local path="$1"
  curl -s -X PUT -H "$AUTH_HEADER" \
    "${API}/resources?path=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$path")" \
    >/dev/null || true
}

push() {
  local local_dir="$1"
  ensure_remote_dir "$REMOTE_ROOT"
  find "$local_dir" -type f | while read -r file; do
    local rel="${file#$local_dir/}"
    local remote_path="${REMOTE_ROOT}/${rel}"
    local remote_dir
    remote_dir=$(dirname "$remote_path")
    ensure_remote_dir "$remote_dir"

    local upload_url
    upload_url=$(curl -s -H "$AUTH_HEADER" \
      "${API}/resources/upload?path=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$remote_path")&overwrite=true" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['href'])")

    curl -s -T "$file" "$upload_url" >/dev/null
    echo "pushed: $rel"
  done
}

pull() {
  local local_dir="$1"
  mkdir -p "$local_dir"
  # List files under the remote path and download each.
  curl -s -H "$AUTH_HEADER" \
    "${API}/resources?path=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$REMOTE_ROOT")&limit=1000&fields=_embedded.items.path,_embedded.items.type" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('_embedded', {}).get('items', []):
    if item['type'] == 'file':
        print(item['path'])
" | while read -r remote_path; do
    local rel="${remote_path#${REMOTE_ROOT}/}"
    local dest="${local_dir}/${rel}"
    mkdir -p "$(dirname "$dest")"

    local download_url
    download_url=$(curl -s -H "$AUTH_HEADER" \
      "${API}/resources/download?path=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$remote_path")" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['href'])")

    curl -s -o "$dest" "$download_url"
    echo "pulled: $rel"
  done
}

case "${1:-}" in
  push) push "${2:?local_dir required}" ;;
  pull) pull "${2:?local_dir required}" ;;
  *) echo "usage: $0 {push|pull} <local_dir>" >&2; exit 1 ;;
esac
