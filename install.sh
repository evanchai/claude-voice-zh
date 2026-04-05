#!/bin/bash
# claude-voice-zh 一键安装脚本
# curl -fsSL https://raw.githubusercontent.com/evanchai/claude-voice-zh/main/install.sh | bash

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
SKHD_CONFIG_DIR="$HOME/.config/skhd"
REPO_URL="https://raw.githubusercontent.com/evanchai/claude-voice-zh/main"

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
echo -e "${YELLOW}[1/4]${NC} 安装依赖..."

if ! command -v skhd &>/dev/null; then
    echo "  安装 skhd..."
    brew install koekeishiya/formulae/skhd 2>/dev/null
else
    echo -e "  skhd ${GREEN}✓${NC}"
fi

# --- 编译 Swift 组件 ---
echo -e "${YELLOW}[2/4]${NC} 编译语音识别引擎..."
mkdir -p "$INSTALL_DIR"

compile_swift() {
    local name="$1"
    local src="$2"
    local frameworks="$3"

    if [ -f "$src" ]; then
        local source="$src"
    else
        local source="$INSTALL_DIR/${name}.swift"
        curl -fsSL -o "$source" "$REPO_URL/${name}.swift"
    fi

    if swiftc "$source" -o "$INSTALL_DIR/$name" $frameworks 2>/dev/null; then
        echo -e "  $name ${GREEN}✓${NC}"
        [ "$source" = "$INSTALL_DIR/${name}.swift" ] && rm -f "$source"
        return 0
    else
        echo -e "  $name ${RED}编译失败${NC}"
        [ "$source" = "$INSTALL_DIR/${name}.swift" ] && rm -f "$source"
        return 1
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# recognizer — 核心：语音识别引擎（必须成功）
if ! compile_swift "recognizer" "$SCRIPT_DIR/recognizer.swift" "-framework AVFoundation -framework Speech"; then
    echo -e "${RED}recognizer 编译失败，无法继续安装${NC}"
    exit 1
fi

# overlay — 可选：状态指示器 UI
compile_swift "overlay" "$SCRIPT_DIR/overlay.swift" "-framework AppKit" || \
    echo -e "  ${YELLOW}overlay 跳过（不影响核心功能）${NC}"

# --- 安装主脚本 ---
echo -e "${YELLOW}[3/4]${NC} 安装脚本..."
mkdir -p "$BIN_DIR"

SCRIPT_SOURCE="$SCRIPT_DIR/claude-voice-zh.sh"
if [ -f "$SCRIPT_SOURCE" ]; then
    cp "$SCRIPT_SOURCE" "$INSTALL_DIR/claude-voice-zh.sh"
else
    curl -fsSL -o "$INSTALL_DIR/claude-voice-zh.sh" "$REPO_URL/claude-voice-zh.sh"
fi
chmod +x "$INSTALL_DIR/claude-voice-zh.sh"

ln -sf "$INSTALL_DIR/claude-voice-zh.sh" "$BIN_DIR/claude-voice-zh"
echo -e "  ${GREEN}✓${NC}"

# --- 配置快捷键 ---
echo -e "${YELLOW}[4/4]${NC} 配置快捷键 (F5)..."
mkdir -p "$SKHD_CONFIG_DIR"

SKHD_ENTRY="fn - f5 : $INSTALL_DIR/claude-voice-zh.sh"

if [ -f "$SKHD_CONFIG_DIR/skhdrc" ]; then
    grep -v "claude-voice-zh" "$SKHD_CONFIG_DIR/skhdrc" > "$SKHD_CONFIG_DIR/skhdrc.tmp" 2>/dev/null || true
    mv "$SKHD_CONFIG_DIR/skhdrc.tmp" "$SKHD_CONFIG_DIR/skhdrc"
fi

echo "# claude-voice-zh: F5 触发语音输入" >> "$SKHD_CONFIG_DIR/skhdrc"
echo "$SKHD_ENTRY" >> "$SKHD_CONFIG_DIR/skhdrc"

skhd --stop-service 2>/dev/null || true
sleep 1
skhd --start-service 2>/dev/null || true
sleep 1

# 检查辅助功能权限
if grep -q "accessibility" /tmp/skhd_*.err.log 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}⚠️  需要授权辅助功能权限：${NC}"
    echo ""
    echo "  1. 系统设置将自动打开"
    echo "  2. 在「辅助功能」列表中找到 skhd"
    echo "  3. 打开开关"
    echo ""
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo -e "  授权后按回车继续..."
    read -r
    skhd --restart-service 2>/dev/null || true
    sleep 1
fi

echo -e "  ${GREEN}✓${NC}"

# --- 检查 PATH ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}提示：${NC}请将以下内容添加到 ~/.zshrc："
    echo ""
    echo -e "  ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
fi

# --- 首次权限 ---
echo ""
echo -e "${YELLOW}首次使用需要授权两个权限：${NC}"
echo "  1. 麦克风权限 — 按 F5 时系统会弹窗询问"
echo "  2. 语音识别权限 — 同上"
echo "  授权一次后，后续使用不会再弹窗"

# --- 完成 ---
echo ""
echo -e "${GREEN}${BOLD}✅ 安装完成！${NC}"
echo ""
echo -e "  ${BOLD}使用方法：${NC}"
echo -e "  按 ${CYAN}F5${NC} 开始录音（边说边出字）"
echo -e "  再按 ${CYAN}F5${NC} 停止 → 自动粘贴"
echo ""
echo -e "  ${BOLD}提示音：${NC}"
echo -e "  🔔 Tink = 开始录音"
echo -e "  🔔 Pop  = 停止录音"
echo ""
echo -e "  ${BOLD}改语言：${NC}"
echo -e "  export CLAUDE_VOICE_LANG=en   # 英文"
echo -e "  export CLAUDE_VOICE_LANG=ja   # 日文"
echo ""
echo -e "  ${BOLD}卸载：${NC}"
echo -e "  curl -fsSL $REPO_URL/uninstall.sh | bash"
echo ""
