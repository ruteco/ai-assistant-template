#!/usr/bin/env bash
# Transcribes an audio file with faster-whisper (local, offline).
# Usage: transcribe.sh <audio-file> [model_size]   (default model: small)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONIOENCODING=utf-8

python3 "${SCRIPT_DIR}/transcribe.py" "$@"
