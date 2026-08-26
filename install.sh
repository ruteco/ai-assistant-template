#!/usr/bin/env bash
# One-command installer for a Telegram-backed Claude Code assistant on
# Ubuntu. Copy-paste into an SSH session on the target server:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jokerosky/ai-assistant-template/main/install.sh)"
#
# (bash -c "$(curl ...)" — not "curl | bash" — so token prompts below can
# actually read from your terminal.)
#
# Installs dependencies, lays out ~/assistant-workspace from this repo's
# workspace/ template, and prompts for the Telegram bot token and Yandex.Disk
# token (leave either blank to configure it later). Does NOT start tmux or
# claude-cli — that's a manual step, see the final message this script
# prints.

set -euo pipefail

REPO="jokerosky/ai-assistant-template"
BRANCH="main"
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/assistant-workspace}"
MARKER_FILE="${WORKSPACE_DIR}/.initialized"

SUDO=""
if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
fi

if [[ -f "$MARKER_FILE" ]]; then
  echo "assistant-workspace already looks initialized (${MARKER_FILE} exists)."
  read -rp "Reinstall everything? Overwrites CLAUDE.md/startup-instructions.md/tools/, keeps secrets/.env and notes/notes.md as-is. [y/N] " CONFIRM < /dev/tty
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted. Nothing changed."
    exit 0
  fi
fi

echo "==> Installing base dependencies"
$SUDO apt-get update -y
$SUDO apt-get install -y curl git ffmpeg python3 python3-pip python3-venv tmux ca-certificates

echo "==> Installing bun"
if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash
fi
export PATH="$HOME/.bun/bin:$PATH"

echo "==> Installing Claude Code"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
export PATH="$HOME/.local/bin:$PATH"

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

echo "==> Pre-downloading the faster-whisper 'small' model"
python3 - "$WORKSPACE_DIR" <<'PYEOF'
import sys, os
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
from faster_whisper import WhisperModel
WhisperModel("small", device="cpu", compute_type="int8",
             download_root=os.path.join(sys.argv[1], "tools/faster-whisper/models"))
PYEOF

echo "==> Registering the official plugin marketplace + Telegram plugin"
claude plugin marketplace add anthropics/claude-plugins-official || \
  echo "!! already registered or failed — check with: claude plugin marketplace list"
claude plugin install telegram@claude-plugins-official || \
  echo "!! already installed or failed — check with: claude plugin list"

echo ""
echo "== Telegram bot token =="
echo "From @BotFather on Telegram after /newbot. Leave blank to configure"
echo "later from inside a session with /telegram:configure."
read -rp "TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN < /dev/tty || TELEGRAM_BOT_TOKEN=""
if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" "${WORKSPACE_DIR}/secrets/.env"
  mkdir -p "$HOME/.claude/channels/telegram"
  printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" > "$HOME/.claude/channels/telegram/.env"
  chmod 600 "$HOME/.claude/channels/telegram/.env"
fi

echo ""
echo "== Yandex.Disk token =="
echo "OAuth token from https://oauth.yandex.ru/ for an app with disk scopes."
echo "Leave blank to configure later by editing ${WORKSPACE_DIR}/secrets/.env"
echo "and running tools/yandex-disk/cron-setup.sh yourself."
read -rp "YANDEX_DISK_TOKEN: " YANDEX_DISK_TOKEN < /dev/tty || YANDEX_DISK_TOKEN=""
if [[ -n "$YANDEX_DISK_TOKEN" ]]; then
  sed -i "s|^YANDEX_DISK_TOKEN=.*|YANDEX_DISK_TOKEN=${YANDEX_DISK_TOKEN}|" "${WORKSPACE_DIR}/secrets/.env"
  "${WORKSPACE_DIR}/tools/yandex-disk/cron-setup.sh" || \
    echo "!! cron setup failed — run ${WORKSPACE_DIR}/tools/yandex-disk/cron-setup.sh manually later"
fi

touch "$MARKER_FILE"

cat <<MSG

==================================================================
Install done. Manual steps left (this script does none of them):

  1. tmux new -s assistant
  2. cd ${WORKSPACE_DIR} && ./start-claude.sh
  3. Inside Claude Code: /login   (first time only)
  4. Message your bot on Telegram once, then inside the session run
     /telegram:access
     and approve your own chat_id — first messages from an unknown
     chat are held for pairing approval by design.

Detach from tmux any time with Ctrl+b d — the session (and
claude-cli) keeps running. Reattach with: tmux attach -t assistant
==================================================================
MSG
