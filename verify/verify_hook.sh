#!/bin/bash
STAMP="$(date +%Y%m%dT%H%M%S)"
OUT_DIR="/tmp/ccsplit-verify"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/hook_$STAMP.txt"

PAYLOAD=$(\cat)

{
  echo "=== SessionStart Hook Verify $STAMP ==="
  echo "--- payload ---"
  echo "$PAYLOAD"
  echo "--- env.PPID=$PPID ---"
  echo "--- ps -p \$PPID ---"
  ps -p "$PPID" -o pid=,ppid=,lstart=,comm=,command= 2>&1 || echo "ps failed"
  echo "--- ps 親方向3段 ---"
  PID=$PPID
  for i in 1 2 3; do
    PARENT=$(ps -p "$PID" -o ppid= 2>/dev/null | tr -d ' ')
    [ -z "$PARENT" ] && break
    ps -p "$PARENT" -o pid=,ppid=,lstart=,comm=,command= 2>&1 || echo "stop"
    PID=$PARENT
  done
  echo "--- env.GHOSTTY_SURFACE_ID=$GHOSTTY_SURFACE_ID ---"
  echo "--- env.TERM_PROGRAM=$TERM_PROGRAM ---"
  echo "--- osascript Ghostty terminal dump (immediate) ---"
  osascript "$(dirname "$0")/verify_ghostty.applescript" 2>&1 || echo "osascript failed"
  echo "--- osascript Ghostty dump (after 100ms) ---"
  sleep 0.1
  osascript "$(dirname "$0")/verify_ghostty.applescript" 2>&1 || echo "osascript failed"
  echo "--- osascript Ghostty dump (after 500ms) ---"
  sleep 0.4
  osascript "$(dirname "$0")/verify_ghostty.applescript" 2>&1 || echo "osascript failed"
  echo "--- osascript Ghostty dump (after 1500ms) ---"
  sleep 1.0
  osascript "$(dirname "$0")/verify_ghostty.applescript" 2>&1 || echo "osascript failed"
} > "$OUT"

exit 0
