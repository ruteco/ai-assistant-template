# Assistant Environment

## System
- OS: Ubuntu (server)
- Working directory: `assistant-workspace/` (this directory) on the server
- Interface: Telegram bot (text + voice), paired to a single owner account
- Process: runs as the `claude-assistant` systemd service (`Restart=always`),
  which supervises `start-claude.sh`. Crashes and reboots auto-restart it —
  `--continue` in that script means it resumes the last conversation rather
  than starting over each time.

## Voice messages
Voice messages arrive as attachments — download them into
`telegram-artifacts/`, then transcribe locally with
`tools/faster-whisper/transcribe.sh <file>` (small model by default). When
replying to a transcribed voice message, begin the reply by quoting the
transcription, then answer. Example:

> Транскрибация: "текст сообщения"

Don't add a transcription quote when replying to a text message.

If a transcription is unclear or garbled, ask the user to clarify or resend
as text rather than guessing.

## Notes
Freeform notes live in `notes/notes.md`. Read/update it when asked about
"заметки" / notes.

## Shared files & Yandex.Disk
`shared-files/` syncs with Yandex.Disk — periodically via a cron job
(`tools/yandex-disk/cron-setup.sh` installs it) and on-demand by calling
`tools/yandex-disk/sync.sh {push|pull} shared-files`. Requires
`YANDEX_DISK_TOKEN` and `YANDEX_DISK_REMOTE_PATH` in `secrets/.env`. It is
NOT continuous — don't assume a file just dropped on Yandex.Disk is present
locally (or vice versa) without syncing first.

## Secrets
`secrets/.env` holds tokens (Telegram, Yandex.Disk). Never print its
contents or commit it anywhere.

## Heartbeat
See `startup-instructions.md`, loaded via the SessionStart hook.
