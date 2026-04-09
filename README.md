# Claude Persistent Bot

One-script setup for running Claude Code as a persistent background service with Discord bot support.

## Problem

Claude Code is a terminal CLI tool. When your SSH session disconnects or the server reboots, the process dies — and so does your Discord bot. This script solves that.

## What It Does

- Installs **tmux** and **bun** (if missing)
- Creates a **systemd user service** for auto-start on boot
- Enables **loginctl linger** so the service runs without login
- Sets up **Discord channel configs** (`.env`, `access.json`, `settings.json`)
- Installs **slash commands** for managing the bot inside Claude Code
- Writes an **operations manual** for daily use

## Quick Start

### Step 1: Run the setup script

```bash
# Make sure Claude Code is installed first
npm install -g @anthropic-ai/claude-code

# One-liner setup
curl -sL https://raw.githubusercontent.com/dennyandwu/claude-persistent-bot/main/setup.sh | bash
```

### Step 2: Create a Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications) → **New Application**
2. Navigate to **Bot** in the sidebar:
   - Give your bot a username
   - Click **Reset Token** → copy the token (shown only once)
   - Scroll down to **Privileged Gateway Intents** → enable **Message Content Intent**
3. Navigate to **OAuth2** → **URL Generator**:
   - Select scope: `bot`
   - Select permissions: `View Channels`, `Send Messages`, `Send Messages in Threads`, `Read Message History`, `Attach Files`, `Add Reactions`
   - Set integration type: **Guild Install**
   - Copy the **Generated URL** → open it → add the bot to your server

### Step 3: Configure the token

```bash
echo 'DISCORD_BOT_TOKEN=your_token_here' > ~/.claude/channels/discord/.env
chmod 600 ~/.claude/channels/discord/.env
```

### Step 4: Install Discord plugin

Start a Claude Code session and run:

```
/plugin install discord@claude-plugins-official
/reload-plugins
```

### Step 5: Pair your Discord account

Start Claude Code with Discord channel enabled:

```bash
tmux new -s claude-bot
claude --dangerously-skip-permissions
```

Then DM your bot on Discord — it replies with a 6-character pairing code. In the Claude Code session:

```
/discord:access pair <code>
```

Your next DM reaches the assistant. Once paired, lock down access:

```
/discord:access policy allowlist
```

### Step 6: Start the persistent service

```bash
# Detach from tmux first: Ctrl+B, D
# Then start the systemd service
systemctl --user start claude-bot
```

From now on the bot auto-starts on boot and survives SSH disconnects.

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

## File Structure

```
~/.claude/
├── start-bot.sh                    # Startup script (tmux + claude)
├── settings.json                   # Claude Code settings + Discord permissions
├── OPERATIONS.md                   # Operations manual
├── channels/
│   └── discord/
│       ├── .env                    # DISCORD_BOT_TOKEN (chmod 600)
│       ├── access.json             # Allowlist, groups, pairing policy
│       └── inbox/                  # Downloaded attachments
├── commands/
│   ├── bot-start.md                # /bot-start
│   ├── bot-stop.md                 # /bot-stop
│   ├── bot-restart.md              # /bot-restart
│   ├── bot-status.md               # /bot-status
│   └── bot-logs.md                 # /bot-logs
~/.config/systemd/user/
└── claude-bot.service              # systemd user service
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/bot-start` | Start the bot background service |
| `/bot-stop` | Stop the bot |
| `/bot-restart` | Restart the bot |
| `/bot-status` | Check bot status (process, network, tmux) |
| `/bot-logs` | View recent systemd logs |

## Discord Access Control

### DM Policies

| Policy | Behavior |
|--------|----------|
| `pairing` (default) | Unknown senders get a pairing code |
| `allowlist` | Unknown senders are silently dropped |
| `disabled` | All messages dropped |

### Manage Access (in Claude Code)

```
/discord:access                              # View current state
/discord:access pair <code>                  # Approve pairing
/discord:access allow <user_id>              # Add user by snowflake ID
/discord:access remove <user_id>             # Remove user
/discord:access policy allowlist             # Change DM policy
/discord:access group add <channel_id>       # Enable a guild channel
/discord:access group add <id> --no-mention  # No @mention required
/discord:access set ackReaction 👀            # React on receipt
```

### Guild Channels

Guild channels are opt-in per channel ID (not guild ID). By default `requireMention: true` — the bot only responds when @mentioned or replied to.

```
/discord:access group add 846209781206941736                # Enable channel
/discord:access group add 846209781206941736 --no-mention   # Respond to all messages
/discord:access group add 846209781206941736 --allow id1,id2  # Restrict to specific users
```

### Config File: `~/.claude/channels/discord/access.json`

```jsonc
{
  "dmPolicy": "pairing",                    // pairing | allowlist | disabled
  "allowFrom": ["184695080709324800"],       // User snowflake IDs allowed to DM
  "groups": {
    "846209781206941736": {                  // Channel snowflake ID
      "requireMention": true,               // Only respond to @mentions
      "allowFrom": []                        // Empty = any member
    }
  },
  "mentionPatterns": ["^hey claude\\b"],     // Regex patterns that count as mention
  "ackReaction": "👀",                       // React on receipt (empty = disabled)
  "replyToMode": "first",                   // first | all | off
  "textChunkLimit": 2000,                   // Discord max is 2000
  "chunkMode": "newline"                    // newline | length
}
```

## Shell Commands

```bash
systemctl --user start claude-bot       # Start
systemctl --user stop claude-bot        # Stop
systemctl --user restart claude-bot     # Restart
systemctl --user status claude-bot      # Status
journalctl --user -u claude-bot -n 50   # Logs
tmux attach -t claude-bot              # View Claude session (Ctrl+B, D to detach)
```

## Important: Always Use tmux

**Never run `claude` in a bare terminal on a server.** Always use tmux:

```bash
tmux new -s work         # New session
claude                   # Start Claude Code
# Ctrl+B, D              # Detach (keeps running)
tmux attach -t work      # Reattach later
```

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Bot doesn't reply | `tmux ls` | `/bot-start` or `systemctl --user start claude-bot` |
| Shows "typing" then stops | `tmux attach -t claude-bot` | `/bot-restart` |
| Service won't start | `journalctl --user -u claude-bot -n 20` | Check logs for errors |
| Token rejected | Check `.env` has correct token | Regenerate token in Developer Portal |
| Can't DM the bot | Must share a server with it | Invite bot via OAuth2 URL |
| Pairing code not working | Code expires after 1 hour | DM the bot again for a new code |

## Requirements

- Linux with systemd (Ubuntu/Debian/RHEL/etc.)
- Node.js (for Claude Code)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- [Bun](https://bun.sh) (auto-installed by setup script)
- tmux (auto-installed by setup script)

## Script Features

- **Idempotent** — safe to run multiple times, won't overwrite existing token or access config
- **Self-contained** — single file generates all configs
- **Cross-platform** — supports apt/yum/brew for tmux, nvm/fnm/mise for Node
- **Secure** — Discord token is never embedded in the script, `.env` is chmod 600

## License

MIT
