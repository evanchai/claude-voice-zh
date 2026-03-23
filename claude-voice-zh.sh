#!/bin/bash
# claude-voice-zh — 本地 Whisper 中文语音输入，专为 Claude Code 设计
# https://github.com/nicning/claude-voice-zh
#
# 按一次快捷键开始录音，再按一次停止 → 本地转写 → 自动粘贴
# 完全离线，不联网，隐私安全

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# --- 配置 ---
CLAUDE_VOICE_DIR="${CLAUDE_VOICE_DIR:-$HOME/.claude-voice-zh}"
MODEL="${CLAUDE_VOICE_MODEL:-$CLAUDE_VOICE_DIR/models/ggml-small.bin}"
WHISPER_LANG="${CLAUDE_VOICE_LANG:-zh}"

# --- 临时文件 ---
TMP_DIR="/tmp/claude-voice-zh"
mkdir -p "$TMP_DIR"
TMP_WAV="$TMP_DIR/recording.wav"
TMP_TXT="$TMP_DIR/result"
LOCK_FILE="$TMP_DIR/lock"
PID_FILE="$TMP_DIR/rec.pid"
DEBOUNCE_FILE="$TMP_DIR/debounce"
LOG="$TMP_DIR/debug.log"

# --- 工具函数 ---
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }

notify() {
    osascript -e "display notification \"$1\" with title \"Claude Voice\"" 2>/dev/null &
}

beep_start() { afplay /System/Library/Sounds/Tink.aiff 2>/dev/null & }
beep_stop()  { afplay /System/Library/Sounds/Pop.aiff 2>/dev/null & }

OVERLAY="$CLAUDE_VOICE_DIR/overlay"
show_overlay() {
    [ -x "$OVERLAY" ] && "$OVERLAY" "$1" &
}
hide_overlay() {
    [ -x "$OVERLAY" ] && "$OVERLAY" hide &
}

# --- 防抖（skhd 按键会重复触发）---
if [ -f "$DEBOUNCE_FILE" ]; then
    last_mod=$(stat -f %m "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $((now - last_mod)) -lt 2 ]; then
        exit 0
    fi
fi
touch "$DEBOUNCE_FILE"

# --- 依赖检查 ---
for cmd in whisper-cli rec sox pbcopy osascript; do
    if ! command -v "$cmd" &>/dev/null; then
        notify "缺少依赖: $cmd，请重新运行 install.sh"
        log "missing dep: $cmd"
        exit 1
    fi
done

if [ ! -f "$MODEL" ]; then
    notify "模型文件不存在，请重新运行 install.sh"
    log "model not found: $MODEL"
    exit 1
fi

# === 主逻辑 ===

if [ -f "$LOCK_FILE" ]; then
    # --- 第二次按：停止录音 → 转写 → 粘贴 ---
    rm -f "$LOCK_FILE"
    beep_stop
    show_overlay transcribing
    log "stop recording"

    if [ -f "$PID_FILE" ]; then
        REC_PID=$(cat "$PID_FILE")
        kill "$REC_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            kill -0 "$REC_PID" 2>/dev/null || break
            sleep 0.1
        done
        rm -f "$PID_FILE"
    fi

    log "wav: $([ -f "$TMP_WAV" ] && echo "$(wc -c < "$TMP_WAV") bytes" || echo "missing")"

    if [ ! -f "$TMP_WAV" ] || [ "$(wc -c < "$TMP_WAV")" -lt 1000 ]; then
        log "wav too small or missing"
        hide_overlay
        notify "录音太短，请重试"
        rm -f "$TMP_WAV"
        exit 1
    fi

    notify "转写中..."

    # 转换为 whisper 需要的 16kHz mono 16bit
    sox "$TMP_WAV" -r 16000 -c 1 -b 16 "$TMP_DIR/16k.wav" 2>>"$LOG"
    mv "$TMP_DIR/16k.wav" "$TMP_WAV"

    log "whisper start"
    whisper-cli \
        -m "$MODEL" \
        -l "$WHISPER_LANG" \
        -nt \
        -of "$TMP_TXT" \
        -otxt \
        "$TMP_WAV" 2>>"$LOG"
    log "whisper done, exit=$?"

    if [ -f "${TMP_TXT}.txt" ]; then
        RESULT=$(cat "${TMP_TXT}.txt" | sed '/^$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')
        log "result: [$RESULT]"

        # 过滤 whisper 幻觉输出（空括号、纯标点等）
        CLEAN=$(echo "$RESULT" | sed 's/[()（）\[\]]*//g' | sed 's/^[[:space:]]*$//')
        if [ -n "$CLEAN" ]; then
            printf '%s' "$RESULT" | pbcopy
            hide_overlay
            sleep 0.3
            osascript -e 'tell application "System Events" to keystroke "v" using command down'
            log "pasted"
        else
            log "empty after cleanup"
            hide_overlay
            notify "未检测到语音"
        fi
    else
        log "no output file"
        hide_overlay
        notify "转写失败"
    fi

    rm -f "$TMP_WAV" "${TMP_TXT}.txt"
else
    # --- 第一次按：开始录音 ---
    log "start recording"
    [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$TMP_WAV"

    touch "$LOCK_FILE"
    beep_start
    show_overlay recording

    rec -q "$TMP_WAV" &
    echo $! > "$PID_FILE"
    log "rec pid=$!"
fi
