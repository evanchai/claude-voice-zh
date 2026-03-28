#!/bin/bash
# claude-voice-zh — Apple 原生中文语音输入，专为 Claude Code 设计
# https://github.com/nicning/claude-voice-zh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# --- 配置 ---
CLAUDE_VOICE_DIR="${CLAUDE_VOICE_DIR:-$HOME/.claude-voice-zh}"

# 加载 .env（skhd 不继承 shell 环境变量）
ENV_FILE="$CLAUDE_VOICE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

VOICE_LANG="${CLAUDE_VOICE_LANG:-zh}"
VOICE_REFINE="${CLAUDE_VOICE_REFINE:-on}"
VOICE_REFINE_MIN_CHARS="${CLAUDE_VOICE_REFINE_MIN_CHARS:-5}"

# --- 临时文件 ---
TMP_DIR="/tmp/claude-voice-zh"
mkdir -p "$TMP_DIR"
LOCK_FILE="$TMP_DIR/lock"
REC_PID_FILE="$TMP_DIR/rec.pid"
OVERLAY_PID_FILE="$TMP_DIR/overlay.pid"
OVERLAY_STATE_FILE="$TMP_DIR/overlay-state"
RESULT_FILE="$TMP_DIR/result.txt"
DEBOUNCE_FILE="$TMP_DIR/debounce"
LOG="$TMP_DIR/debug.log"

# --- 工具函数 ---
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }

beep_start() { afplay /System/Library/Sounds/Tink.aiff 2>/dev/null & }
beep_stop()  { afplay /System/Library/Sounds/Pop.aiff 2>/dev/null & }

OVERLAY="$CLAUDE_VOICE_DIR/overlay"
RECOGNIZER="$CLAUDE_VOICE_DIR/recognizer"

write_overlay_state() {
    local mode="$1"
    local text="${2:-}"
    local tmp="$OVERLAY_STATE_FILE.tmp"
    printf '%s\n%s\n' "$mode" "$text" > "$tmp"
    mv "$tmp" "$OVERLAY_STATE_FILE"
}

ensure_overlay() {
    [ -x "$OVERLAY" ] || return 0
    if [ -f "$OVERLAY_PID_FILE" ]; then
        local pid
        pid=$(cat "$OVERLAY_PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    "$OVERLAY" start >/dev/null 2>&1 &
}

hide_overlay() {
    rm -f "$OVERLAY_STATE_FILE"
    [ -x "$OVERLAY" ] && "$OVERLAY" hide >/dev/null 2>&1 &
}

stop_pid() {
    local file="$1"
    local pid=""
    [ -f "$file" ] || return 0
    pid=$(cat "$file" 2>/dev/null || true)
    rm -f "$file"
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
}

# --- 防抖 ---
if [ -f "$DEBOUNCE_FILE" ]; then
    last_mod=$(stat -f %m "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $((now - last_mod)) -lt 2 ]; then
        exit 0
    fi
fi
touch "$DEBOUNCE_FILE"

# --- LLM 后处理 ---
refine_with_llm() {
    local raw="$1"
    local char_count=${#raw}

    # 太短不处理
    if [ "$char_count" -lt "$VOICE_REFINE_MIN_CHARS" ]; then
        printf '%s' "$raw"
        return 0
    fi

    # 需要 API key
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        log "refine: skipped (no ANTHROPIC_API_KEY)"
        printf '%s' "$raw"
        return 0
    fi

    write_overlay_state refining "$raw"

    local prompt
    prompt=$(cat <<'PROMPT_END'
修正以下语音识别文本中的错误。规则：
1. 修正技术术语拼写（编程、AI、开发工具等常见术语）
2. 修正明显的同音字错误
3. 优化标点符号
4. 不改变原意，不添加内容，不删减内容
5. 只输出修正后的文本，不要任何解释或前缀
PROMPT_END
)

    local body
    body=$(jq -cn \
        --arg prompt "$prompt" \
        --arg text "$raw" \
        '{
            model: "claude-haiku-4-5-20251001",
            max_tokens: 1024,
            messages: [{role: "user", content: ($prompt + "\n\n" + $text)}]
        }')

    local response
    response=$(curl -s --max-time 2 \
        -H "content-type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$body" \
        "https://api.anthropic.com/v1/messages" 2>/dev/null) || {
        log "refine: curl failed"
        printf '%s' "$raw"
        return 0
    }

    local refined
    refined=$(printf '%s' "$response" | jq -r '.content[0].text // empty' 2>/dev/null)

    if [ -n "$refined" ]; then
        log "refine: [$raw] → [$refined]"
        printf '%s' "$refined"
    else
        log "refine: parse failed, using raw"
        printf '%s' "$raw"
    fi
}

# --- 依赖检查 ---
if [ ! -x "$RECOGNIZER" ]; then
    osascript -e 'display notification "recognizer 未编译，请运行 install.sh" with title "Claude Voice"' 2>/dev/null &
    exit 1
fi

# === 主逻辑 ===

if [ -f "$LOCK_FILE" ]; then
    # --- 停止 → 粘贴 ---
    rm -f "$LOCK_FILE"
    beep_stop
    log "stop"

    stop_pid "$REC_PID_FILE"

    if [ -f "$RESULT_FILE" ]; then
        RESULT=$(cat "$RESULT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        log "result: [$RESULT]"

        if [ -n "$RESULT" ]; then
            if [ "$VOICE_REFINE" = "on" ]; then
                RESULT=$(refine_with_llm "$RESULT")
            fi
            printf '%s' "$RESULT" | pbcopy
            hide_overlay
            sleep 0.05
            osascript -e 'tell application "System Events" to keystroke "v" using command down'
            log "pasted"
        else
            hide_overlay
            osascript -e 'display notification "未检测到语音" with title "Claude Voice"' 2>/dev/null &
        fi
    else
        hide_overlay
        osascript -e 'display notification "识别失败" with title "Claude Voice"' 2>/dev/null &
    fi

    rm -f "$RESULT_FILE"
else
    # --- 开始录音+识别 ---
    log "start"
    stop_pid "$REC_PID_FILE"
    rm -f "$RESULT_FILE"

    touch "$LOCK_FILE"
    beep_start
    write_overlay_state recording ""
    ensure_overlay

    "$RECOGNIZER" \
        --lang "$VOICE_LANG" \
        --state "$OVERLAY_STATE_FILE" \
        --result "$RESULT_FILE" \
        >>"$LOG" 2>&1 &
    echo $! > "$REC_PID_FILE"
    log "recognizer pid=$!"
fi
