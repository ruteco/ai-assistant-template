#!/usr/bin/env bash
# One-command installer for a Telegram-backed Claude Code assistant on
# Ubuntu, supervised by systemd (auto-restart on crash/reboot). Run as root
# (or with sudo) via SSH:
#
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruteco/ai-assistant-template/as-service/install.sh)"
#
# (bash -c "$(curl ...)" — not "curl | bash" — so token prompts below can
# actually read from your terminal.)
#
# Same workspace layout as the `main` branch (tools/, secrets/, notes/, ...);
# the difference is this branch installs+enables a systemd service instead of
# leaving process supervision to a manually-started tmux session. If you
# don't need auto-restart on crash/reboot, main is simpler.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'Run as root: sudo bash -c "$(curl -fsSL .../install.sh)"' >&2
  exit 1
fi

REPO="ruteco/ai-assistant-template"
BRANCH="as-service"
ASSISTANT_USER="${SUDO_USER:-$(whoami)}"
ASSISTANT_HOME="$(getent passwd "$ASSISTANT_USER" | cut -d: -f6)"
WORKSPACE_DIR="${ASSISTANT_HOME}/assistant-workspace"
MARKER_FILE="${WORKSPACE_DIR}/.initialized"

if [[ -f "$MARKER_FILE" ]]; then
  echo "assistant-workspace already looks initialized (${MARKER_FILE} exists)."
  read -rp "Reinstall everything? Overwrites CLAUDE.md/startup-instructions.md/tools/, keeps secrets/.env and notes/notes.md, restarts the service. [y/N] " CONFIRM < /dev/tty
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted. Nothing changed."
    exit 0
  fi
fi

echo "==> Installing base dependencies"
apt-get update -y
apt-get install -y curl git ffmpeg python3 python3-pip python3-venv ca-certificates

echo "==> Installing bun (as ${ASSISTANT_USER})"
if ! su - "$ASSISTANT_USER" -c 'command -v bun' >/dev/null 2>&1; then
  su - "$ASSISTANT_USER" -c 'curl -fsSL https://bun.sh/install | bash'
fi
ln -sf "${ASSISTANT_HOME}/.bun/bin/bun" /usr/local/bin/bun

echo "==> Installing Claude Code (as ${ASSISTANT_USER})"
if ! su - "$ASSISTANT_USER" -c 'command -v claude' >/dev/null 2>&1; then
  su - "$ASSISTANT_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi
ln -sf "${ASSISTANT_HOME}/.local/bin/claude" /usr/local/bin/claude
CLAUDE_BIN="/usr/local/bin/claude"

echo "==> Installing faster-whisper (local speech-to-text)"
python3 -m pip install --break-system-packages --quiet faster-whisper

echo "==> Laying out ${WORKSPACE_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar -xz -C "$TMP_DIR"
SRC_DIR="$(find "$TMP_DIR" -maxdepth 1 -mindepth 1 -type d)/workspace"

# Preserve personal notes across a reinstall — the template ships an empty
# notes.md and cp -r below would otherwise clobber it.
NOTES_BACKUP=""
if [[ -f "${WORKSPACE_DIR}/notes/notes.md" ]]; then
  NOTES_BACKUP="$(mktemp)"
  cp "${WORKSPACE_DIR}/notes/notes.md" "$NOTES_BACKUP"
fi

mkdir -p "$WORKSPACE_DIR"
cp -r "${SRC_DIR}/." "$WORKSPACE_DIR/"

if [[ -n "$NOTES_BACKUP" ]]; then
  cp "$NOTES_BACKUP" "${WORKSPACE_DIR}/notes/notes.md"
fi

chmod +x "$WORKSPACE_DIR"/start-claude.sh "$WORKSPACE_DIR"/tools/*/*.sh

if [[ ! -f "${WORKSPACE_DIR}/secrets/.env" ]]; then
  cp "${WORKSPACE_DIR}/secrets/.env.example" "${WORKSPACE_DIR}/secrets/.env"
fi
chmod 600 "${WORKSPACE_DIR}/secrets/.env"
chown -R "$ASSISTANT_USER":"$ASSISTANT_USER" "$WORKSPACE_DIR"

echo "==> Pre-downloading the faster-whisper 'small' model"
python3 - "$WORKSPACE_DIR" <<'PYEOF'
import sys, os
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
WhisperModel("small", device="cpu", compute_type="int8",
             download_root=os.path.join(sys.argv[1], "tools/faster-whisper/models"))
PYEOF
chown -R "$ASSISTANT_USER":"$ASSISTANT_USER" "${WORKSPACE_DIR}/tools/faster-whisper/models"

echo "==> Registering the official plugin marketplace + Telegram plugin"
su - "$ASSISTANT_USER" -c "'$CLAUDE_BIN' plugin marketplace add anthropics/claude-plugins-official" || \
  echo "!! already registered or failed — check with: claude plugin marketplace list"
su - "$ASSISTANT_USER" -c "'$CLAUDE_BIN' plugin install telegram@claude-plugins-official" || \
  echo "!! already installed or failed — check with: claude plugin list"

echo ""
echo "== Telegram bot token =="
echo "From @BotFather on Telegram after /newbot. Leave blank to configure"
echo "later from inside a session with /telegram:configure."
read -rp "TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN < /dev/tty || TELEGRAM_BOT_TOKEN=""
if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" "${WORKSPACE_DIR}/secrets/.env"
  mkdir -p "${ASSISTANT_HOME}/.claude/channels/telegram"
  printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" > "${ASSISTANT_HOME}/.claude/channels/telegram/.env"
  chown -R "$ASSISTANT_USER":"$ASSISTANT_USER" "${ASSISTANT_HOME}/.claude"
  chmod 600 "${ASSISTANT_HOME}/.claude/channels/telegram/.env"
fi

echo ""
echo "== Yandex.Disk token =="
echo "OAuth token from https://oauth.yandex.ru/ for an app with disk scopes."
echo "Leave blank to configure later by editing ${WORKSPACE_DIR}/secrets/.env"
echo "and running tools/yandex-disk/cron-setup.sh yourself (as ${ASSISTANT_USER})."
read -rp "YANDEX_DISK_TOKEN: " YANDEX_DISK_TOKEN < /dev/tty || YANDEX_DISK_TOKEN=""
if [[ -n "$YANDEX_DISK_TOKEN" ]]; then
  sed -i "s|^YANDEX_DISK_TOKEN=.*|YANDEX_DISK_TOKEN=${YANDEX_DISK_TOKEN}|" "${WORKSPACE_DIR}/secrets/.env"
  su - "$ASSISTANT_USER" -c "${WORKSPACE_DIR}/tools/yandex-disk/cron-setup.sh" || \
    echo "!! cron setup failed — run ${WORKSPACE_DIR}/tools/yandex-disk/cron-setup.sh manually later"
fi

echo "==> Installing systemd service (enabled, not started yet)"
cat > /etc/systemd/system/claude-assistant.service <<EOF
[Unit]
Description=Claude Code personal assistant (Telegram)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${ASSISTANT_USER}
WorkingDirectory=${WORKSPACE_DIR}
ExecStart=${WORKSPACE_DIR}/start-claude.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable claude-assistant.service

touch "$MARKER_FILE"
chown "$ASSISTANT_USER":"$ASSISTANT_USER" "$MARKER_FILE"

cat <<MSG

==================================================================
Install done. The claude-assistant service is enabled but NOT started
yet — /login and Telegram pairing need one interactive run first:

  sudo -u ${ASSISTANT_USER} ${WORKSPACE_DIR}/start-claude.sh
  (inside: /login, then message your bot once and run /telegram:access)

Ctrl+C out once that's done, then hand off to the supervised service:

  sudo systemctl start claude-assistant
  sudo systemctl status claude-assistant

It will now auto-restart on crash and survive reboots.
==================================================================
MSG
