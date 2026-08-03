#!/bin/bash

# Waybar 計器モジュール custom/holiday (#562)
# 左島(現実世界の窓)に次の祝日カウントダウンを表示する。holidays-jp API の年次データを
# 日次キャッシュし、今日以降で最初の祝日を1件選んで return-type: json を1行出力する。
# Waybar gauge module custom/holiday (#562): countdown to the next Japanese national
# holiday on the left island. Caches the holidays-jp API data daily, picks the first
# holiday on/after today, and emits one return-type: json line.

set -euo pipefail

api_url="https://holidays-jp.github.io/api/v1/date.json"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="${cache_dir}/holidays_jp.json"
mkdir -p "$cache_dir"

today="$(date +%Y-%m-%d)"

# キャッシュの鮮度は mtime の日付で判定(日次更新)。取得失敗時は古いキャッシュで続行する
# Cache freshness = mtime date (daily refresh). On fetch failure keep serving the old cache.
if [ ! -s "$cache_file" ] || [ "$(date -r "$cache_file" +%Y-%m-%d)" != "$today" ]; then
  curl -sf --max-time 10 "$api_url" -o "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file" || true
fi

# キャッシュも無い(初回起動でオフライン等) → 非表示
# No cache at all (first run while offline, etc.) -> hide the module.
if [ ! -s "$cache_file" ]; then
  jq -cn '{text: "", tooltip: ""}'
  exit 0
fi

# 今日以降で最初の祝日を1件取り出す(ISO日付なので文字列比較でそのまま並ぶ)
# Pick the first holiday on/after today (ISO dates sort lexicographically).
next="$(jq -r --arg today "$today" '
  to_entries | map(select(.key >= $today)) | sort_by(.key) | first
  | if . == null then "" else "\(.key)|\(.value)" end
' "$cache_file")"

# データの終端(来年分が未公開の年末など)に達したら非表示
# Past the end of the dataset (e.g. year-end before next year is published) -> hide.
if [ -z "$next" ]; then
  jq -cn '{text: "", tooltip: ""}'
  exit 0
fi

IFS='|' read -r hdate hname <<<"$next"
days_until=$(( ($(date -d "$hdate" +%s) - $(date -d "$today" +%s)) / 86400 ))

# ツールチップ用の日付(例: 8/11(火))
# Human date for the tooltip (e.g. 8/11(火)).
hdate_human="$(LC_TIME=ja_JP.UTF-8 date -d "$hdate" "+%-m/%-d(%a)")"

# バーに出す1行の文言を決める。days=0 は今日が祝日。
# Decide the one-line text for the bar. days=0 means today IS the holiday.
format_countdown() {
  local days="$1" name="$2"
  case "$days" in
    0)  echo "今日は 🎌 ${name} 🎌" ;;
    1)  echo "明日は 🎌 ${name} 🎌" ;;
    *)  echo "${days}日後は 🎌 ${name} 🎌" ;;
  esac
}

text="$(format_countdown "$days_until" "$hname")"

jq -cn \
  --arg text "$text" \
  --arg tooltip "次の祝日: ${hdate_human} ${hname}" \
  '{text: $text, tooltip: $tooltip}'
