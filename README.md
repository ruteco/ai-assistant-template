# AI Assistant Template (as-service)

Deploys a personal AI CLI assistant (Claude Code) on an Ubuntu server with:
- Telegram bot as the interface (text + voice messages)
- Local speech-to-text for voice messages (faster-whisper)
- Yandex.Disk file sync for a shared-files folder
- Web search (built into Claude Code)
- A persistent notes file

This branch runs the assistant as a `systemd` service (`Restart=always`) —
it survives crashes and reboots, not just SSH disconnects. Want the simpler
version instead (tmux, no auto-restart, no root required)? See the `main`
branch.

## Install

SSH into the Ubuntu server as root (or a sudo-capable user), then paste:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/jokerosky/ai-assistant-template/as-service/install.sh)"
```

It installs dependencies, lays out `~/assistant-workspace` for the invoking
user (or `$SUDO_USER` if you used `sudo`), pre-downloads the faster-whisper
`small` model, registers the systemd unit, and prompts for two tokens
(Telegram bot token, Yandex.Disk token) — leave either blank to configure it
later. It enables the service but does **not** start it — see "After
install" below.

Use `bash -c "$(curl ...)"`, not `curl ... | bash` — piping breaks the token
prompts, because stdin ends up attached to the curl stream instead of your
terminal.

Safe to re-run: if `~/assistant-workspace/.initialized` already exists, it
asks for confirmation before reinstalling, and preserves `secrets/.env` and
`notes/notes.md` either way.

## After install

`/login` and Telegram pairing need one interactive run before the service
can take over unattended:

```bash
sudo -u <ASSISTANT_USER> ~/assistant-workspace/start-claude.sh
```

Inside that session:
1. `/login` — first time only, normal browser OAuth flow (or paste an API
   key / setup-token into `secrets/.env`, see "Headless auth" below, and
   skip `/login`).
2. Message your bot on Telegram once. It won't respond yet — first messages
   from an unknown chat are held for pairing approval by design.
3. Run `/telegram:access` and approve your own chat_id.

Then `Ctrl+C` out and hand off to the supervised service:

```bash
sudo systemctl start claude-assistant
sudo systemctl status claude-assistant
```

`start-claude.sh` uses `--continue`, so the service picks up the same
conversation you were just in, and keeps resuming it across restarts.

## Layout this repo ships

```
install.sh                    — the one-command installer (see above)
workspace/                    — template copied to ~/assistant-workspace
  CLAUDE.md                   — persistent instructions for the assistant
  startup-instructions.md     — heartbeat / session-start behavior
  start-claude.sh             — launches claude-cli (--continue --rc, Telegram channel)
  notes/notes.md              — freeform notes file (empty)
  secrets/.env.example        — token template; install.sh copies it to .env
  telegram-artifacts/         — downloaded Telegram attachments/voice land here
  shared-files/                — synced with Yandex.Disk
  tools/
    faster-whisper/
      transcribe.sh            — transcribe an audio file (wraps transcribe.py)
      models/                  — downloaded whisper models
    yandex-disk/
      sync.sh                  — push/pull shared-files/ via Yandex.Disk REST API
      cron-setup.sh             — installs the periodic sync cron job
```

`install.sh` additionally writes `/etc/systemd/system/claude-assistant.service`
(`User=<ASSISTANT_USER>`, `ExecStart=<workspace>/start-claude.sh`,
`Restart=always`) — not shipped as a file in this repo since it's generated
inline with the actual paths/user filled in.

## Problem points to understand before deploying

- **Headless auth is the main friction point.** Claude Code's normal login is
  a browser OAuth flow. If you're on a Pro/Max plan and this server has no
  browser, run `claude setup-token` on a machine where you're already logged
  in, then paste the resulting token into `~/assistant-workspace/secrets/.env`
  as `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY` for Console billing)
  before the first `start-claude.sh` run — or just do the browser flow if the
  server has one. install.sh does not attempt to automate this step.

- **First-message pairing is a deliberate security gate**, not a bug: the
  Telegram plugin won't respond to a chat_id it doesn't know until you
  approve the pairing (`/telegram:access`, run once inside a session). This
  prevents a stranger who finds your bot's @username from talking to your
  assistant.

- **WebSearch may be geo-restricted.** Claude Code's built-in web search tool
  is documented as US-only in some deployments. If your server's egress IP is
  outside the US, web search may silently not work.

- **faster-whisper on a small VPS can be slow.** `small` (the default here)
  is fine on modest CPUs; `medium` is noticeably heavier without a GPU.

- **Yandex.Disk sync is not continuous.** `shared-files/` syncs on a cron
  timer (`tools/yandex-disk/cron-setup.sh` installs it, default every 15
  minutes) and on-demand when the assistant calls `sync.sh` itself — not the
  instant, always-on sync you'd get from the official `yandex-disk` Linux
  daemon. That daemon exists but needs a one-time interactive device-code
  step (open a URL, type a code) that can't be scripted, so it's out of scope
  here. Don't assume a file just dropped on Yandex.Disk is present locally
  (or vice versa) without a sync first.

- **Credentials sit in plaintext `secrets/.env` on the server.** install.sh
  chmods it `600`, but you're still trusting that box. Treat the bot token,
  the Claude token, and the Yandex token as secrets — rotate/revoke from
  Anthropic's and Yandex's account settings if the server is ever
  compromised.

- **Subscription usage limits.** A Pro/Max token shares the same usage pool
  as your interactive Claude Code sessions elsewhere. Heavy assistant traffic
  through the bot competes with your own usage on other machines.

## Useful systemd commands

```bash
sudo systemctl status claude-assistant    # is it running?
sudo journalctl -u claude-assistant -f    # follow logs
sudo systemctl restart claude-assistant   # restart (resumes via --continue)
sudo systemctl stop claude-assistant      # stop, e.g. to run start-claude.sh by hand
```
