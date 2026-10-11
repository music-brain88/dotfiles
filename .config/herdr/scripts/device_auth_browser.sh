#!/usr/bin/env bash
# device_auth_browser.sh — $BROWSER wrapper for the device-auth approval flow
#
# aws sso login --profile / gh auth login -w / gcloud auth login 等が開く承認 URL
# を、herdr の中では GUI ブラウザではなく terminal-browser の pane (呼び出し元の
# pane の右) に開く。WSL 機・SSH のセッション・herdr の外では、従来どおり GUI
# ブラウザを開く。terminal-browser が見つからないときと open が失敗したときも
# GUI ブラウザへフォールバックする。$BROWSER はスペース区切りの引数付き指定を
# 解釈しないツールがあるため、単一実行ファイルのラッパーにしてある
# (Issue #523, #701)。
#
# Opens device-auth approval URLs (aws sso login --profile, gh auth login -w,
# gcloud auth login, etc.) in a terminal-browser pane to the right of the calling
# pane when running inside herdr, instead of a GUI browser. On WSL, over SSH, and
# outside herdr it opens the GUI browser as before, and it also falls back to the
# GUI browser when terminal-browser is missing or `open` fails. Kept as a single
# executable (not "cmd --flag") because some tools that honor $BROWSER don't split
# on spaces (Issue #523, #701).
#
# 参照 / see: docs/reference/terminal-browser.md
set -euo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "usage: $(basename "$0") <url>" >&2
  exit 1
fi

# GUI ブラウザへフォールバックする / fall back to the desktop GUI browser
fallback_gui() {
  # desktop 判定不能な環境では xdg-open が generic モードで $BROWSER を参照し、
  # このスクリプト自身へ戻る無限ループになるため、必ず unset してから呼ぶ
  # In environments where xdg-open can't detect a desktop it falls back to
  # generic mode, which consults $BROWSER — i.e. this very script. Unset it
  # first so the fallback can never loop back here.
  unset BROWSER
  if command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$url"
  fi
  if command -v open >/dev/null 2>&1; then
    exec open "$url"
  fi
  echo "device_auth_browser: no GUI browser opener (xdg-open/open) found for $url" >&2
  exit 1
}

# WSL では Windows 側の既定ブラウザで開く / on WSL, open the Windows default browser
fallback_windows() {
  if command -v wslview >/dev/null 2>&1; then
    exec wslview "$url"
  fi
  if command -v rundll32.exe >/dev/null 2>&1; then
    exec rundll32.exe url.dll,FileProtocolHandler "$url"
  fi
  if command -v explorer.exe >/dev/null 2>&1; then
    exec explorer.exe "$url"
  fi
  # Windows interop が無効な場合の最終手段 / last resort when interop is off
  fallback_gui
}

# WSL 判定: WSL2 では ConPTY が kitty graphics の APC エスケープを剥ぐため、
# terminal-browser は設定に関わらず描画できない (Issue #569 で確定)。herdr 環境
# 判定より先に Windows 側ブラウザへ振り分ける (Issue #574)。
# WSL detection: on WSL2 the ConPTY layer strips the kitty graphics APC
# escapes, so terminal-browser can never render regardless of configuration
# (confirmed in Issue #569). Route to the Windows default browser before any
# herdr detection (Issue #574).
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
  fallback_windows
fi

# SSH セッション判定: SSH 由来のセッションは、HERDR_ENV=1 (herdr --remote 等で
# 明示的に立っている場合) でない限り、無条件に GUI へフォールバックさせる。
# SSH detection: an SSH-originated session always falls back to the GUI browser
# unless HERDR_ENV=1 is explicitly set (e.g. via herdr --remote).
is_ssh=0
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  is_ssh=1
fi

# herdr 環境判定: herdr が pane に渡す HERDR_PANE_ID が空でないこと。
# terminal-browser は HERDR_PANE_ID があるときだけ herdr のアダプタを使い、
# 無いと WezTerm などのアダプタで端末そのものを split する。判定をこの条件に
# そろえ、herdr の外の WezTerm 単体ではサーバーの稼働に関係なく GUI を開く
# (以前の herdr サーバーのソケットへの問い合わせは #701 で消した)。
# HERDR_PANE_ID が古い値で残っていた場合は、open が失敗して GUI に落ちる。
# Detect herdr: HERDR_PANE_ID, which herdr sets in every pane, must be non-empty.
# terminal-browser only uses its herdr adapter when HERDR_PANE_ID is set, and
# otherwise splits the terminal itself (WezTerm, etc.). Matching that condition
# keeps a plain WezTerm tab outside herdr on the GUI browser whether or not the
# herdr server is running (the old herdr socket probe was dropped in #701). A
# stale HERDR_PANE_ID makes `open` fail, which falls back to the GUI browser.
in_herdr=0
if [ -n "${HERDR_PANE_ID:-}" ]; then
  if [ "$is_ssh" -eq 0 ] || [ "${HERDR_ENV:-}" = "1" ]; then
    in_herdr=1
  fi
fi

if [ "$in_herdr" -ne 1 ]; then
  fallback_gui
fi

# terminal-browser は native 機だけに入る (nix/modules/terminal-browser.nix)
# terminal-browser is installed on the native machine only (nix/modules/terminal-browser.nix)
if ! command -v terminal-browser >/dev/null 2>&1; then
  fallback_gui
fi

# open は開いた後のブラウザの状態を JSON (約 40 行) で標準出力に書くので、
# 呼び出し元の pane に流れないよう捨てる。標準エラーは失敗の理由を見るために残す。
# 隣に terminal-browser の pane があれば、既定でそこにタブとして開く。
# `open` prints the browser state as ~40 lines of JSON on stdout; discard it so it
# doesn't spill into the calling pane. Keep stderr so failures stay visible. By
# default it opens a tab in an adjacent terminal-browser pane when there is one.
terminal-browser open "$url" --split right >/dev/null || fallback_gui
