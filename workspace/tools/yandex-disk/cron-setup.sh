#!/usr/bin/env bash
# Installs a periodic cron entry that syncs shared-files/ with Yandex.Disk.
# Run once, as the assistant user (not root), from anywhere.
#
# Usage: cron-setup.sh [interval_minutes]   (default: 15)

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SH="${WORKSPACE_DIR}/tools/yandex-disk/sync.sh"
SHARED_DIR="${WORKSPACE_DIR}/shared-files"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"
INTERVAL="${1:-15}"

CRON_CMD="*/${INTERVAL} * * * * set -a; . ${ENV_FILE}; set +a; ${SYNC_SH} push ${SHARED_DIR} >> ${WORKSPACE_DIR}/tools/yandex-disk/sync.log 2>&1"
MARKER="# ai-assistant yandex-disk sync"

( crontab -l 2>/dev/null | grep -vF "$MARKER"; echo "${CRON_CMD} ${MARKER}" ) | crontab -

echo "Installed cron job: sync shared-files/ every ${INTERVAL} minutes."
echo "Check it with: crontab -l"
