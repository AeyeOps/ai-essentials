#!/usr/bin/env bash
# whisper-ptt.sh - Push-to-talk speech-to-text using whisper.cpp
#
# Usage:
#   ./whisper-ptt.sh start   # Begin recording (bind to hotkey press)
#   ./whisper-ptt.sh stop    # Stop recording and transcribe (bind to hotkey release)
#
# TODO: Implement after building whisper.cpp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="${SCRIPT_DIR}/whisper.cpp"
MODEL="${WHISPER_DIR}/models/ggml-base.en.bin"
TEMP_AUDIO="/tmp/whisper-ptt-recording.wav"
PID_FILE="/tmp/whisper-ptt.pid"

# Detect display server
if [ "${XDG_SESSION_TYPE:-x11}" = "wayland" ]; then
    TYPE_CMD="wtype -"
else
    TYPE_CMD="xdotool type --clearmodifiers --"
fi

start_recording() {
    # Record audio using sox (rec)
    rec -q -r 16000 -c 1 -b 16 "$TEMP_AUDIO" &
    echo $! > "$PID_FILE"
    echo "Recording started..."
}

stop_recording() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi

    if [ -f "$TEMP_AUDIO" ]; then
        # Transcribe
        TEXT=$("${WHISPER_DIR}/main" -m "$MODEL" -f "$TEMP_AUDIO" -np -nt 2>/dev/null | tr -d '\n')

        # Type into focused window
        if [ -n "$TEXT" ]; then
            echo "$TEXT" | $TYPE_CMD
        fi

        rm -f "$TEMP_AUDIO"
    fi
}

case "${1:-}" in
    start)
        start_recording
        ;;
    stop)
        stop_recording
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
