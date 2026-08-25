#!/usr/bin/env bash
# Deploys a personal Claude Code assistant on Ubuntu, wired to Telegram
# (text + voice) with local speech-to-text and Yandex.Disk sync.
#
# Run as root (sudo ./deploy.sh) from the repo root, after copying
# .env.example to .env and filling it in. See README.md for the manual
# prerequisites (auth token, bot token, Yandex token) this script cannot do
# for you.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REPO_DIR}/.env"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo ./deploy.sh" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo ".env not found. Copy .env.example to .env and fill it in first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${ASSISTANT_HOME:=/opt/ai-assistant}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required in .env}"

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in .env before running." >&2
  echo "See README.md > 'Before you run deploy.sh' for how to generate one." >&2
  exit 1
fi

ASSISTANT_USER="${SUDO_USER:-$(whoami)}"

echo "==> Installing base dependencies"
apt-get update -y
apt-get install -y curl git ffmpeg python3 python3-pip python3-venv unzip ca-certificates

echo "==> Installing bun (for the Telegram plugin's MCP server)"
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash
  # bun installs to ~/.bun/bin; make it available for the target user's shell
  ln -sf "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.bun/bin/bun" /usr/local/bin/bun
fi

echo "==> Installing Claude Code"
if ! command -v claude >/dev/null 2>&1; then
  su - "$ASSISTANT_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'
  ln -sf "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.local/bin/claude" /usr/local/bin/claude
fi
CLAUDE_BIN="$(command -v claude)"

echo "==> Installing faster-whisper (local speech-to-text)"
python3 -m pip install --break-system-packages --quiet faster-whisper

echo "==> Laying out workspace at ${ASSISTANT_HOME}"
mkdir -p "$ASSISTANT_HOME"
cp -rn "${REPO_DIR}/workspace/." "$ASSISTANT_HOME/"
mkdir -p "$ASSISTANT_HOME/scripts"
cp "${REPO_DIR}/scripts/yandex_sync.sh" "$ASSISTANT_HOME/scripts/"
chmod +x "$ASSISTANT_HOME/scripts/yandex_sync.sh"
cp "$ENV_FILE" "$ASSISTANT_HOME/.env"
chmod 600 "$ASSISTANT_HOME/.env"
chown -R "$ASSISTANT_USER":"$ASSISTANT_USER" "$ASSISTANT_HOME"

echo "==> Registering the official plugin marketplace + Telegram plugin"
su - "$ASSISTANT_USER" -c "'$CLAUDE_BIN' plugin marketplace add anthropics/claude-plugins-official" || \
  echo "!! Marketplace add failed or already registered — check manually with: claude plugin marketplace list"
su - "$ASSISTANT_USER" -c "'$CLAUDE_BIN' plugin install telegram@claude-plugins-official" || \
  echo "!! Plugin install failed or already installed — check manually with: claude plugin list"

echo "==> Configuring Telegram bot token"
mkdir -p "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.claude/channels/telegram"
cat > "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.claude/channels/telegram/.env" <<EOF
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
EOF
chown -R "$ASSISTANT_USER":"$ASSISTANT_USER" "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.claude"
chmod 600 "$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)/.claude/channels/telegram/.env"

echo "==> Installing systemd service"
sed \
  -e "s#__ASSISTANT_USER__#${ASSISTANT_USER}#g" \
  -e "s#__ASSISTANT_HOME__#${ASSISTANT_HOME}#g" \
  -e "s#__CLAUDE_BIN__#${CLAUDE_BIN}#g" \
  "${REPO_DIR}/claude-assistant.service.template" > /etc/systemd/system/claude-assistant.service

systemctl daemon-reload
systemctl enable claude-assistant.service
systemctl restart claude-assistant.service

echo ""
echo "==> Done. Service status:"
systemctl status claude-assistant.service --no-pager || true

cat <<'MSG'

==================================================================
MANUAL STEP STILL NEEDED
==================================================================
Message your bot on Telegram once. It won't respond yet — first
messages from an unknown chat_id are held for pairing approval by
design. To approve it:

  sudo -u <ASSISTANT_USER> claude
  (inside the session) /telegram:access

Follow its prompts to approve your chat_id. After that, the running
systemd service will start responding to you normally.

If you're using the Yandex.Disk REST API route, test it with:
  ASSISTANT_HOME/scripts/yandex_sync.sh push ASSISTANT_HOME/notes

If you'd rather have continuous folder sync instead, see
scripts/yandex_disk_daemon_setup.md for the yandex-disk daemon route
(also requires one interactive step).
==================================================================
MSG
