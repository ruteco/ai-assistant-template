# Assistant Environment

## System
- OS: Ubuntu (server)
- Working directory: `assistant-workspace/` (this directory) on the server
- Interface: Telegram bot (text + voice), paired to a single owner account
- Process: runs inside a tmux session started manually by the user via
  `start-agent.sh` — not a systemd service. Restarting means re-attaching to
  tmux and re-running that script (it uses `--continue` to resume).

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

## Google Calendar
`tools/google-calendar/calendar.sh {list|create|delete}` reads/writes the
primary Google Calendar. Requires `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
and `GOOGLE_CALENDAR_REFRESH_TOKEN` in `secrets/.env` — if the refresh token
is missing, tell the user to run `tools/google-calendar/auth.sh` (one-time
device-flow authorization: it prints a URL + code to open on any browser).
The access token is cached in `tools/google-calendar/.token-cache.json` for
45 minutes; don't touch that file directly.

## Secrets
`secrets/.env` holds tokens (Telegram, Yandex.Disk, Google Calendar). Never
print its contents or commit it anywhere.

## Heartbeat
See `startup-instructions.md`, loaded via the SessionStart hook.
