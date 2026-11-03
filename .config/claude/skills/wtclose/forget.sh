#!/usr/bin/env bash
# Move approved work products to the desktop trash / 承認された作業物をゴミ箱に移す
#
# After the user approves, the /wt commander calls this script to forget the
# paths listed in the close gate's list <workbench_dir>/_reachability.md
# (sections "## 忘れる候補" and "## 古い状態ファイル"). Every argument is
# checked first; if any one of them is refused, nothing is moved. The files go
# to the desktop trash with "gio trash", so they can be restored; emptying the
# trash is up to the user. This script never uses rm.
# ユーザーが OK を出した後、/wt の司令塔がこのスクリプトを呼び、検問の一覧
# <workbench_dir>/_reachability.md の「## 忘れる候補」と「## 古い状態ファイル」
# に載ったパスを忘れる。先に全部の引数を確かめ、1 件でも拒否があれば 1 件も
# 動かさない。ファイルは gio trash でデスクトップのゴミ箱に移すので、戻せる。
# ゴミ箱を空にするのはユーザーである。このスクリプトは rm を使わない。
#
# Usage / 使い方:
#   forget.sh <path>...
#     path: as written in the "path" column of the list (relative to
#           workbench_dir for forgetting candidates, absolute for stale state
#           files), or an absolute path.
#           一覧の path 列のとおりの形(忘れる候補は workbench_dir からの相対
#           パス、古い状態ファイルは絶対パス)か、絶対パス。
#
# Output / 出力:
#   stdout: "trashed <absolute path>" per file / 1 件 1 行
#   stderr: "refused <argument>: <reason>" per refusal / 拒否 1 件 1 行
#
# Exit codes / 終了コード:
#   0 every file was moved to the trash / 全部をゴミ箱に移せた
#   1 some arguments were refused; nothing was moved / 拒否があって何も動かしていない
#   2 environment problem (no workbench_dir, no list, no gio, no arguments);
#     nothing was moved
#     環境の問題(置き場を求められない・一覧が無い・gio が無い・引数が無い)で
#     何も動かしていない
#   3 gio trash failed midway; the files printed as "trashed" were moved, the
#     rest were not / gio trash が途中で失敗した。trashed と出した分は移し、
#     残りは動かしていない
#
# Overrides / 差し替え:
#   WTCLOSE_WORKBENCH_DIR       : workbench_dir (default: close_gate.sh --where workbench_dir)
#                                 置き場(既定は close_gate.sh --where workbench_dir)
#   WTCLOSE_FORGET_MAX_AGE_HOURS: refuse when the list is older than this (default 24)
#                                 一覧がこれより古ければ拒否する(既定 24 時間)
set -euo pipefail

readonly index_name='_reachability.md' # written by close_gate.sh / 検問が書く一覧
readonly log_name='_gate_log.jsonl'    # written by close_gate.sh / 検問が書く記録
readonly -a forget_sections=('## 忘れる候補' '## 古い状態ファイル')
max_age_hours="${WTCLOSE_FORGET_MAX_AGE_HOURS:-24}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die_env() {
  printf 'forget.sh: %s\n' "$1" >&2
  exit 2
}

case "${1:-}" in
  -h | --help) sed -n '2,43p' "$0"; exit 0 ;;
esac
[ "$#" -gt 0 ] || die_env '引数が無い。一覧の path 列のパスを 1 件以上渡す(使い方: forget.sh <パス>...)'
[[ "$max_age_hours" =~ ^[0-9]+$ ]] || die_env "WTCLOSE_FORGET_MAX_AGE_HOURS が整数ではない: $max_age_hours"

# ---------------------------------------------------------------------------
# Places and the list / 置き場と一覧
# ---------------------------------------------------------------------------
wb_dir="${WTCLOSE_WORKBENCH_DIR:-}"
if [ -z "$wb_dir" ]; then
  wb_dir="$(bash "$script_dir/close_gate.sh" --where workbench_dir)" \
    || die_env 'workbench_dir を求められない(close_gate.sh --where workbench_dir が失敗した)'
fi
[ -n "$wb_dir" ] || die_env 'workbench_dir が空である'

# Normalize a path: resolve the parent directory to an absolute physical path,
# but keep the last component as it is, so a symlink stays a symlink.
# パスを正規化する。親ディレクトリは物理的な絶対パスにし、最後の要素はそのまま
# 残す(symlink を辿らずに symlink として見るため)。
norm_path() {
  local p="$1" dir base
  [[ "$p" == /* ]] || p="$wb_dir/$p"
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  dir="$(dirname -- "$p")"
  base="$(basename -- "$p")"
  dir="$(realpath -m -- "$dir")"
  printf '%s/%s\n' "${dir%/}" "$base"
}

wb_dir="$(realpath -m -- "$wb_dir")"
index="$wb_dir/$index_name"
[ -f "$index" ] || die_env "一覧 $index が無い。close_gate.sh --check --session <ID> で作る"
[ -r "$index" ] || die_env "一覧 $index を読めない"
command -v gio >/dev/null 2>&1 || die_env 'gio が無い(glib2 が入っていない)。何も動かしていない'

# Rows of the two tables, normalized / 2 つの表の行を正規化したもの
declare -A listed=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  listed["$(norm_path "$p")"]=1
done < <(
  awk -v s1="${forget_sections[0]}" -v s2="${forget_sections[1]}" '
    /^## / { insec = ($0 == s1 || $0 == s2); next }
    insec && /^\| `/ {
      split($0, c, "|"); p = c[2]
      gsub(/^[ \t`]+|[ \t`]+$/, "", p)
      print p
    }' "$index"
)

# Age of the list / 一覧の古さ
index_mtime="$(stat -c %Y -- "$index")"
age_sec=$(($(date +%s) - index_mtime))
stale_list=''
if [ "$age_sec" -gt $((max_age_hours * 3600)) ]; then
  stale_list="一覧が $((age_sec / 3600)) 時間前のもので、${max_age_hours} 時間より古い"
fi

# ---------------------------------------------------------------------------
# Check every argument first / 先に全部の引数を確かめる
# ---------------------------------------------------------------------------
refused=0
declare -a targets=()
declare -A seen=()
for arg in "$@"; do
  abs="$(norm_path "$arg")"
  base="${abs##*/}"
  reason=''
  if [ -n "$stale_list" ]; then
    reason="$stale_list"
  elif [ "$base" = "$index_name" ] || [ "$base" = "$log_name" ]; then
    reason="検問の一覧と記録($index_name・$log_name)は消さない"
  elif [ -z "${listed[$abs]:-}" ]; then
    reason="一覧の「${forget_sections[0]#\#\# }」にも「${forget_sections[1]#\#\# }」にも載っていない($abs)"
  elif [ -L "$abs" ]; then
    reason='symlink は消さない'
  elif [ -d "$abs" ]; then
    reason='ディレクトリは消さない'
  elif [ ! -f "$abs" ]; then
    reason='通常のファイルとして存在しない'
  fi
  if [ -n "$reason" ]; then
    printf 'refused %s: %s\n' "$arg" "$reason" >&2
    refused=$((refused + 1))
    continue
  fi
  [ -n "${seen[$abs]:-}" ] || targets+=("$abs")
  seen["$abs"]=1
done

if [ "$refused" -gt 0 ]; then
  if [ -n "$stale_list" ]; then
    printf 'forget.sh: 一覧を bash ~/.claude/skills/wtclose/close_gate.sh --check --session <ID> で作り直してから、もう一度呼ぶ\n' >&2
  fi
  printf 'forget.sh: %d 件を拒否したので、1 件も動かしていない\n' "$refused" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Move to the trash / ゴミ箱に移す
# ---------------------------------------------------------------------------
for abs in "${targets[@]}"; do
  if ! gio trash -- "$abs"; then
    printf 'forget.sh: gio trash が %s で失敗した。trashed と出した分だけ移し、残りは動かしていない\n' "$abs" >&2
    exit 3
  fi
  printf 'trashed %s\n' "$abs"
done
