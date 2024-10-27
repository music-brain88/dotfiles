#!/bin/bash
# ~/.config/hypr/scripts/wofi-window-switcher.sh

# ウィンドウ一覧を取得し、選択されたウィンドウにフォーカスを移動
selected=$(hyprctl clients -j | \
    jq -r '.[] | select(.class != "") | "\(.address)|\(.class) - \(.title)"' | \
    column -t -s'|' | \
    wofi --dmenu --prompt "Switch Window" --insensitive true) 

if [ ! -z "$selected" ]; then
    address=$(echo "$selected" | awk '{print $1}')
    hyprctl dispatch focuswindow "address:${address}"
fi

# スクリプトに実行権限を付与
# chmod +x ~/.config/hypr/scripts/wofi-window-switcher.sh
