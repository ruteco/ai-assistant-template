#!/usr/bin/env bash
# Starts the assistant. Normally launched by the claude-assistant systemd
# service (see install.sh) — run it manually only for the one-time /login
# and Telegram pairing step, or to debug.
#
# --continue resumes the most recent session (starts fresh if there is none).
# --rc makes the session visible/controllable from claude.ai/code and the
# mobile app. The Telegram channel is attached by default.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ -f secrets/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source secrets/.env
  set +a
fi

claude --continue --rc --channels plugin:telegram@claude-plugins-official
