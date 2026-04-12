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
  ├── claude-bot.service            # Fresh session (Discord bot)
  │     └── start-bot.sh
  │           └── tmux session "claude-bot"
  │                 └── claude --dangerously-skip-permissions
  │                       └── Discord MCP server (bun)
  │                             └── Discord Gateway (WebSocket)
  └── claude-work.service          # Resume session (persistent work)
        └── start-bot.sh (SESSION_NAME=work, RESUME_SESSION_ID=xxx)
              └── tmux session "work"
                    └── claude --dangerously-skip-permissions --resume --session-id xxx
```

## systemd Services

| Service | Description | Auto-enabled |
|---------|-------------|--------------|
| `claude-bot.service` | Starts a fresh Claude Code session as the Discord bot | Yes |
| `claude-work.service` | Resumes a specific conversation on boot (set `RESUME_SESSION_ID`) | No — configure first |
| `acpx-tunnel.service` | Reverse SSH tunnel to Mac Mini (ACPX bridge, optional) | Optional |
| `elon2-sshfs.service` | SSHFS mount of Mac Mini OpenClaw workspace (depends on acpx-tunnel) | Optional |

### Resume Mode (claude-work.service)

`claude-work.service` uses the same `start-bot.sh` but passes two env vars that switch it into resume mode:

```bash
# Edit the service file to set your session ID:
systemctl --user edit claude-work.service
# Or edit directly: ~/.config/systemd/user/claude-work.service
#
# Set:
#   Environment=SESSION_NAME=work
#   Environment=RESUME_SESSION_ID=<your-session-id>

# Then enable and start:
systemctl --user enable --now claude-work.service
```

To find a session ID to resume, run inside Claude Code: `/session-id` or check `~/.claude/sessions/`.

## File Structure

```
~/.claude/
├── start-bot.sh                    # Startup script (tmux + claude, dual-mode)
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
├── claude-bot.service              # Fresh session (Discord bot)
├── claude-work.service             # Resume session (work)
├── acpx-tunnel.service             # ACPX reverse SSH tunnel (optional)
└── elon2-sshfs.service             # Mac Mini SSHFS mount (optional)
```

## ACPX Bridge (Optional)

ACPX connects a remote Claude Code agent (this server) to an **OpenClaw Gateway** running on a Mac Mini via a reverse SSH tunnel. This lets Claude Code on the server act as a remote node — executing tasks in OpenClaw workspaces over SSH.

### How it works

```
Server (this machine)
  └── acpx-tunnel.service
        └── autossh reverse tunnel → Mac Mini (:2222 → server :22)
              └── OpenClaw Gateway (Mac Mini) calls back via tunnel
                    └── Claude Code agent runs tasks in shared workspace
elon2-sshfs.service (optional)
  └── SSHFS mount: Mac Mini OpenClaw workspace → ~/elon2-workspace/openclaw/
```

### Setup with --with-acpx

If you're setting up the ACPX bridge, after running `setup.sh`:

1. Copy your SSH key for the Mac Mini to `~/.ssh/id_ed25519_macmini`
2. Create `acpx-tunnel.service` pointing to your Mac Mini's Tailscale IP:

```bash
cat > ~/.config/systemd/user/acpx-tunnel.service << EOF
[Unit]
Description=ACPX Reverse SSH Tunnel to Mac Mini
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStart=/usr/bin/autossh -M 0 -N \
  -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" \
  -o "StrictHostKeyChecking no" \
  -i $HOME/.ssh/id_ed25519_macmini \
  -R 2222:127.0.0.1:22 <mac-mini-user>@<mac-mini-tailscale-ip>

[Install]
WantedBy=default.target
EOF
systemctl --user enable --now acpx-tunnel.service
```

3. Optionally mount the OpenClaw workspace via SSHFS:

```bash
sudo apt-get install -y sshfs
# Then create elon2-sshfs.service pointing to your workspace path
```

### Multi-Agent Config Isolation

When running multiple Claude Code agents on the same server, isolate their configs using `CLAUDE_CONFIG_DIR`:

```bash
# Agent 1: Discord bot (uses default ~/.claude)
claude --dangerously-skip-permissions

# Agent 2: Work/ACPX agent (isolated config + workspace)
CLAUDE_CONFIG_DIR=~/.claude-work claude --dangerously-skip-permissions

# In systemd service, set:
Environment=CLAUDE_CONFIG_DIR=/home/ubuntu/.claude-work
```

Each `CLAUDE_CONFIG_DIR` gets its own `settings.json`, `sessions/`, `commands/`, and `channels/` — agents don't share memory or session history.

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
