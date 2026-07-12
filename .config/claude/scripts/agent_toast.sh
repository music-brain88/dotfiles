#!/usr/bin/env bash
# agent_toast.sh - Claude Code hook からエージェント状態の OS トースト通知を出す
# Fires an OS toast notification from Claude Code hooks (Notification / Stop).
#
# Usage: agent_toast.sh <notification|stop>
# stdin: hook が渡す JSON (message フィールド等を含む、任意)
#
# 設計方針: hook はエージェント本体を絶対にブロックしない。
# 各行 fail-silent (`|| true`) を徹底しつつ set -euo pipefail と両立させる。
# Design: this hook must never block the agent. Every external/fallible call
# ends in `|| true` so the composite exit status stays 0 even under `set -e`.
set -euo pipefail

event="${1:-}"

# stdin の hook JSON を読む(パイプが無ければ待たずにスキップ)
# Read hook JSON from stdin, skipping without blocking when nothing is piped.
hook_json=""
if [ ! -t 0 ]; then
  hook_json="$(cat || true)"
fi

message=""
if command -v jq >/dev/null 2>&1 && [ -n "$hook_json" ]; then
  message="$(printf '%s' "$hook_json" | jq -r '.message // empty' 2>/dev/null || true)"
fi

cwd_base="$(basename "$PWD" 2>/dev/null || true)"
pane_id="${HERDR_PANE_ID:-}"

case "$event" in
  notification)
    title="Claude: 承認待ち"
    sound="request"
    ;;
  stop)
    title="Claude: 完了"
    sound="done"
    ;;
  *)
    title="Claude"
    sound="done"
    ;;
esac

body="$cwd_base"
if [ -n "$pane_id" ]; then
  body="$body (pane: $pane_id)"
fi
if [ -n "$message" ]; then
  body="$body — $message"
fi

# Wayland 環境: notify-send 経由で通知デーモン(mako 等)に出す
# Wayland: notify-send to the running notification daemon (mako).
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$body" || true
  fi
fi

# WSL2 環境: OSC 9 エスケープを /dev/tty へ(未検証経路)
# WSL2: OSC 9 escape sequence to /dev/tty (UNVERIFIED path — no WSL test rig
# available at implementation time). Silently give up if /dev/tty can't be opened.
is_wsl=0
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  is_wsl=1
elif grep -qi microsoft /proc/version 2>/dev/null; then
  is_wsl=1
fi
if [ "$is_wsl" -eq 1 ]; then
  { printf '\033]9;%s\007' "$title: $body" > /dev/tty; } 2>/dev/null || true
fi

# herdr 内なら画面内通知も併発(コアの通知経路とは独立、失敗しても無視)
# Inside herdr, also fire its in-app notification — best-effort, never fatal.
if [ "${HERDR_ENV:-}" = "1" ]; then
  if command -v herdr >/dev/null 2>&1; then
    herdr notification show "$title" --sound "$sound" >/dev/null 2>&1 || true
  fi
fi

exit 0
