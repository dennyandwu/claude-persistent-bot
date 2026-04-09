#!/bin/bash
# Claude Code Persistent Bot Setup
# 在新服务器上一键配置 Claude Code + Discord Bot 持久化运行环境
# 用法: curl -sL <url> | bash  或  bash setup-persistent-bot.sh
#
# 幂等设计 — 重复运行安全，只更新有变化的部分。

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SYSTEMD_DIR="$HOME/.config/systemd/user"

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

# ── 1. 目录结构 ──────────────────────────────────────────────

step "创建目录结构"

mkdir -p "$CLAUDE_DIR" "$COMMANDS_DIR" "$SYSTEMD_DIR"
info "$CLAUDE_DIR"
info "$COMMANDS_DIR"
info "$SYSTEMD_DIR"

# ── 2. 启动脚本 ──────────────────────────────────────────────

step "写入启动脚本"

cat > "$CLAUDE_DIR/start-bot.sh" << 'SCRIPT'
#!/bin/bash
SESSION="claude-bot"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if tmux list-panes -t "$SESSION" -F '#{pane_current_command}' | grep -q claude; then
    echo "claude-bot session already running"
    exit 0
  fi
  tmux kill-session -t "$SESSION"
fi

# Source nvm / fnm / mise — cover common node version managers.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$HOME/.fnm/fnm" ] && eval "$($HOME/.fnm/fnm env)"
command -v mise &>/dev/null && eval "$(mise activate bash)"

tmux new-session -d -s "$SESSION" -x 200 -y 50 "claude --dangerously-skip-permissions"
SCRIPT
chmod +x "$CLAUDE_DIR/start-bot.sh"
info "start-bot.sh"

# ── 3. systemd user service ─────────────────────────────────

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

# ── 4. Enable lingering + service ────────────────────────────

step "启用 lingering 和服务"

if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
  sudo loginctl enable-linger "$(whoami)"
fi
info "linger enabled"

systemctl --user daemon-reload
systemctl --user enable claude-bot.service 2>/dev/null
info "service enabled"

# ── 5. Slash 命令 ────────────────────────────────────────────

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

# ── 6. 操作手册 ──────────────────────────────────────────────

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
echo "  后续步骤："
echo "  1. 配置 Discord bot token:"
echo "     mkdir -p ~/.claude/channels/discord"
echo "     echo 'DISCORD_BOT_TOKEN=你的token' > ~/.claude/channels/discord/.env"
echo "     chmod 600 ~/.claude/channels/discord/.env"
echo ""
echo "  2. 安装 Discord 插件（在 claude 内）:"
echo "     /install-plugin discord@claude-plugins-official"
echo ""
echo "  3. 启动 bot:"
echo "     systemctl --user start claude-bot"
echo "     或在 claude 内: /bot-start"
echo ""
echo "  4. 日常使用 claude 请通过 tmux:"
echo "     tmux new -s work && claude"
echo ""
