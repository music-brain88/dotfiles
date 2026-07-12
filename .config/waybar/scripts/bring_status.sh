#!/bin/bash

# Waybar 計器盤モジュール custom/bring (#422)
# bring_window.sh(Super+Y)が記録した「現在の参照ウィンドウ」を表示する常駐スクリプト。
# Hyprland socket2 のイベント購読で駆動し、窓の移動・クローズの瞬間に表示を更新する
# (ポーリングなし)。操作系は一切持たない — Waybar は状態表示のみ(Bring 型の計器盤)。
# Waybar gauge module custom/bring (#422): long-running script that displays the
# "current reference window" recorded by bring_window.sh (Super+Y). Driven by
# Hyprland socket2 event subscription — updates the instant a window moves or
# closes, no polling. Display only; all control stays on Super+Y (Bring-style).

set -euo pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/bring_state.json"
sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# グリフは raw で書かず ANSI-C の \uXXXX エスケープで書く(不可視文字の罠 — PR #366)
# Write the glyph as an ANSI-C \uXXXX escape, never raw (invisible-char trap, PR #366)
icon=$'\uf0c6' # nf-fa-paperclip

# Waybar の return-type: json 形式で1行出力する(text が空だとモジュール非表示)
# Emit one line in Waybar's return-type: json format (empty text hides the module)
emit_json() {
  jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" \
    '{text: $text, tooltip: $tooltip, class: $class}'
}

# 状態ファイルと実際のウィンドウ一覧を突き合わせて、計器盤の表示を1回分出力する
# Cross-check the state file against the live window list and emit one reading
emit() {
  # まだ何も借りていない(状態ファイルなし/空) → 非表示
  # Nothing borrowed yet (state file absent/empty) -> hide the module
  if [ ! -s "$state_file" ]; then
    emit_json "" "" ""
    return
  fi

  local address class title origin_ws dest_ws cur_ws
  address="$(jq -r '.address' "$state_file")"
  class="$(jq -r '.class' "$state_file")"
  title="$(jq -r '.title' "$state_file")"
  origin_ws="$(jq -r '.origin_ws' "$state_file")"
  dest_ws="$(jq -r '.dest_ws' "$state_file")"

  # 参照ウィンドウの現在地(閉じられていたら空文字になる)。
  # hyprctl の一時的な失敗で常駐スクリプトごと死なないよう失敗は空扱いにする
  # (set -e 下では $() 内の失敗も伝播するため)。
  # Where the reference window is right now (empty string if it was closed).
  # Treat hyprctl failures as empty so a transient error can't kill the gauge
  # (under set -e, failures inside $() propagate to the assignment).
  cur_ws="$(hyprctl clients -j 2>/dev/null | jq -r --arg addr "$address" '
    .[] | select(.address == $addr) | .workspace.name
  ' || true)"

  # 判定は3状態: 閉じられた=非表示 / 借り先にいる=active / よそへ移動した=stray
  # tooltip は貸出カード形式で「誰を・どこから借りたか」を出す
  # Three states: closed = hidden / at the borrow destination = active /
  # wandered off elsewhere = stray. Tooltip reads like a lending card.
  if [ -z "$cur_ws" ]; then
    # 参照ウィンドウが閉じられた → 非表示
    emit_json "" "" ""
  elif [ "$cur_ws" = "$dest_ws" ]; then
    # 参照ウィンドウが借り先にいる → active
    emit_json "$icon $title" "$class ← ws:$origin_ws" "active"
  else
    # 参照ウィンドウがよそ(借り元含む)へ移動した → stray
    emit_json "$icon $title" "$class ← ws:$origin_ws(今は ws:$cur_ws)" "stray"
  fi
}

# 起動直後に現在値を1回出す(Waybar 再起動時に前回の状態を復元するため)
# Emit once at startup so a Waybar restart restores the current reading
emit

# socket2 を購読し、計器盤に関係するイベントの時だけ再評価する。
# nc は libressl 版(dev-tools.nix の netcat)。-U: unix socket、-d: stdin を読まない。
# Subscribe to socket2 and re-evaluate only on events that can change the gauge.
# nc is the libressl flavor (netcat in dev-tools.nix); -U unix socket, -d no stdin.
nc -Ud "$sock" | while IFS= read -r line; do
  case "$line" in
    movewindow*|closewindow*|workspace*) emit ;;
  esac
done
