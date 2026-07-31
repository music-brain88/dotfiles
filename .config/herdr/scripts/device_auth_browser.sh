#!/usr/bin/env bash
# device_auth_browser.sh — $BROWSER wrapper for the device-auth approval flow
#
# aws sso login --profile / gh auth login -w / gcloud auth login 等が開く承認 URL
# を、herdr 内では GUI ブラウザではなく herdr-browser (official.browser) プラグイン
# の pane に直行させる。herdr 外・SSH・プラグイン未導入時は従来の GUI ブラウザへ
# フォールバックする。$BROWSER はスペース区切りの引数付き指定を解釈しないツールが
# あるため、単一実行ファイルのラッパーにしてある(Issue #523)。
#
# Routes device-auth approval URLs (aws sso login --profile, gh auth login -w,
# gcloud auth login, etc.) into a herdr-browser (official.browser) plugin pane
# instead of a GUI browser when running inside herdr. Falls back to the normal
# GUI browser outside herdr, over SSH, or when the plugin isn't installed. Kept
# as a single executable (not "cmd --flag") because some tools that honor
# $BROWSER don't split on spaces (Issue #523).
#
# 参照 / see: docs/reference/herdr-browser.md
set -euo pipefail

PLUGIN_ID="official.browser"
ENTRYPOINT="browser"

url="${1:-}"
if [ -z "$url" ]; then
  echo "usage: $(basename "$0") <url>" >&2
  exit 1
fi

# GUI ブラウザへフォールバックする / fall back to the desktop GUI browser
fallback_gui() {
  if command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$url"
  fi
  if command -v open >/dev/null 2>&1; then
    exec open "$url"
  fi
  echo "device_auth_browser: no GUI browser opener (xdg-open/open) found for $url" >&2
  exit 1
}

# herdr 環境判定: HERDR_ENV=1 か、herdr サーバのソケットに到達可能か
# Detect herdr: either HERDR_ENV=1, or the herdr server socket answers.
in_herdr=0
if [ "${HERDR_ENV:-}" = "1" ]; then
  in_herdr=1
elif command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  server_status="$(herdr status server --json 2>/dev/null || true)"
  if [ "$(printf '%s' "$server_status" | jq -r '.status // empty' 2>/dev/null || true)" = "running" ]; then
    in_herdr=1
  fi
fi

if [ "$in_herdr" -ne 1 ]; then
  fallback_gui
fi

# herdr-browser プラグインの前提コマンド (herdr/jq/bun) が揃っているか確認
# Confirm the herdr-browser plugin's prerequisite commands are available.
if ! command -v herdr >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v bun >/dev/null 2>&1; then
  fallback_gui
fi

# プラグイン導入済み判定 + plugin_root 解決 (ハードコード禁止、#523 実装案どおり)
# Confirm the plugin is installed and resolve plugin_root — never hardcode it.
plugin_list_json="$(herdr plugin list --plugin "$PLUGIN_ID" --json 2>/dev/null || true)"
plugin_root="$(printf '%s' "$plugin_list_json" |
  jq -r --arg id "$PLUGIN_ID" '.result.plugins[]? | select(.id == $id) | .plugin_root // empty' 2>/dev/null || true)"

if [ -z "$plugin_root" ] || [ ! -f "$plugin_root/src/cli.ts" ]; then
  fallback_gui
fi

cli="$plugin_root/src/cli.ts"

# 既存 view (可視 pane に紐づくもの) の有無で分岐する
# Branch on whether a view (backed by a visible pane) already exists.
views_json="$(bun run "$cli" views 2>/dev/null || true)"
has_view="$(printf '%s' "$views_json" | jq -r '(.views // []) | length > 0' 2>/dev/null || echo false)"

if [ "$has_view" = "true" ]; then
  # 既存 view を ensureView() が自動選択して navigate する (open に --view は無い)
  # ensureView() auto-selects the existing view and navigates it (open has no --view flag)
  bun run "$cli" open "$url" >/dev/null 2>&1 || fallback_gui
else
  # view が無ければ pane を新規に開きつつ初期 URL を渡す (README 記載の --env)
  # No view yet: open a fresh pane with the initial URL in one step (documented --env)
  herdr plugin pane open \
    --plugin "$PLUGIN_ID" \
    --entrypoint "$ENTRYPOINT" \
    --placement overlay \
    --focus \
    --env "HERDR_BROWSER_INITIAL_URL=$url" \
    >/dev/null 2>&1 || fallback_gui
fi
