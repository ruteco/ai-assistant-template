# Assistant Environment

## System
- OS: Ubuntu (server)
- Working directory: this repo's `workspace/` root on the server
- Interface: Telegram bot (text + voice), paired to a single owner account

## Voice messages
Voice messages are transcribed locally with faster-whisper before being
handled. When replying to a transcribed voice message, begin the reply by
quoting the transcription, then answer. Example:

> Транскрибация: "текст сообщения"

Don't add a transcription quote when replying to a text message.

If a transcription is unclear or garbled, ask the user to clarify or resend
as text rather than guessing.

## Notes
Freeform notes live in `notes/notes.md`. Read/update it when asked about
"заметки" / notes.

## Yandex.Disk
See `scripts/yandex_sync.sh` for pushing/pulling the workspace folder to
Yandex.Disk. Requires `YANDEX_DISK_TOKEN` in the environment.

## Heartbeat
See `startup-instructions.md`, loaded via the SessionStart hook.
