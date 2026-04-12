#!/bin/bash
# Claude Code Persistent Bot Setup
# 在新服务器上一键配置 Claude Code + Discord Bot 持久化运行环境
# 用法: curl -sL <url> | bash  或  bash setup.sh
#
# 幂等设计 — 重复运行安全，只更新有变化的部分。

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SYSTEMD_DIR="$HOME/.config/systemd/user"
DISCORD_DIR="$CLAUDE_DIR/channels/discord"

info()  { echo -e "\033[32m[OK]\033[0m $1"; }
warn()  { echo -e "\033[33m[!!]\033[0m $1"; }
step()  { echo -e "\n\033[36m==>\033[0m $1"; }

# ── 0. 前置检查 ──────────────────────────────────────────────

step "检查依赖"

if ! command -v claude &>/dev/null; then
  warn "claude 未安装，请先安装 Claude Code: npm install -g @anthropic-ai/claude-code"
  exit 1
fi
info "claude $(claude --version 2>/dev/null | head -1)"

if ! command -v tmux &>/dev/null; then
  echo "  安装 tmux..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq tmux
  elif command -v yum &>/dev/null; then
    sudo yum install -y tmux
  elif command -v brew &>/dev/null; then
    brew install tmux
  else
    warn "无法自动安装 tmux，请手动安装"
    exit 1
  fi
fi
info "tmux $(tmux -V)"

if ! command -v bun &>/dev/null; then
  echo "  安装 bun（Discord 插件运行时）..."
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
fi
info "bun $(bun --version 2>/dev/null)"

# ── 1. 目录结构 ──────────────────────────────────────────────

step "创建目录结构"

mkdir -p "$CLAUDE_DIR" "$COMMANDS_DIR" "$SYSTEMD_DIR" "$DISCORD_DIR"
info "$CLAUDE_DIR"
info "$COMMANDS_DIR"
info "$SYSTEMD_DIR"
info "$DISCORD_DIR"

# ── 2. Discord 配置 ─────────────────────────────────────────

step "配置 Discord"

# .env — 不覆盖已有 token
if [ ! -f "$DISCORD_DIR/.env" ]; then
  cat > "$DISCORD_DIR/.env" << 'ENV'
DISCORD_BOT_TOKEN=replace-with-your-discord-bot-token
ENV
  chmod 600 "$DISCORD_DIR/.env"
  info ".env 模板已创建（需填入 bot token）"
else
  info ".env 已存在，跳过"
fi

# access.json — 不覆盖已有配置
if [ ! -f "$DISCORD_DIR/access.json" ]; then
  cat > "$DISCORD_DIR/access.json" << 'ACCESS'
{
  "dmPolicy": "pairing",
  "allowFrom": [],
  "groups": {},
  "pending": {}
}
ACCESS
  info "access.json 初始化（pairing 模式）"
else
  info "access.json 已存在，跳过"
fi

# inbox 目录 — 存放 Discord 附件下载
mkdir -p "$DISCORD_DIR/inbox"
info "inbox/"

# settings.json — 合并 Discord 插件权限，不覆盖已有设置
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  # 检查是否已包含 discord 权限
  if ! grep -q 'mcp__plugin_discord_discord' "$SETTINGS_FILE" 2>/dev/null; then
    warn "settings.json 已存在但未包含 Discord 权限，请手动添加："
    echo '    "mcp__plugin_discord_discord__*" 到 permissions.allow 数组中'
  else
    info "settings.json 已包含 Discord 权限"
  fi
else
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebFetch(*)",
      "WebSearch(*)",
      "mcp__plugin_discord_discord__*"
    ],
    "deny": [],
    "defaultMode": "bypassPermissions"
  },
  "enabledPlugins": {
    "discord@claude-plugins-official": true
  },
  "skipDangerousModePermissionPrompt": true
}
SETTINGS
  info "settings.json 已创建（含 Discord 权限）"
fi

# ── 3. 启动脚本 ──────────────────────────────────────────────

step "写入启动脚本"

cat > "$CLAUDE_DIR/start-bot.sh" << 'SCRIPT'
#!/bin/bash
# Start Claude Code in a tmux session for persistent Discord bot operation.
# Used by systemd service: claude-bot.service
#
# Supports two modes:
#   SESSION_NAME=work RESUME_SESSION_ID=xxx  → resume a specific conversation
#   (default)                                → start fresh as claude-bot

SESSION="${SESSION_NAME:-claude-bot}"
RESUME_ID="${RESUME_SESSION_ID:-}"

# If the session already exists and claude is running inside, do nothing.
if tmux has-session -t "$SESSION" 2>/dev/null; then
  if tmux list-panes -t "$SESSION" -F '#{pane_current_command}' | grep -q claude; then
    echo "$SESSION session already running"
    exit 0
  fi
  # Session exists but claude isn't running — kill and recreate.
  tmux kill-session -t "$SESSION"
fi

# Source nvm / fnm / mise — cover common node version managers.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$HOME/.fnm/fnm" ] && eval "$($HOME/.fnm/fnm env)"
command -v mise &>/dev/null && eval "$(mise activate bash)"

# Ensure bun is on PATH.
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# Build claude command
if [ -n "$RESUME_ID" ]; then
  CMD="claude --dangerously-skip-permissions --resume --session-id $RESUME_ID"
else
  CMD="claude --dangerously-skip-permissions"
fi

# Start tmux detached with claude running inside.
tmux new-session -d -s "$SESSION" -x 200 -y 50 "$CMD"
SCRIPT
chmod +x "$CLAUDE_DIR/start-bot.sh"
info "start-bot.sh"

# ── 4. systemd user service ─────────────────────────────────

step "配置 systemd user service"

cat > "$SYSTEMD_DIR/claude-bot.service" << EOF
[Unit]
Description=Claude Code Discord Bot (tmux)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=%h/.claude/start-bot.sh
ExecStop=/usr/bin/tmux kill-session -t claude-bot

[Install]
WantedBy=default.target
EOF
info "claude-bot.service"

# claude-work.service — resume a specific conversation on boot
# Edit SESSION_NAME / RESUME_SESSION_ID to match your session before enabling.
if [ ! -f "$SYSTEMD_DIR/claude-work.service" ]; then
  cat > "$SYSTEMD_DIR/claude-work.service" << 'EOF'
[Unit]
Description=Claude Code Work Session (tmux, resume conversation)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=SESSION_NAME=work
Environment=RESUME_SESSION_ID=replace-with-session-id
ExecStart=%h/.claude/start-bot.sh
ExecStop=/usr/bin/tmux kill-session -t work

[Install]
WantedBy=default.target
EOF
  info "claude-work.service (template — fill in RESUME_SESSION_ID before enabling)"
else
  info "claude-work.service already exists, skipped"
fi

# ── 5. Enable lingering + service ────────────────────────────

step "启用 lingering 和服务"

if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
  sudo loginctl enable-linger "$(whoami)"
fi
info "linger enabled"

systemctl --user daemon-reload
systemctl --user enable claude-bot.service 2>/dev/null
info "service enabled (claude-bot)"
# claude-work.service is NOT auto-enabled — enable it manually after configuring RESUME_SESSION_ID

# ── 6. Slash 命令 ────────────────────────────────────────────

step "写入 slash 命令"

cat > "$COMMANDS_DIR/bot-start.md" << 'CMD'
启动 Claude Code Discord Bot 后台服务。

执行以下步骤：
1. 运行 `systemctl --user start claude-bot` 启动服务
2. 等待 3 秒后运行 `systemctl --user status claude-bot` 确认状态
3. 运行 `tmux has-session -t claude-bot 2>/dev/null && echo "tmux session exists" || echo "tmux session not found"` 确认 tmux 会话
4. 向用户报告启动结果
CMD

cat > "$COMMANDS_DIR/bot-stop.md" << 'CMD'
停止 Claude Code Discord Bot 后台服务。

执行以下步骤：
1. 运行 `systemctl --user stop claude-bot` 停止服务
2. 运行 `systemctl --user status claude-bot` 确认已停止
3. 向用户报告结果
CMD

cat > "$COMMANDS_DIR/bot-restart.md" << 'CMD'
重启 Claude Code Discord Bot 后台服务。

执行以下步骤：
1. 运行 `systemctl --user stop claude-bot` 停止服务
2. 等待 2 秒
3. 运行 `systemctl --user start claude-bot` 启动服务
4. 等待 3 秒后运行 `systemctl --user status claude-bot` 确认状态
5. 向用户报告重启结果
CMD

cat > "$COMMANDS_DIR/bot-status.md" << 'CMD'
检查 Claude Code Discord Bot 的运行状态。

执行以下步骤：
1. 运行 `systemctl --user status claude-bot` 查看 systemd 服务状态
2. 运行 `tmux has-session -t claude-bot 2>/dev/null && echo "tmux session: alive" || echo "tmux session: not found"` 检查 tmux 会话
3. 运行 `ps aux | grep -E 'claude|bun.*discord' | grep -v grep` 查看相关进程
4. 运行 `ss -tnp 2>/dev/null | grep bun | head -5` 检查 Discord 网络连接
5. 汇总报告 bot 是否正常运行
CMD

cat > "$COMMANDS_DIR/bot-logs.md" << 'CMD'
查看 Claude Code Discord Bot 的最近日志。

执行以下步骤：
1. 运行 `journalctl --user -u claude-bot --no-pager -n 30` 查看 systemd 日志
2. 如果日志为空，提示用户可以通过 `tmux attach -t claude-bot` 直接查看 claude 输出
3. 向用户报告日志内容
CMD

info "bot-start / bot-stop / bot-restart / bot-status / bot-logs"

# ── 7. 操作手册 ──────────────────────────────────────────────

step "写入操作手册"

cat > "$CLAUDE_DIR/OPERATIONS.md" << 'DOC'
# Claude Code 服务器操作手册

## 核心原则

**永远不要在裸终端直接运行 `claude`。** 始终通过 tmux 运行，否则 SSH 断开 = 会话丢失 = Discord bot 掉线。

---

## 日常操作

### 启动新的 Claude Code 会话（交互使用）

```bash
# 1. 创建或接入 tmux 会话
tmux new -s work        # 创建名为 "work" 的新会话
tmux attach -t work     # 接入已有的 "work" 会话

# 2. 在 tmux 内启动 claude
claude

# 3. 用完后分离（不是退出！）
#    按 Ctrl+B，松开，再按 D
```

### tmux 速查

| 操作 | 命令 |
|------|------|
| 新建会话 | `tmux new -s <名字>` |
| 分离（保持后台） | `Ctrl+B` 然后 `D` |
| 列出所有会话 | `tmux ls` |
| 接入已有会话 | `tmux attach -t <名字>` |
| 关闭会话 | 在 tmux 内输入 `exit` |

---

## Discord Bot 管理

### Slash 命令（在 Claude Code 内）

| 命令 | 作用 |
|------|------|
| `/bot-start` | 启动 bot 后台服务 |
| `/bot-stop` | 停止 bot 后台服务 |
| `/bot-restart` | 重启 bot 后台服务 |
| `/bot-status` | 查看 bot 运行状态 |
| `/bot-logs` | 查看 bot 最近日志 |

### 终端命令

```bash
systemctl --user start claude-bot     # 启动
systemctl --user stop claude-bot      # 停止
systemctl --user restart claude-bot   # 重启
systemctl --user status claude-bot    # 状态
tmux attach -t claude-bot             # 接入查看（Ctrl+B,D 分离）
```

---

## 故障排查

| 症状 | 检查 | 处理 |
|------|------|------|
| bot 不回复 | `tmux ls` | `/bot-start` |
| "正在输入"后消失 | `tmux attach -t claude-bot` | `/bot-restart` |
| 服务启动失败 | `/bot-logs` | 根据日志修复 |
DOC
info "OPERATIONS.md"

# ── 完成 ─────────────────────────────────────────────────────

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""

# 检查 Discord token 是否已配置
if grep -q 'replace-with-your-discord-bot-token' "$DISCORD_DIR/.env" 2>/dev/null; then
  echo "  ⚠️  Discord bot token 未配置！请完成以下步骤："
  echo ""
  echo "  1. 创建 Discord Bot（如果还没有）："
  echo "     https://discord.com/developers/applications"
  echo "     → New Application → Bot → Reset Token → 复制 token"
  echo "     → Bot → 开启 Message Content Intent"
  echo "     → OAuth2 → URL Generator → bot scope → 选择权限 → 邀请到服务器"
  echo ""
  echo "  2. 填入 token："
  echo "     echo 'DISCORD_BOT_TOKEN=你的token' > ~/.claude/channels/discord/.env"
  echo "     chmod 600 ~/.claude/channels/discord/.env"
  echo ""
  echo "  3. 安装 Discord 插件（在 claude 会话内）："
  echo "     /plugin install discord@claude-plugins-official"
  echo "     /reload-plugins"
  echo ""
  echo "  4. 配置 bot token（在 claude 会话内）："
  echo "     /discord:configure 你的token"
  echo ""
  echo "  5. 启动 bot："
  echo "     systemctl --user start claude-bot"
  echo ""
else
  echo "  ✅ Discord token 已配置"
  echo ""
  echo "  启动 bot："
  echo "     systemctl --user start claude-bot"
  echo "     或在 claude 内: /bot-start"
  echo ""
fi
echo "  📖 操作手册: ~/.claude/OPERATIONS.md"
echo ""
