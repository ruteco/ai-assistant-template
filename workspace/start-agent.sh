#!/usr/bin/env bash
# Starts the assistant. Run this yourself inside a tmux session so it
# survives SSH disconnects — this script does not start tmux for you.
#
#   tmux new -s assistant
#   ./start-agent.sh
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
