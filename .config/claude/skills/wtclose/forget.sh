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
# The list lives in the workbench, which agents can edit, so a row is trusted
# only in the shape the gate writes it: a forgetting candidate must be inside
# workbench_dir, and a stale state file must be <memory_dir>/state_*.md.
# Other rows are ignored ("ignored list row: <row>" on stderr).
# 一覧はエージェントが書き換えられる作業記憶の中にあるので、検問が書く形の行
# だけを信じる。忘れる候補は workbench_dir の中、古い状態ファイルは
# <memory_dir>/state_*.md に限る。それ以外の行は捨て、標準エラーに
# 「ignored list row: <行>」と出す。
#
# The places always come from close_gate.sh --where next to this script; the
# overrides of close_gate.sh (WTCLOSE_VAULT, WTCLOSE_PROJECT, WTCLOSE_GIT) are
# removed from its environment.
# 置き場は、常にこのスクリプトの隣の close_gate.sh --where で求める。
# close_gate.sh の差し替え(WTCLOSE_VAULT・WTCLOSE_PROJECT・WTCLOSE_GIT)は、
# 呼ぶときの環境から外す。
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
#           "ignored list row: <row>" per ignored row / 捨てた一覧の行 1 件 1 行
#
# Exit codes / 終了コード:
#   0 every file was moved to the trash / 全部をゴミ箱に移せた
#   1 some arguments were refused; nothing was moved / 拒否があって何も動かしていない
#   2 environment problem (no places, no list, no gio, no arguments, or the
#     list was rewritten while this script ran); nothing was moved
#     環境の問題(置き場を求められない・一覧が無い・gio が無い・引数が無い・
#     一覧が途中で書き換わった)で何も動かしていない
#   3 gio trash failed midway; the files printed as "trashed" were moved, the
#     rest were not / gio trash が途中で失敗した。trashed と出した分は移し、
#     残りは動かしていない
#
# Tunable / 閾値:
#   WTCLOSE_FORGET_MAX_AGE_HOURS: refuse when the list is older than this (default 24)
#                                 一覧がこれより古ければ拒否する(既定 24 時間)
set -euo pipefail

readonly index_name='_reachability.md' # written by close_gate.sh / 検問が書く一覧
readonly log_name='_gate_log.jsonl'    # written by close_gate.sh / 検問が書く記録
readonly state_prefix='state_'         # <memory_dir>/state_*.md, as in close_gate.sh
readonly sec_cand='## 忘れる候補'
readonly sec_stale='## 古い状態ファイル'
max_age_hours="${WTCLOSE_FORGET_MAX_AGE_HOURS:-24}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die_env() {
  printf 'forget.sh: %s\n' "$1" >&2
  exit 2
}

case "${1:-}" in
  -h | --help) sed -n '2,/^set -euo/{/^#/p}' "$0"; exit 0 ;;
esac
[ "$#" -gt 0 ] || die_env '引数が無い。一覧の path 列のパスを 1 件以上渡す(使い方: forget.sh <パス>...)'
[[ "$max_age_hours" =~ ^[0-9]+$ ]] || die_env "WTCLOSE_FORGET_MAX_AGE_HOURS が整数ではない: $max_age_hours"

# ---------------------------------------------------------------------------
# Places / 置き場
# ---------------------------------------------------------------------------
where() {
  env -u WTCLOSE_VAULT -u WTCLOSE_PROJECT -u WTCLOSE_GIT \
    bash "$script_dir/close_gate.sh" --where "$1"
}
wb_dir="$(where workbench_dir)" \
  || die_env 'workbench_dir を求められない(close_gate.sh --where workbench_dir が失敗した)'
mem_dir="$(where memory_dir)" \
  || die_env 'memory_dir を求められない(close_gate.sh --where memory_dir が失敗した)'
[ -n "$wb_dir" ] || die_env 'workbench_dir が空である'
[ -n "$mem_dir" ] || die_env 'memory_dir が空である'
wb_dir="$(realpath -m -- "$wb_dir")"
mem_dir="$(realpath -m -- "$mem_dir")"

# Normalize a path: resolve the parent directory to an absolute physical path,
# but keep the last component as it is, so a symlink stays a symlink.
# Relative paths are relative to workbench_dir.
# パスを正規化する。親ディレクトリは物理的な絶対パスにし、最後の要素はそのまま
# 残す(symlink を辿らずに symlink として見るため)。相対パスは workbench_dir から。
norm_path() {
  local p="$1" dir base
  [[ "$p" == /* ]] || p="$wb_dir/$p"
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  dir="$(dirname -- "$p")"
  base="$(basename -- "$p")"
  dir="$(realpath -m -- "$dir")"
  printf '%s/%s\n' "${dir%/}" "$base"
}

# ---------------------------------------------------------------------------
# The list / 一覧
# ---------------------------------------------------------------------------
index="$wb_dir/$index_name"
[ -f "$index" ] || die_env "一覧 $index が無い。close_gate.sh --check --session <ID> で作る"
[ -r "$index" ] || die_env "一覧 $index を読めない"
command -v gio >/dev/null 2>&1 || die_env 'gio が無い(glib2 が入っていない)。何も動かしていない'

# Generation of the list: inode, mtime (ns) and size. close_gate.sh replaces
# the list by rename, so a rewrite changes the generation.
# 一覧の世代(inode・ナノ秒の更新時刻・大きさ)。検問は一覧を rename で置き換える
# ので、書き換わると世代が変わる。
generation() { stat -c '%i:%.9Y:%s' -- "$index"; }
gen_before="$(generation)" || die_env "一覧 $index の更新時刻を読めない"

# Rows of the two tables. The name is taken verbatim from just after the
# opening "| `" up to the next backtick, which must be followed by " |".
# Output: "C|S<TAB>name<TAB>row" for a usable row, "X<TAB>-<TAB>row" otherwise
# (not an empty field: read with IFS=TAB would merge two tabs into one).
# 2 つの表の行。名前は、行頭の「| `」の直後から次のバッククォートまでを変えずに
# 取り出し、その直後は「 |」でなければならない。捨てる行の名前の欄は「-」にする
# (空の欄にすると、IFS をタブにした read が 2 つのタブを 1 つに詰める)。
rows="$(
  awk -v s1="$sec_cand" -v s2="$sec_stale" '
    /^## / { kind = ($0 == s1) ? "C" : (($0 == s2) ? "S" : ""); next }
    kind != "" && substr($0, 1, 3) == "| `" {
      rest = substr($0, 4)
      i = index(rest, "`")
      name = (i > 0) ? substr(rest, 1, i - 1) : ""
      after = (i > 0) ? substr(rest, i + 1, 2) : ""
      if (i == 0 || name == "" || after != " |" || name ~ /[|\t]/ || name ~ /^[ ]|[ ]$/) {
        print "X\t-\t" $0
      } else {
        print kind "\t" name "\t" $0
      }
    }' "$index"
)" || die_env "一覧 $index を読めない"

gen_after="$(generation)" || die_env "一覧 $index の更新時刻を読めない"
[ "$gen_before" = "$gen_after" ] \
  || die_env '一覧が読んでいる途中で書き換わった。何も動かしていない。もう一度呼ぶ'

# Keep only rows in the shape the gate writes / 検問が書く形の行だけを残す
declare -A listed=()
while IFS=$'\t' read -r kind name row; do
  [ -n "$kind" ] || continue
  ok=''
  if [ "$kind" != X ]; then
    abs="$(norm_path "$name")"
    if [ "$kind" = C ]; then
      [[ "$abs" != "$wb_dir"/* ]] || ok=1
    else
      base="${abs##*/}"
      if [ "${abs%/*}" = "$mem_dir" ] && [[ "$base" == "$state_prefix"*.md ]]; then
        ok=1
      fi
    fi
  fi
  if [ -n "$ok" ]; then
    listed["$abs"]=1
  else
    printf 'ignored list row: %s\n' "$row" >&2
  fi
done <<<"$rows"

# Age of the list / 一覧の古さ
index_mtime="${gen_before#*:}"
index_mtime="${index_mtime%%[.:]*}"
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
  reason=''
  abs=''
  if [[ "$arg" == *['|`']* ]]; then
    reason='| か ` を含むパスは受け付けない'
  else
    abs="$(norm_path "$arg")"
    base="${abs##*/}"
  fi
  if [ -n "$reason" ]; then
    :
  elif [ -n "$stale_list" ]; then
    reason="$stale_list"
  elif [ "$base" = "$index_name" ] || [ "$base" = "$log_name" ]; then
    reason="検問の一覧と記録($index_name・$log_name)は消さない"
  elif [ -z "${listed[$abs]:-}" ]; then
    reason="一覧の「${sec_cand#\#\# }」にも「${sec_stale#\#\# }」にも載っていない($abs)"
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
gen_now="$(generation 2>/dev/null)" || gen_now=''
[ "$gen_before" = "$gen_now" ] \
  || die_env '一覧が確かめている途中で書き換わった。何も動かしていない。もう一度呼ぶ'

for abs in "${targets[@]}"; do
  if ! gio trash -- "$abs"; then
    printf 'forget.sh: gio trash が %s で失敗した。trashed と出した分だけ移し、残りは動かしていない\n' "$abs" >&2
    exit 3
  fi
  printf 'trashed %s\n' "$abs"
done
