#!/bin/bash

# Bring/Go 型ウィンドウピッカー(#346)
# wofi で任意のウィンドウを選び、現在のワークスペースへ引き込む(bring)か、
# そのウィンドウの場所へ飛ぶ(go)かを選べる。引数なしは bring として動く。
# Bring/Go style window picker (#346): pick any window via wofi, then either
# pull it into the current workspace (bring) or jump to where it lives (go).
# Defaults to bring when called with no argument.

set -euo pipefail

mode="${1:-bring}"

# mapped なウィンドウを「class: title [ws]」の表示行とアドレスのペアで、
# 同じ並び順の配列に読み込む(タブ区切り、選択後にアドレスへ逆引きするため)
# Load mapped windows as "display line \t address" pairs in matching order,
# so the address can be looked back up once wofi returns the chosen line.
mapfile -t entries < <(hyprctl clients -j | jq -r '
  .[] | select(.mapped == true) |
  "\(.class): \(.title) [\(.workspace.name)]\t\(.address)"
')

if [ "${#entries[@]}" -eq 0 ]; then
  notify-send "Window Picker" "引き込めるウィンドウがありません"
  exit 0
fi

# 表示行の先頭にインデックスを振る(同名ウィンドウがあっても選択後に
# インデックスで一意にアドレスへ逆引きできるようにするため)
# Prefix each display line with its index, so the address lookup after
# selection is by position rather than by (possibly duplicate) text match.
displays=()
addresses=()
i=0
for entry in "${entries[@]}"; do
  displays+=("${i}: ${entry%$'\t'*}")
  addresses+=("${entry##*$'\t'}")
  i=$((i + 1))
done

selection="$(printf '%s\n' "${displays[@]}" | wofi --dmenu --prompt "Window")"

# Escape 等で選択なしなら何もしない / no-op when the user cancels the picker
[ -z "$selection" ] && exit 0

idx="${selection%%:*}"
address="${addresses[$idx]:-}"

[ -z "$address" ] && exit 0

case "$mode" in
  bring)
    # special workspace 上から実行される場合もあるため id ではなく name を使う
    # Use name, not id, since this may run from a (named) special workspace
    active_ws="$(hyprctl activeworkspace -j | jq -r '.name')"
    # 計器盤(Waybar custom/bring #422)用に「何をどこから借りたか」を記録する。
    # 移動の dispatch より先に書くことで、socket2 の movewindow イベントが
    # 購読側に届いた時点で状態ファイルが確定していることを保証する。
    # Record what was borrowed and from where, for the Waybar gauge (#422).
    # Written *before* dispatching the move so the state file is already
    # settled when the movewindow event reaches the socket2 subscriber.
    # temp + mv で書き込みをアトミックにする(同一ディレクトリ内の rename は
    # アトミックなので、読み手が書きかけの JSON を観測することがない)
    # Write via temp + mv so the update is atomic (same-directory rename),
    # ensuring readers never observe a truncated JSON file.
    state_file="${XDG_RUNTIME_DIR:-/tmp}/bring_state.json"
    hyprctl clients -j | jq -c --arg addr "$address" --arg dest "$active_ws" '
      .[] | select(.address == $addr) |
      {address, class, title, origin_ws: .workspace.name, dest_ws: $dest}
    ' > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
    hyprctl dispatch movetoworkspacesilent "${active_ws},address:${address}"
    hyprctl dispatch focuswindow "address:${address}"
    ;;
  go)
    hyprctl dispatch focuswindow "address:${address}"
    ;;
  *)
    echo "Unknown mode: ${mode} (expected 'bring' or 'go')" >&2
    exit 1
    ;;
esac
