#!/bin/bash
# Claude Code Status Line — Starship "Myth Dark Pointed" full powerline port
# starship.toml (Myth Dark Pointed) の配色と pointed セグメントを 24bit カラーで忠実に再現する
# Faithful port of .config/starship/starship.toml: colored pills with U+E0B0 arrows on a #464347 base band
#
# Segments: user > host > dir > git branch > git status > model > context gauge
# Base-band text (cmd_duration style): session duration / cost / lines changed / rate limits (5h & 7d)

set -euo pipefail

input=$(cat)

# ---------- helpers ----------

# "#RRGGBB" -> "R;G;B" (ANSI 24bit 用 / for ANSI true-color sequences)
hex2rgb() {
  local h=${1#\#}
  printf '%d;%d;%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

ARROW=$''
BASE_RGB=$(hex2rgb "#464347")

line=""

# 色付きピルを1個追加 / append one colored pill: seg <bg_hex> <fg_hex> <text>
# 左端: セグメント色の上にベース色の  (内側にえぐれたトゲ)
# 右端: ベース色の上にセグメント色の  (外へ突き出るトゲ)
seg() {
  local bg fg
  bg=$(hex2rgb "$1")
  fg=$(hex2rgb "$2")
  line+="\033[48;2;${bg}m\033[38;2;${BASE_RGB}m${ARROW}\033[38;2;${fg}m $3 \033[48;2;${BASE_RGB}m\033[38;2;${bg}m${ARROW}"
}

# ピルにせずベース帯に直接載せる (starship の cmd_duration 方式) / plain text on the base band
plain() {
  line+="\033[48;2;${BASE_RGB}m\033[38;2;$(hex2rgb "$1")m $2"
}

# ---------- extract JSON fields ----------

model=$(echo "$input" | jq -r '.model.display_name // "?"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

# レートリミット使用率 (Pro/Max のみ、初回 API レスポンス後に出現) / rate limit usage, appears after first API response
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# コンテキスト使用率 / context window usage percentage
pct=""
usage=$(echo "$input" | jq '.context_window.current_usage // empty')
if [ -n "$usage" ]; then
  current=$(echo "$usage" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
  size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
  if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
    pct=$((current * 100 / size))
  fi
fi

# ---------- context gauge color ----------

# 使用率に応じたゲージ色を返す / return gauge pill color for a usage percentage
# 引数: $1 = 使用率 (0-100 の整数) / usage percent as integer
# 出力: "#RRGGBB" を echo する / echo a "#RRGGBB" hex color
context_gauge_color() {
  # 60% 以上は赤系にする / red-ish for >= 60%
  if [ "$1" -ge 60 ]; then
    echo "#ff3322"
    return
  fi
  # 40% 以上は黄色系にする / yellow-ish for >= 40%
  if [ "$1" -ge 40 ]; then
    echo "#E0B25D"
    return
  fi
  # それ以外は緑系にする / green-ish for < 40%
  echo "#96ab5f"
}

# ---------- build segments ----------

# 先頭キャップ: ベース帯の左端 (starship の format 先頭と同じ #AFD700 の三角)
line+="\033[48;2;${BASE_RGB}m\033[38;2;$(hex2rgb "#AFD700")m${ARROW}"

# username (bg:#3388FF fg:#EEEEEE)
seg "#3388FF" "#EEEEEE" " $(whoami)"

# hostname (bg:#AFD700 fg:#111111)
seg "#AFD700" "#111111" " $(hostname -s 2>/dev/null || hostname)"

# directory (bg:#6F6A70 fg:#EEEEEE) — プロジェクト相対、~ は  に置換
# NOTE: 置換側の \~ は必須 — 素の ~ だとチルダ展開されて $HOME に戻ってしまう
# The backslash in the replacement is required: a bare ~ tilde-expands back to $HOME
if [ -n "$project_dir" ] && [ "$current_dir" != "$project_dir" ]; then
  display_dir="${current_dir#"$project_dir"/}"
  if [ "$display_dir" = "$current_dir" ]; then
    display_dir="${current_dir/#"$HOME"/\~}"
  fi
else
  display_dir="${current_dir/#"$HOME"/\~}"
fi
display_dir="${display_dir/#\~/ }"
seg "#6F6A70" "#EEEEEE" "$display_dir"

# git branch (bg:#96ab5f fg:#111111) + git status (bg:#E0B25D fg:#000000)
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || true)
  if [ -n "$branch" ]; then
    seg "#96ab5f" "#111111" "󰊢 $branch"

    # starship の git_status と同じシンボルでカウント表示 / same symbols as starship's git_status
    porcelain=$(git -C "$current_dir" status --porcelain 2>/dev/null || true)
    status_text=""
    if [ -n "$porcelain" ]; then
      staged=$(grep -c '^[MADRC].' <<<"$porcelain" || true)
      modified=$(grep -c '^.[MD]' <<<"$porcelain" || true)
      untracked=$(grep -c '^??' <<<"$porcelain" || true)
      [ "$staged" -gt 0 ] && status_text+=" ${staged} "
      [ "$modified" -gt 0 ] && status_text+="󰏫 ${modified} "
      [ "$untracked" -gt 0 ] && status_text+="󱪝 ${untracked} "
    fi
    # ahead/behind (upstream がある場合のみ) / only when an upstream exists
    counts=$(git -C "$current_dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
    if [ -n "$counts" ]; then
      behind=${counts%%$'\t'*}
      ahead=${counts##*$'\t'}
      [ "$ahead" -gt 0 ] && status_text+="⇡${ahead} "
      [ "$behind" -gt 0 ] && status_text+="⇣${behind} "
    fi
    if [ -n "$status_text" ]; then
      seg "#E0B25D" "#000000" "${status_text% }"
    fi
  fi
fi

# model (bg:#FF6AC1 fg:#111111) — テーマのアクセントピンク / theme accent pink
seg "#FF6AC1" "#111111" "󰧑 $model"

# context gauge — 使用率で色が変わるピル / pill color follows usage
if [ -n "$pct" ]; then
  filled=$((pct / 20))
  [ "$filled" -gt 5 ] && filled=5
  bar=""
  for ((i = 0; i < 5; i++)); do
    if [ "$i" -lt "$filled" ]; then bar+="▰"; else bar+="▱"; fi
  done
  seg "$(context_gauge_color "$pct")" "#111111" "󰍛 ${bar} ${pct}%"
fi

# ---------- base-band session info (cmd_duration 方式) ----------

# セッション時間 (fg:#FBDE2D — starship cmd_duration と同色 / same color as cmd_duration)
if [ -n "$duration_ms" ]; then
  mins=$((${duration_ms%.*} / 60000))
  if [ "$mins" -ge 60 ]; then
    plain "#FBDE2D" "⌛$((mins / 60))h$((mins % 60))m"
  else
    plain "#FBDE2D" "⌛${mins}m"
  fi
fi

# セッションコスト (fg:#FFA200 — starship time と同色 / same color as time)
if [ -n "$cost_usd" ]; then
  plain "#FFA200" "\$$(printf '%.2f' "$cost_usd")"
fi

# 変更行数 (+green / -red)
if [ -n "$lines_added" ] && [ "$lines_added" != "0" ]; then
  plain "#96ab5f" "+${lines_added}"
fi
if [ -n "$lines_removed" ] && [ "$lines_removed" != "0" ]; then
  plain "#ff3322" "-${lines_removed}"
fi

# レートリミット使用率 — 色はコンテキストゲージと同じ閾値を再利用 / reuse the gauge thresholds
if [ -n "$five_hour_pct" ]; then
  p5=${five_hour_pct%.*}
  plain "$(context_gauge_color "$p5")" "󰅐 5h:${p5}%"
fi
if [ -n "$seven_day_pct" ]; then
  p7=${seven_day_pct%.*}
  plain "$(context_gauge_color "$p7")" "󰃭 7d:${p7}%"
fi

# ---------- terminate the base band ----------
line+=" \033[0m\033[38;2;${BASE_RGB}m${ARROW}\033[0m"

printf '%b' "$line"
