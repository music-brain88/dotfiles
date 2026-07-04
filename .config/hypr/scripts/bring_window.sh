#!/bin/bash

# Bring/Go 型ウィンドウピッカー(#346)
# wofi で任意のウィンドウを選び、現在のワークスペースへ引き込む(bring)か、
# そのウィンドウの場所へ飛ぶ(go)かを選べる。引数なしは bring として動く。
# Bring/Go style window picker (#346): pick any window via wofi, then either
# pull it into the current workspace (bring) or jump to where it lives (go).
# Defaults to bring when called with no argument.

set -euo pipefail

mode="${1:-bring}"

clients_json="$(hyprctl clients -j)"

# mapped なウィンドウを「class: title [ws]」の表示行とアドレスのペアで、
# 同じ並び順の配列に読み込む(タブ区切り、選択後にアドレスへ逆引きするため)
# Load mapped windows as "display line \t address" pairs in matching order,
# so the address can be looked back up once wofi returns the chosen line.
mapfile -t entries < <(echo "$clients_json" | jq -r '
  .[] | select(.mapped == true) |
  "\(.class): \(.title) [\(.workspace.name)]\t\(.address)"
')

if [ "${#entries[@]}" -eq 0 ]; then
  notify-send "Window Picker" "引き込めるウィンドウがありません"
  exit 0
fi

displays=()
addresses=()
for entry in "${entries[@]}"; do
  displays+=("${entry%$'\t'*}")
  addresses+=("${entry##*$'\t'}")
done

selection="$(printf '%s\n' "${displays[@]}" | wofi --dmenu --prompt "Window")"

# Escape 等で選択なしなら何もしない / no-op when the user cancels the picker
[ -z "$selection" ] && exit 0

address=""
for i in "${!displays[@]}"; do
  if [ "${displays[$i]}" = "$selection" ]; then
    address="${addresses[$i]}"
    break
  fi
done

[ -z "$address" ] && exit 0

case "$mode" in
  bring)
    active_ws="$(hyprctl activeworkspace -j | jq -r '.id')"
    hyprctl dispatch movetoworkspacesilent "${active_ws},address:${address}"
    hyprctl dispatch focuswindow "address:${address}"
    ;;
  go)
    hyprctl dispatch focuswindow "address:${address}"
    ;;
esac
