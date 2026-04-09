# Claude Persistent Bot

One-script setup for running Claude Code as a persistent background service with Discord bot support.

## Problem

Claude Code is a terminal CLI tool. When your SSH session disconnects or the server reboots, the process dies — and so does your Discord bot. This script solves that by setting up:

- **tmux** — keeps Claude Code alive after SSH disconnect
- **systemd user service** — auto-starts on boot
- **loginctl linger** — runs user services without login
- **Slash commands** — manage the bot from within Claude Code

## Quick Start

```bash
# 1. Make sure Claude Code is installed
npm install -g @anthropic-ai/claude-code

# 2. Run the setup script
curl -sL https://raw.githubusercontent.com/dennyandwu/claude-persistent-bot/main/setup.sh | bash

# 3. Configure Discord bot token (if using Discord plugin)
mkdir -p ~/.claude/channels/discord
echo 'DISCORD_BOT_TOKEN=your_token_here' > ~/.claude/channels/discord/.env
chmod 600 ~/.claude/channels/discord/.env

# 4. Start the bot
systemctl --user start claude-bot
```

## What It Sets Up

```
~/.claude/
├── start-bot.sh                          # Startup script (tmux + claude)
├── OPERATIONS.md                         # Operations manual (Chinese)
├── commands/
│   ├── bot-start.md                      # /bot-start
│   ├── bot-stop.md                       # /bot-stop
│   ├── bot-restart.md                    # /bot-restart
│   ├── bot-status.md                     # /bot-status
│   ├── bot-logs.md                       # /bot-logs
│   └── setup-server.md                   # /setup-server
~/.config/systemd/user/
└── claude-bot.service                    # systemd user service
```

## Architecture

```
systemd (boot)
  └── claude-bot.service
        └── start-bot.sh
              └── tmux session "claude-bot"
                    └── claude --dangerously-skip-permissions
                          └── Discord MCP server (bun)
                                └── Discord Gateway (WebSocket)
```

## Slash Commands

Use these inside Claude Code to manage the bot:

| Command | Description |
|---------|-------------|
| `/bot-start` | Start the bot background service |
| `/bot-stop` | Stop the bot |
| `/bot-restart` | Restart the bot |
| `/bot-status` | Check bot status (process, network, tmux) |
| `/bot-logs` | View recent systemd logs |
| `/setup-server` | Re-run setup on current server |

## Shell Commands

```bash
systemctl --user start claude-bot       # Start
systemctl --user stop claude-bot        # Stop
systemctl --user restart claude-bot     # Restart
systemctl --user status claude-bot      # Status
tmux attach -t claude-bot              # Attach to bot session (Ctrl+B, D to detach)
```

## Important: Always Use tmux

**Never run `claude` in a bare terminal on a server.** Always use tmux:

```bash
# Start a new session
tmux new -s work

# Inside tmux, run claude
claude

# Detach (keep running): Ctrl+B, then D
# Reattach later:
tmux attach -t work
```

## Requirements

- Linux with systemd (Ubuntu/Debian/RHEL/etc.)
- Node.js (for Claude Code)
- Claude Code CLI (`@anthropic-ai/claude-code`)
- tmux (auto-installed by setup script)

## Script Features

- **Idempotent** — safe to run multiple times
- **Self-contained** — single file generates all configs
- **Cross-platform** — supports apt/yum/brew for tmux, nvm/fnm/mise for Node
- **Secure** — Discord token is not embedded, configured separately

## License

MIT
