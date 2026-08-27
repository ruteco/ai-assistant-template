#!/usr/bin/env bash
# Google Calendar API wrapper. The access token is cached on disk for 45
# minutes (Google's tokens last 60) so routine calls don't hit the token
# endpoint every time — only auth.sh's one-time device flow and this cache
# ever touch the refresh token.
#
# Usage:
#   calendar.sh list [max_results]
#   calendar.sh create <summary> <start_iso8601> <end_iso8601>
#   calendar.sh delete <event_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"
TOKEN_CACHE="${SCRIPT_DIR}/.token-cache.json"
CACHE_TTL=$((45 * 60))
API="https://www.googleapis.com/calendar/v3"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID not set in secrets/.env}"
: "${GOOGLE_CLIENT_SECRET:?GOOGLE_CLIENT_SECRET not set in secrets/.env}"
: "${GOOGLE_CALENDAR_REFRESH_TOKEN:?GOOGLE_CALENDAR_REFRESH_TOKEN not set — run auth.sh first}"

get_access_token() {
  if [[ -f "$TOKEN_CACHE" ]]; then
    local cached_at now
    cached_at=$(python3 -c "import json;print(json.load(open('${TOKEN_CACHE}'))['cached_at'])" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - cached_at < CACHE_TTL )); then
      python3 -c "import json;print(json.load(open('${TOKEN_CACHE}'))['access_token'])"
      return
    fi
  fi

  local response access_token
  response=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d "client_id=${GOOGLE_CLIENT_ID}" \
    -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
    -d "refresh_token=${GOOGLE_CALENDAR_REFRESH_TOKEN}" \
    -d "grant_type=refresh_token")

  access_token=$(echo "$response" | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")

  python3 -c "import json,time;json.dump({'access_token':'${access_token}','cached_at':int(time.time())}, open('${TOKEN_CACHE}','w'))"
  chmod 600 "$TOKEN_CACHE"
  echo "$access_token"
}

ACCESS_TOKEN=$(get_access_token)

list_events() {
  local max="${1:-10}"
  curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${API}/calendars/primary/events?maxResults=${max}&orderBy=startTime&singleEvents=true&timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    start = item.get('start', {}).get('dateTime', item.get('start', {}).get('date', '?'))
    print(f\"{item['id']}  {start}  {item.get('summary', '(no title)')}\")
"
}

create_event() {
  local summary="$1" start="$2" end="$3"
  curl -s -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" \
    "${API}/calendars/primary/events" \
    -d "{\"summary\":\"${summary}\",\"start\":{\"dateTime\":\"${start}\"},\"end\":{\"dateTime\":\"${end}\"}}" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('htmlLink', d))"
}

delete_event() {
  local event_id="$1"
  curl -s -X DELETE -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${API}/calendars/primary/events/${event_id}"
  echo "deleted: ${event_id}"
}

case "${1:-}" in
  list) list_events "${2:-10}" ;;
  create) create_event "${2:?summary required}" "${3:?start ISO8601 required}" "${4:?end ISO8601 required}" ;;
  delete) delete_event "${2:?event_id required}" ;;
  *) echo "usage: $0 {list [max]|create <summary> <start_iso8601> <end_iso8601>|delete <event_id>}" >&2; exit 1 ;;
esac
