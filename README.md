# claude-voice-zh 🎤

**本地中文语音输入，专为 Claude Code 打造。**

按一个键说中文，自动转写，自动粘贴到 Claude Code。完全离线，不联网，隐私安全。

<!-- TODO: 录屏演示 GIF -->
<!-- ![demo](./demo.gif) -->

## 为什么

Claude Code 的语音模式支持 20 种语言，但**不支持中文**。这个工具用 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 在本地跑语音识别，补上这块缺失。

## 特性

- **一个键操作** — F5 开始录音，F5 停止，自动粘贴
- **完全本地** — Whisper 模型跑在你的 Mac 上，不联网
- **一行安装** — 复制命令，等它跑完就能用
- **Apple Silicon 加速** — M 系列芯片 GPU 推理，转写 < 2 秒

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/nicning/claude-voice-zh/main/install.sh | bash
```

安装脚本会自动：
1. 安装 whisper-cpp、sox、skhd（通过 Homebrew）
2. 下载 Whisper small 模型（~500MB）
3. 配置 F5 全局快捷键
4. 引导你授权辅助功能权限

## 使用

在 Claude Code（或任何应用）中：

| 操作 | 效果 |
|------|------|
| 按 **F5** | 🔔 Tink 提示音，开始录音 |
| 说中文 | 正常说话 |
| 再按 **F5** | 🔔 Pop 提示音，停止录音 → 转写 → 自动粘贴 |

## 配置

通过环境变量自定义（加到 `~/.zshrc`）：

```bash
# 使用 medium 模型（更准确，需先下载）
export CLAUDE_VOICE_MODEL=~/.claude-voice-zh/models/ggml-medium.bin

# 改变识别语言（默认 zh）
export CLAUDE_VOICE_LANG=ja

# 自定义安装目录
export CLAUDE_VOICE_DIR=~/my-custom-path
```

### 升级到 medium 模型

small 模型对大多数场景够用。如果你觉得识别不够准，可以升级：

```bash
curl -L -o ~/.claude-voice-zh/models/ggml-medium.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
export CLAUDE_VOICE_MODEL=~/.claude-voice-zh/models/ggml-medium.bin
```

### 更换快捷键

编辑 `~/.config/skhd/skhdrc`，修改绑定：

```bash
# 默认 F5
fn - f5 : ~/.claude-voice-zh/claude-voice-zh.sh

# 改成 Ctrl+Shift+Space
ctrl + shift - space : ~/.claude-voice-zh/claude-voice-zh.sh
```

然后 `skhd --restart-service`。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/nicning/claude-voice-zh/main/uninstall.sh | bash
```

## 系统要求

- macOS 12+
- Apple Silicon 或 Intel Mac
- [Homebrew](https://brew.sh)
- 麦克风权限

## 工作原理

```
F5 → sox 录音 → whisper.cpp 本地转写 → pbcopy 复制 → osascript 模拟 Cmd+V 粘贴
```

全程不联网，音频和文字都只存在本地 `/tmp`，用完即删。

## 常见问题

**Q: 按 F5 没反应？**
检查 skhd 是否有辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 确保 skhd 已开启。

**Q: 识别不准？**
升级到 medium 模型（见配置章节），或者说话时离麦克风近一点。

**Q: 能识别英文/日文吗？**
可以，设置 `CLAUDE_VOICE_LANG=en` 或 `ja`。支持 [Whisper 所有语言](https://github.com/openai/whisper#available-models-and-languages)。

**Q: 不只是 Claude Code，其他地方也能用？**
对，任何接受键盘输入的应用都能用。它只是模拟 Cmd+V 粘贴。

## License

MIT

---

**觉得有用？给个 ⭐ 吧！**
