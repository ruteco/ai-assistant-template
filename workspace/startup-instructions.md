# Startup instructions

Read at the start of every new CLI session via the SessionStart hook. Do these
steps silently before handling the user's actual message.

## Heartbeat (optional)

If you want a periodic "still alive" ping, check for an existing recurring
cron job (`CronList`) and start one with `CronCreate` if none is running, e.g.
sending a short check-in message to the owner's Telegram chat_id a few times a
day. Note this is session-scoped, not durable across restarts of the
underlying process — the `claude-assistant` systemd service restarting
`start-agent.sh` (`Restart=always`) counts as a fresh session, so this
re-arms naturally each time.
