#!/bin/bash
# claude-voice-zh 一键安装脚本
# curl -fsSL https://raw.githubusercontent.com/nicning/claude-voice-zh/main/install.sh | bash

set -euo pipefail

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="$HOME/.claude-voice-zh"
BIN_DIR="$HOME/.local/bin"
MODEL_DIR="$INSTALL_DIR/models"
SKHD_CONFIG_DIR="$HOME/.config/skhd"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
REPO_URL="https://raw.githubusercontent.com/nicning/claude-voice-zh/main"

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║     claude-voice-zh 安装程序          ║${NC}"
echo -e "${CYAN}${BOLD}║     本地中文语音输入 for Claude Code  ║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════╝${NC}"
echo ""

# --- 系统检查 ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}仅支持 macOS${NC}"
    exit 1
fi

if ! command -v brew &>/dev/null; then
    echo -e "${RED}需要 Homebrew。安装: https://brew.sh${NC}"
    exit 1
fi

# --- 安装依赖 ---
echo -e "${YELLOW}[1/5]${NC} 安装依赖..."

install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        echo "  安装 $2..."
        brew install "$2" 2>/dev/null
    else
        echo -e "  $2 ${GREEN}✓${NC}"
    fi
}

install_if_missing whisper-cli whisper-cpp
install_if_missing sox sox
install_if_missing skhd koekeishiya/formulae/skhd

# --- 下载模型 ---
echo -e "${YELLOW}[2/6]${NC} 下载 Whisper 模型 (small, ~500MB)..."
mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/ggml-small.bin" ]; then
    echo -e "  模型已存在 ${GREEN}✓${NC}"
else
    echo "  下载中，请稍候..."
    curl -L --progress-bar -o "$MODEL_DIR/ggml-small.bin" "$MODEL_URL"
    echo -e "  ${GREEN}✓${NC} 下载完成"
fi

# --- 编译状态指示器 ---
echo -e "${YELLOW}[3/6]${NC} 编译状态指示器..."
OVERLAY_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/overlay.swift"
if [ -f "$OVERLAY_SOURCE" ]; then
    swiftc "$OVERLAY_SOURCE" -o "$INSTALL_DIR/overlay" -framework AppKit 2>/dev/null
else
    curl -fsSL -o "$INSTALL_DIR/overlay.swift" "$REPO_URL/overlay.swift"
    swiftc "$INSTALL_DIR/overlay.swift" -o "$INSTALL_DIR/overlay" -framework AppKit 2>/dev/null
    rm -f "$INSTALL_DIR/overlay.swift"
fi
if [ -f "$INSTALL_DIR/overlay" ]; then
    echo -e "  ${GREEN}✓${NC}"
else
    echo -e "  ${YELLOW}跳过（编译失败，不影响核心功能）${NC}"
fi

# --- 安装主脚本 ---
echo -e "${YELLOW}[4/6]${NC} 安装脚本..."
mkdir -p "$BIN_DIR"

# 如果是从 curl | bash 运行，从 GitHub 下载脚本；否则用本地文件
SCRIPT_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/claude-voice-zh.sh"
if [ -f "$SCRIPT_SOURCE" ]; then
    cp "$SCRIPT_SOURCE" "$INSTALL_DIR/claude-voice-zh.sh"
else
    curl -fsSL -o "$INSTALL_DIR/claude-voice-zh.sh" "$REPO_URL/claude-voice-zh.sh"
fi
chmod +x "$INSTALL_DIR/claude-voice-zh.sh"

# 创建 symlink 到 PATH
ln -sf "$INSTALL_DIR/claude-voice-zh.sh" "$BIN_DIR/claude-voice-zh"
echo -e "  ${GREEN}✓${NC}"

# --- 配置快捷键 ---
echo -e "${YELLOW}[5/6]${NC} 配置快捷键 (F5)..."
mkdir -p "$SKHD_CONFIG_DIR"

SKHD_ENTRY="fn - f5 : $INSTALL_DIR/claude-voice-zh.sh"

if [ -f "$SKHD_CONFIG_DIR/skhdrc" ]; then
    # 移除旧的 claude-voice-zh 配置
    grep -v "claude-voice-zh" "$SKHD_CONFIG_DIR/skhdrc" > "$SKHD_CONFIG_DIR/skhdrc.tmp" 2>/dev/null || true
    mv "$SKHD_CONFIG_DIR/skhdrc.tmp" "$SKHD_CONFIG_DIR/skhdrc"
fi

echo "# claude-voice-zh: F5 触发语音输入" >> "$SKHD_CONFIG_DIR/skhdrc"
echo "$SKHD_ENTRY" >> "$SKHD_CONFIG_DIR/skhdrc"
echo -e "  ${GREEN}✓${NC}"

# --- 启动 skhd ---
echo -e "${YELLOW}[6/6]${NC} 启动快捷键服务..."

skhd --stop-service 2>/dev/null || true
sleep 1
skhd --start-service 2>/dev/null || true
sleep 1

# 检查 skhd 是否需要辅助功能权限
if grep -q "accessibility" /tmp/skhd_*.err.log 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}⚠️  需要授权辅助功能权限：${NC}"
    echo ""
    echo "  1. 系统设置将自动打开"
    echo "  2. 在「辅助功能」列表中找到 skhd"
    echo "  3. 打开开关"
    echo "  4. 如果没找到，点 + 号添加 /opt/homebrew/bin/skhd"
    echo ""
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo -e "  授权后按回车继续..."
    read -r
    skhd --restart-service 2>/dev/null || true
    sleep 1
fi

# --- 检查 PATH ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}提示：${NC}请将以下内容添加到你的 shell 配置文件 (~/.zshrc)："
    echo ""
    echo -e "  ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
fi

# --- 完成 ---
echo ""
echo -e "${GREEN}${BOLD}✅ 安装完成！${NC}"
echo ""
echo -e "  ${BOLD}使用方法：${NC}"
echo -e "  按 ${CYAN}F5${NC} 开始录音"
echo -e "  说中文"
echo -e "  再按 ${CYAN}F5${NC} 停止 → 自动转写 → 自动粘贴"
echo ""
echo -e "  ${BOLD}提示音：${NC}"
echo -e "  🔔 Tink = 开始录音"
echo -e "  🔔 Pop  = 停止录音"
echo ""
echo -e "  ${BOLD}升级模型（更准确）：${NC}"
echo -e "  curl -L -o ~/.claude-voice-zh/models/ggml-medium.bin \\"
echo -e "    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
echo -e "  export CLAUDE_VOICE_MODEL=~/.claude-voice-zh/models/ggml-medium.bin"
echo ""
echo -e "  ${BOLD}卸载：${NC}"
echo -e "  curl -fsSL $REPO_URL/uninstall.sh | bash"
echo ""
