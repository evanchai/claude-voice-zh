# claude-voice-zh 🎤

**本地中文语音输入，专为 Claude Code 打造。**

按一个键说中文，实时出字，AI 自动润色，粘贴到 Claude Code。语音识别完全在设备上运行，可选 LLM 后处理修正技术术语。

<!-- TODO: 录屏演示 GIF -->
<!-- ![demo](./demo.gif) -->

## 为什么

Claude Code 的语音模式支持 20 种语言，但**不支持中文**。这个工具用 macOS 原生语音识别（SFSpeechRecognizer）在本地跑，补上这块缺失。

## 特性

- **一个键操作** — F5 开始录音，F5 停止，自动粘贴
- **实时出字** — 边说边在顶部胶囊里显示识别结果
- **AI 润色** — 停止后自动用 Haiku 修正技术术语、标点和同音字（~1s）
- **中英混杂** — 说中文夹英文单词，自动识别，润色时保留不翻译
- **完全本地识别** — Apple on-device 语音识别，不联网
- **零配置** — 如果你已登录 Claude Code，LLM 润色开箱即用
- **一行安装** — 复制命令，等它跑完就能用

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/evanchai/claude-voice-zh/main/install.sh | bash
```

安装脚本会自动：
1. 安装 skhd（全局快捷键，通过 Homebrew）
2. 编译语音识别引擎和状态指示器（Swift）
3. 配置 F5 全局快捷键
4. 引导你授权辅助功能权限

首次使用时，系统会弹窗请求**麦克风**和**语音识别**权限，授权一次后不再弹窗。

## 使用

在 Claude Code（或任何应用）中：

| 操作 | 效果 |
|------|------|
| 按 **F5** | 🔔 Tink 提示音，开始录音，顶部出现实时预览胶囊 |
| 说中文 | 边说边出字，支持中英混杂 |
| 再按 **F5** | 🔔 Pop 提示音，停止 → AI 润色 → 粘贴 |

## 配置

通过环境变量自定义（加到 `~/.zshrc`）：

```bash
# 改变识别语言（默认 zh，即简体中文）
export CLAUDE_VOICE_LANG=en    # 英文
export CLAUDE_VOICE_LANG=ja    # 日文

# 关闭 LLM 润色（默认开启）
export CLAUDE_VOICE_REFINE=off

# 自定义安装目录
export CLAUDE_VOICE_DIR=~/my-custom-path
```

### AI 润色

停止录音后，工具会自动调用 Claude Haiku 修正识别结果：

- 修正技术术语拼写（deploy、Vercel、TypeScript 等）
- 优化标点和断句
- 保留中英混杂，不会把英文翻译成中文

**API Key 来源**（按优先级）：
1. `ANTHROPIC_API_KEY` 环境变量（或写在 `~/.claude-voice-zh/.env` 中）
2. Claude Code OAuth token（自动从 macOS Keychain 读取）

如果你已登录 Claude Code，无需额外配置。设置 `CLAUDE_VOICE_REFINE=off` 可关闭。

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
curl -fsSL https://raw.githubusercontent.com/evanchai/claude-voice-zh/main/uninstall.sh | bash
```

## 系统要求

- macOS 13+（需要 on-device 语音识别）
- Apple Silicon 或 Intel Mac
- [Homebrew](https://brew.sh)
- 麦克风权限 + 语音识别权限

## 工作原理

```
F5 → SFSpeechRecognizer 实时识别 → 顶部胶囊显示 → F5 → Haiku 润色 → pbcopy → Cmd+V 粘贴
```

语音识别使用 macOS 原生 SFSpeechRecognizer，音频在设备上处理。停止后可选经过 Claude Haiku 后处理，修正技术术语和标点（~1s），然后粘贴到当前应用。

## 常见问题

**Q: 按 F5 没反应？**
检查 skhd 是否有辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能 → 确保 skhd 已开启。

**Q: 弹窗要求麦克风/语音识别权限？**
首次使用需要授权，点允许即可。如果不小心拒绝了：系统设置 → 隐私与安全性 → 对应权限 → 找到终端应用开启。

**Q: 识别不准？**
确保 macOS 已下载中文 on-device 语音模型：系统设置 → 键盘 → 听写 → 语言中添加中文。

**Q: 能识别英文/日文吗？**
可以，设置 `CLAUDE_VOICE_LANG=en` 或 `ja`。

**Q: 不只是 Claude Code，其他地方也能用？**
对，任何接受键盘输入的应用都能用。它只是模拟 Cmd+V 粘贴。

**Q: 润色后结果不对？**
可以设置 `CLAUDE_VOICE_REFINE=off` 关闭 LLM 润色，直接使用原始识别结果。

**Q: 和之前的 Whisper 版本有什么区别？**
v2 换用了 macOS 原生语音识别，解决了 Whisper 版本的三个问题：繁体输出、实时预览不准、停止后等待长。不再需要下载 500MB 模型。v3 加入了 Haiku LLM 后处理，大幅提升技术术语的准确率。

## License

MIT

---

**觉得有用？给个 ⭐ 吧！**
