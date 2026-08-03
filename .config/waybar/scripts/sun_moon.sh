#!/bin/bash

# Waybar 計器モジュール custom/sun_moon (#562)
# 左島(現実世界の窓)に月相と日の出/日の入りを表示する。weather.sh と同じく wttr.in
# から1リクエストで取得し、return-type: json を1行出力して終了する(interval 再実行)。
# Waybar gauge module custom/sun_moon (#562): moon phase plus sunrise/sunset on the
# left island (the window to the real world). Like weather.sh, one wttr.in request,
# one return-type: json line, then exit (waybar reruns via interval).

set -euo pipefail

# weather.sh と同じ場所解決を使う(空 = IP ジオロケーション)
# Same place resolution as weather.sh (empty = IP geolocation).
location="${WAYBAR_WEATHER_LOCATION:-}"

# 月相絵文字|月齢|夜明け|日の出|日の入り|日暮れ を1リクエストで取る
# One request for moon-phase emoji|moon day|dawn|sunrise|sunset|dusk.
if ! reading="$(curl -sf --max-time 10 "https://wttr.in/${location}?format=%m|%M|%D|%S|%s|%d")"; then
  # 取得失敗は「表示するものがない」扱い(weather.sh と同じ振る舞い)
  # A failed fetch means "nothing to display" (same behavior as weather.sh).
  jq -cn '{text: "", tooltip: ""}'
  exit 0
fi

IFS='|' read -r moon moonday dawn sunrise sunset dusk <<<"$reading"
moon="${moon// /}"

# wttr.in の時刻は HH:MM:SS — バー上は分までで充分なので秒を落とす
# wttr.in returns HH:MM:SS; minutes are enough on the bar, drop the seconds.
sunrise="${sunrise%:*}"
sunset="${sunset%:*}"
dawn="${dawn%:*}"
dusk="${dusk%:*}"

jq -cn \
  --arg text "${moon} 🌅${sunrise} 🌇${sunset}" \
  --arg tooltip "月齢 ${moonday} / 夜明け ${dawn} → 日の出 ${sunrise} / 日の入り ${sunset} → 日暮れ ${dusk}" \
  '{text: $text, tooltip: $tooltip}'
