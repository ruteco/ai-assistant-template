#!/usr/bin/env bash
# One-time Google Calendar authorization via OAuth device flow — no browser
# or redirect URI needed on this machine, just any device to open a URL and
# type a code on.
#
# Prerequisite: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in secrets/.env,
# from a Google Cloud Console OAuth Client (type "TVs and Limited Input
# devices") with the Calendar API enabled on that project.
#
# Usage: auth.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"
SCOPE="https://www.googleapis.com/auth/calendar"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID not set in secrets/.env}"
: "${GOOGLE_CLIENT_SECRET:?GOOGLE_CLIENT_SECRET not set in secrets/.env}"

echo "Requesting device code..."
DEVICE_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/device/code \
  -d "client_id=${GOOGLE_CLIENT_ID}" \
  -d "scope=${SCOPE}")

DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['device_code'])")
USER_CODE=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['user_code'])")
VERIFICATION_URL=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['verification_url'])")
INTERVAL=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin).get('interval', 5))")
EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['expires_in'])")

echo ""
echo "Open ${VERIFICATION_URL} on any device and enter code: ${USER_CODE}"
echo "Waiting for approval (expires in $((EXPIRES_IN / 60)) minutes)..."

DEADLINE=$(($(date +%s) + EXPIRES_IN))
while [[ $(date +%s) -lt $DEADLINE ]]; do
  sleep "$INTERVAL"

  TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d "client_id=${GOOGLE_CLIENT_ID}" \
    -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
    -d "device_code=${DEVICE_CODE}" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code")

  ERROR=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin).get('error', ''))")

  if [[ -z "$ERROR" ]]; then
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['refresh_token'])")
    sed -i "s|^GOOGLE_CALENDAR_REFRESH_TOKEN=.*|GOOGLE_CALENDAR_REFRESH_TOKEN=${REFRESH_TOKEN}|" "$ENV_FILE"
    echo "Authorized. Refresh token saved to secrets/.env."
    exit 0
  elif [[ "$ERROR" == "authorization_pending" ]]; then
    continue
  elif [[ "$ERROR" == "slow_down" ]]; then
    INTERVAL=$((INTERVAL + 5))
    continue
  else
    echo "Authorization failed: ${ERROR}" >&2
    exit 1
  fi
done

echo "Timed out waiting for authorization — run auth.sh again." >&2
exit 1
