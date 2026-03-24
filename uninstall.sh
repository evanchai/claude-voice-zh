#!/bin/bash
# claude-voice-zh 卸载脚本

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$HOME/.claude-voice-zh"
BIN_LINK="$HOME/.local/bin/claude-voice-zh"
SKHD_CONFIG="$HOME/.config/skhd/skhdrc"

echo ""
echo -e "${YELLOW}卸载 claude-voice-zh...${NC}"
echo ""

# 移除 skhd 配置
if [ -f "$SKHD_CONFIG" ]; then
    grep -v "claude-voice-zh" "$SKHD_CONFIG" > "$SKHD_CONFIG.tmp" 2>/dev/null || true
    mv "$SKHD_CONFIG.tmp" "$SKHD_CONFIG"
    skhd --restart-service 2>/dev/null || true
    echo -e "  快捷键配置 ${GREEN}✓${NC}"
fi

# 移除 symlink
rm -f "$BIN_LINK"
echo -e "  命令链接 ${GREEN}✓${NC}"

# 移除安装目录（含模型）
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo -e "  安装目录 ${GREEN}✓${NC}"
fi

# 清理临时文件
rm -rf /tmp/claude-voice-zh
echo -e "  临时文件 ${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}✅ 卸载完成${NC}"
echo ""
echo -e "  注意：skhd 未卸载（可能被其他工具使用）"
echo -e "  如需卸载：brew uninstall skhd"
echo ""
