# AI Assistant Template

Deploys a personal AI CLI assistant (Claude Code) on an Ubuntu server with:
- Telegram bot as the interface (text + voice messages)
- Local speech-to-text for voice messages (faster-whisper)
- Yandex.Disk file sync for a workspace folder
- Web search (built into Claude Code)
- A persistent notes file

## How it works

`claude` runs as a long-lived process on the server (via systemd), listening for
messages through the official Telegram channel plugin. When you send a voice
message, it's downloaded, transcribed locally with faster-whisper, and handled
like a normal chat turn — same flow as this Windows setup, just self-hosted.

## Before you run `deploy.sh`

Three things cannot be scripted end-to-end because they require a one-time
interactive/browser step. Do these first (or right after the script finishes,
per the step it pauses on):

1. **Claude Code auth token** (blocks everything — do this first)
   - If you're on a Pro/Max plan: on *any* machine where you're already logged
     into Claude Code, run `claude setup-token`. It prints a URL, you approve
     it in a browser, and it gives you a long-lived token
     (`CLAUDE_CODE_OAUTH_TOKEN`). Paste that into `.env` on the server.
   - If you have Anthropic Console API billing instead: use `ANTHROPIC_API_KEY`
     in `.env`. Note this bills per-token, separately from a Pro/Max
     subscription — check which one you actually want before deploying.

2. **Telegram bot token** — talk to [@BotFather](https://t.me/BotFather) on
   Telegram, `/newbot`, copy the token into `.env` as `TELEGRAM_BOT_TOKEN`.
   This part is fully non-interactive.

3. **Yandex.Disk OAuth token** — go to https://yandex.ru/dev/disk-api/,
   register an app (or use an existing one) with the `cloud_api:disk.app_folder`
   or `cloud_api:disk.read`/`cloud_api:disk.write` scopes, then get a token via
   the OAuth debug flow at https://oauth.yandex.ru/. Put it in `.env` as
   `YANDEX_DISK_TOKEN`. This is the REST API approach (recommended for a
   headless server — see "Yandex.Disk: two options" below for the alternative).

## Problem points to understand before deploying

- **Headless auth is the main friction point.** Claude Code's normal login is
  a browser OAuth flow. `setup-token` sidesteps it, but you generate the token
  *elsewhere* (a machine with a browser) and copy it in — the deploy script
  cannot obtain it for you.

- **The process must stay alive continuously**, unlike a one-off CLI run. This
  script installs a `systemd` service with `Restart=always` for that reason.
  If you only run `claude --channels ...` by hand in a terminal, Telegram
  messages stop being received the moment you close the SSH session.

- **First-message pairing is a deliberate security gate**, not a bug: the
  Telegram plugin won't respond to a chat_id it doesn't know until you approve
  the pairing (via `/telegram:access` inside a session, run once). This
  prevents a stranger who finds your bot's @username from talking to your
  assistant. Budget for this manual step after first boot.

- **WebSearch may be geo-restricted.** Claude Code's built-in web search tool
  is documented as US-only in some deployments. If your Ubuntu server's egress
  IP is outside the US, web search may silently not work — worth testing
  right after deploy, not assuming it'll just work because it does on your
  Windows machine.

- **faster-whisper on a small VPS can be slow.** The `small` model is fine on
  modest CPUs; `medium` is noticeably heavier without a GPU. Size the server
  (or pick the model) accordingly — a 1-2 vCPU box transcribing with `medium`
  can take much longer than the voice clip itself.

- **Yandex.Disk: two options, pick one:**
  - *REST API + OAuth token* (what `.env`'s `YANDEX_DISK_TOKEN` is for): the
    script writes a small helper (`scripts/yandex_sync.sh`) that pushes/pulls
    a specific folder via HTTP calls. No daemon, no interactive step at deploy
    time, but it's sync-on-trigger (cron or on-demand), not instant/continuous.
  - *Official `yandex-disk` Linux daemon*: true continuous background sync of
    one folder, closer to what you'd get on Windows/Mac — but its `yandex-disk
    setup` command requires a one-time interactive device-code step (open a
    URL, type a code shown in the terminal). Not scriptable, but only needed
    once. See `scripts/yandex_disk_daemon_setup.md` if you'd rather use this.

- **Credentials sit in a plaintext `.env` on the server.** The script chmods
  it `600`, but you're still trusting that box. Treat the bot token, the
  Claude token, and the Yandex token as secrets — rotate/revoke from
  Anthropic's and Yandex's account settings if the server is ever compromised.

- **Subscription usage limits.** A Pro/Max token shares the same usage pool as
  your interactive Claude Code sessions elsewhere. Heavy assistant traffic
  through the bot competes with your own usage on other machines.

## Layout this repo ships

```
deploy.sh                          — main setup script (see below)
.env.example                       — copy to .env, fill in tokens
claude-assistant.service.template  — systemd unit installed by deploy.sh
workspace/
  CLAUDE.md                        — persistent instructions for the assistant
  startup-instructions.md          — heartbeat / session-start behavior
  notes/notes.md                   — freeform notes file
scripts/
  yandex_sync.sh                   — push/pull a folder via Yandex.Disk REST API
  yandex_disk_daemon_setup.md      — notes for the alternative daemon route
```

## Running it

```bash
git clone <this repo> ai-assistant-template
cd ai-assistant-template
cp .env.example .env
$EDITOR .env   # fill in TELEGRAM_BOT_TOKEN, CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY, YANDEX_DISK_TOKEN
sudo ./deploy.sh
```

The script installs dependencies, installs Claude Code + the Telegram plugin,
lays out the workspace, and installs+starts a systemd service. Watch its
output — it pauses and prints instructions for the one manual step (approving
your own Telegram pairing) it cannot do for you.
