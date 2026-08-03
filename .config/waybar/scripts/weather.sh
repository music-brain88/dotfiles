#!/bin/bash

# Waybar 計器モジュール custom/weather (#563)
# 左島(現実世界の窓)に現在の天気を表示する。wttr.in から観測値を1リクエストで取得し、
# return-type: json 形式で1行出力して終了する(常駐しない — interval 1800 で再実行)。
# Waybar gauge module custom/weather (#563): shows current conditions on the left
# island (the window to the real world). Fetches one reading from wttr.in in a
# single request, emits one return-type: json line, and exits (not resident —
# waybar reruns it via interval 1800).

set -euo pipefail

# 場所未指定 = wttr.in の IP ジオロケーション任せ。固定したい時は
# WAYBAR_WEATHER_LOCATION(例: Tokyo)で上書きする。
# Empty location = wttr.in's IP geolocation; override with
# WAYBAR_WEATHER_LOCATION (e.g. "Tokyo") to pin a place.
location="${WAYBAR_WEATHER_LOCATION:-}"

# 全項目を1リクエストで取り | で分解する: 天気アイコン|気温|天況|体感|湿度|風|場所
# One request for every field, split on "|": icon|temp|condition|feels|humidity|wind|place
if ! reading="$(curl -sf --max-time 10 "https://wttr.in/${location}?format=%c|%t|%C|%f|%h|%w|%l")"; then
  # 取得失敗は「表示するものがない」扱い(text が空だとモジュール非表示)。
  # exec-if の ping を通過した後の一時的な失敗もここで握る。
  # A failed fetch means "nothing to display" (empty text hides the module),
  # covering transient errors that slip past the exec-if ping.
  jq -cn '{text: "", tooltip: ""}'
  exit 0
fi

IFS='|' read -r icon temp cond feels humidity wind place <<<"$reading"

# wttr.in の絵文字アイコンは余白(パディング用スペース)を含むので除去する
# The emoji icon from wttr.in carries padding spaces — strip them.
icon="${icon// /}"

# alt は config 側の format-alt "{alt}: {}"(右クリック)で場所名として使われる
# alt feeds the config's format-alt "{alt}: {}" (right-click) as the place name.
jq -cn \
  --arg text "${icon} ${temp}" \
  --arg alt "${place}" \
  --arg tooltip "${place}: ${cond} ${temp} (体感 ${feels}) 湿度 ${humidity} 風 ${wind}" \
  '{text: $text, alt: $alt, tooltip: $tooltip}'
