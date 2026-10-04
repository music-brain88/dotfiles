#!/usr/bin/env bash
# Close gate for the /wt commander / /wt の司令塔の締めの検問
#
# The Stop hook declared in wtclose/SKILL.md (once: true) runs this script at
# the end of every commander turn. It reads the hook input JSON on stdin,
# checks the closing conditions P1-P8 against real state (gh, git, the vault)
# and exits 2 with every unmet condition on stderr, so that Claude keeps
# working until all of them are met.
# wtclose/SKILL.md の Stop hook(once: true)が、司令塔のターンが終わるたびに
# このスクリプトを呼ぶ。stdin の hook 入力を読み、締めの条件 P1〜P8 を実物
# (gh・git・vault)で確かめる。そろっていない条件があれば、その全部を stderr
# に書いて exit 2 で返し、条件がそろうまで司令塔のターンを続けさせる。
#
# Usage / 使い方:
#   close_gate.sh                          # as the Stop hook (stdin = hook input JSON)
#   close_gate.sh --check --session <id>   # dry run by the commander / 司令塔が手で試す
#   close_gate.sh --where [key]            # print the resolved places / 置き場を出す
#                                          #   key: project | memory_dir | workbench_dir
#
# The gate never deletes or moves work products.
# 検問は作業物を消さないし、移さない。
#
# Exit codes / 終了コード:
#   0 pass (or the gate was skipped) / 通過(または検問を省いた)
#   2 some conditions are unmet; only emit_result returns 2 / 条件がそろわない(emit_result だけが返す)
#   1 the gate itself failed unexpectedly (non-blocking; the hook stays registered)
#     検問自身が想定外に失敗した(止めない。hook は登録されたまま残る)
#   3 --where found no vault / --where で vault が見つからない
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Format contract / 書式の契約
# Everything the commander writes and this script reads is defined here only.
# The values were decided by the user on 2026-10-04 (provisional, see #658).
# 司令塔が書き、検問が読む書式は、この節だけで定める。
# 値は 2026-10-04 にユーザーが決めた(暫定。#658 参照)。
# ---------------------------------------------------------------------------
readonly state_prefix='state_'      # <memory_dir>/state_<commander name>.md
readonly fm_as_of='as_of'           # frontmatter: "YYYY-MM-DD HH:MM" (local time)
readonly fm_session='session_id'    # frontmatter: the commander's session ID
readonly as_of_re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'
readonly sec_remaining='残っているもの' # P4 / P8
readonly sec_next='次の入口'           # P3
readonly -a state_sections=('稼働中の worker' '判定の途中' 'ユーザー待ち' "$sec_remaining" "$sec_next")
readonly -a reason_kinds=('マージ待ち' 'レビュー待ち' 'worker 稼働中' '別のセッションの管轄')
readonly pr_unverified_tag='PR の状態は未確認' # P8: "- [PR の状態は未確認] YYYY-MM-DD HH:MM ..."
# Optional repository qualifier (owner/repo) for P4 lines and unit:
#   P4:   "- [マージ待ち] PR owner/repo#663 ..."  (omitted = this repository)
#   unit: "owner/repo#663" | "owner/repo@feat/x" (omitted = this repository)
# P4 の行と unit に付けられる、任意のリポジトリの修飾子(省いたら自分のリポジトリ)。
readonly repo_re='[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'
readonly index_name='_reachability.md'      # list of "last reached" dates / 最後に辿れた日の一覧
readonly log_name='_gate_log.jsonl'         # one line per run / 1 回の判定を 1 行
readonly notes_rel='Zettelkasten/ResearchNotes'

# ---------------------------------------------------------------------------
# Tunables (provisional, see #658) / 閾値(暫定。#658 参照)
# dormant_days is shared by forgetting candidates and stale state files.
# dormant_days は、忘れる候補と古い状態ファイルの両方に使う。
# ---------------------------------------------------------------------------
max_lines="${WTCLOSE_MAX_LINES:-200}"      # P2
dormant_days="${WTCLOSE_DORMANT_DAYS:-14}" # P6 and stale state files / 古い状態ファイル
gh_timeout="${WTCLOSE_GH_TIMEOUT:-20}"     # P8 (seconds / 秒)

# ---------------------------------------------------------------------------
# Overrides (mainly for tests) / 差し替え(主にテスト用)
# WTCLOSE_VAULT   : vault root (default: $HOME/Documents/Obsidian)
# WTCLOSE_PROJECT : AgentMemory folder name / AgentMemory のフォルダ名
# WTCLOSE_NOW     : current local time "YYYY-MM-DD HH:MM" / 現在時刻
# WTCLOSE_GH      : gh command / gh の代わりに呼ぶコマンド
# WTCLOSE_GIT     : git command / git の代わりに呼ぶコマンド
# WTCLOSE_FAULT   : exit code of a forced failure, to test the safety net
#                   安全網を試すために起こす失敗の終了コード
# ---------------------------------------------------------------------------
vault_override="${WTCLOSE_VAULT:-}"
default_vault="$HOME/Documents/Obsidian"
gh_cmd="${WTCLOSE_GH:-gh}"
git_cmd="${WTCLOSE_GIT:-git}"

# ---------------------------------------------------------------------------
# Safety net / 安全網
# Every intended exit goes through finish. Any other exit (a failed command
# under set -e, an unbound variable, ...) is an unexpected failure: the gate
# reports it, records it when it can, and exits 1 instead of 2, so that an
# accident never looks like "conditions are unmet" to Claude Code.
# 意図した終わり方は、すべて finish を通る。それ以外の終わり方(set -e の下で
# 失敗したコマンド、未定義の変数など)は想定外の失敗として扱う。検問はそれを
# 報告し、書けるときは記録し、2 ではなく 1 で終える。事故が Claude Code に
# 「条件がそろっていない」と読まれないようにするためである。
# ---------------------------------------------------------------------------
main_pid=$$
clean_exit=''
err_context=''
mode='hook'
tmp_dir=''
wb_dir=''

finish() {
  clean_exit=1
  exit "$1"
}

# shellcheck disable=SC2329 # invoked by the ERR trap / ERR の trap から呼ばれる
on_err() {
  # In a subshell, just leave: the parent shell records the failure.
  # サブシェルでは抜けるだけにする。失敗は親のシェルが控える。
  [ "$BASHPID" = "$main_pid" ] || exit "$1"
  [ -n "$err_context" ] || err_context="${2} 行目、終了コード ${1}: ${3}"
}

# shellcheck disable=SC2329 # invoked by the EXIT trap / EXIT の trap から呼ばれる
on_exit() {
  local rc=$? msg
  trap - ERR
  [ -z "$tmp_dir" ] || rm -rf "$tmp_dir"
  [ -z "$clean_exit" ] || return 0
  msg="wtclose の検問は、条件を確かめられなかった(close_gate.sh の ${err_context:-終了コード ${rc}})。このターンは止めない。hook は登録されたまま残るので、次のターンの終わりにもう一度確かめる。同じ失敗が続くなら、ユーザーに報告する。"
  printf '%s\n' "$msg" >&2
  if [ "$mode" = 'check' ]; then printf '%s\n' "$msg"; fi
  write_error_log "$msg" 2>/dev/null || true
  exit 1
}

trap 'on_err "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap on_exit EXIT

started_ns="$(date +%s%N)"
tmp_dir="$(mktemp -d)"

# ---------------------------------------------------------------------------
# Arguments and hook input / 引数と hook 入力
# ---------------------------------------------------------------------------
session_id=''
cwd_arg=''
where_key=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) mode='check' ;;
    --where)
      mode='where'
      if [ "$#" -gt 1 ] && [ "${2#--}" = "$2" ]; then
        where_key="$2"
        shift
      fi
      ;;
    --session) session_id="${2:-}"; shift ;;
    --cwd) cwd_arg="${2:-}"; shift ;;
    -h | --help) sed -n '2,30p' "$0"; finish 0 ;;
    *) echo "close_gate.sh: unknown argument: $1" >&2; finish 64 ;;
  esac
  shift
done

input_json=''
if [ "$mode" = 'hook' ]; then
  input_json="$(cat || true)"
fi

have_jq() { command -v jq >/dev/null 2>&1; }

# Read a top-level string field of the hook input (jq, or sed as a fallback).
# hook 入力の最上位の文字列フィールドを読む(jq が無ければ sed で代用する)。
input_field() {
  local key="$1"
  [ -n "$input_json" ] || return 0
  if have_jq; then
    printf '%s' "$input_json" | jq -r --arg k "$key" '.[$k] // empty | strings' 2>/dev/null || true
  else
    printf '%s' "$input_json" | tr '\n' ' ' \
      | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

stop_hook_active='false'
if [ "$mode" = 'hook' ]; then
  session_id="$(input_field session_id)"
  cwd_arg="$(input_field cwd)"
  if grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$input_json"; then
    stop_hook_active='true'
  fi
fi
work_dir="${cwd_arg:-$PWD}"

# ---------------------------------------------------------------------------
# Time / 時刻
# ---------------------------------------------------------------------------
now="${WTCLOSE_NOW:-$(date '+%Y-%m-%d %H:%M')}"
today="${now%% *}"
today_epoch="$(date -d "$today" +%s)"
if [ -n "${WTCLOSE_NOW:-}" ]; then
  ts="$(date -d "$now" '+%Y-%m-%dT%H:%M:%S%z')"
else
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
fi

# Days from a YYYY-MM-DD date to today; empty when the date is invalid.
# YYYY-MM-DD の日付から今日までの日数。日付が不正なら空を返す。
days_since() {
  local epoch
  epoch="$(date -d "$1" +%s 2>/dev/null)" || return 0
  echo $(((today_epoch - epoch) / 86400))
}

# ---------------------------------------------------------------------------
# Result accumulators / 判定結果の集計
# ---------------------------------------------------------------------------
fail_ids=()
fail_msgs=()
notes=()

# fail <id> <what is missing> <what to write to pass>
# fail <番号> <何がそろっていないか> <何を書けば通るか>
fail() {
  local how="${3//$'\n'/$'\n'      }"
  fail_ids+=("$1")
  fail_msgs+=("[$1] $2"$'\n'"    → 通すには: $how")
}

# note <text>: recorded and shown, but does not block / 記録して見せるが、止めない
note() {
  notes+=("$1")
}

# ---------------------------------------------------------------------------
# Generic readers / 汎用の読み取り
# ---------------------------------------------------------------------------
# Print the value of a frontmatter key (surrounding quotes removed).
# frontmatter のキーの値を出す(前後の引用符は外す)。
fm_get() {
  awk -v key="$2" -v q="'" '
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && $0 == "---" { exit }
    infm {
      k = $0; sub(/:.*/, "", k)
      if (k != key) next
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (substr(v, 1, 1) == "\"" || substr(v, 1, 1) == q) v = substr(v, 2, length(v) - 2)
      print v; exit
    }' "$1"
}

# Succeed when the file has the "## <heading>" line.
# 「## <見出し>」の行があれば成功を返す。
has_section() {
  awk -v h="$2" '
    substr($0, 1, 3) == "## " { t = substr($0, 4); sub(/[ \t]+$/, "", t); if (t == h) { found = 1; exit } }
    END { exit found ? 0 : 1 }' "$1"
}

# Print the lines under "## <heading>" up to the next "#" or "##" heading.
# 「## <見出し>」の下の行を、次の「#」か「##」の見出しの手前まで出す。
section_body() {
  awk -v h="$2" '
    /^##? / {
      if (insec) exit
      t = $0; sub(/^## /, "", t); sub(/[ \t]+$/, "", t)
      if (substr($0, 1, 3) == "## " && t == h) insec = 1
      next
    }
    insec { print }' "$1"
}

# Expand "~/" and "$HOME/", drop the trailing slash and canonicalize.
# 「~/」と「$HOME/」を展開し、末尾のスラッシュを外して正規化する。
norm_path() {
  local p="$1"
  # The patterns match the literal text "~/" and "$HOME/" written in the files.
  # パターンは、ファイルに書かれた文字どおりの「~/」と「$HOME/」に一致させる。
  # shellcheck disable=SC2088,SC2016
  case "$p" in
    '~') p="$HOME" ;;
    '~/'*) p="$HOME/${p#'~/'}" ;;
    '$HOME/'*) p="$HOME/${p#'$HOME/'}" ;;
  esac
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  realpath -m -- "$p" 2>/dev/null || printf '%s\n' "$p"
}

# Escape a string for JSON / JSON の文字列としてエスケープする
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/}"
  # Drop the other control characters (e.g. ANSI escapes from gh) so that a
  # log line always stays valid JSON / ほかの制御文字(gh の ANSI エスケープなど)を
  # 落とし、記録の行がいつも JSON として読めるようにする
  if [[ "$s" == *[[:cntrl:]]* ]]; then
    s="$(printf '%s' "$s" | LC_ALL=C tr -d '\001-\037\177')"
  fi
  printf '"%s"' "$s"
}

json_array() {
  local out='' item
  for item in "$@"; do
    out+="${out:+,}$(json_str "$item")"
  done
  printf '[%s]' "$out"
}

# Succeed when an owner/repo qualifier names this repository (empty = this one).
# owner/repo の修飾子が自分のリポジトリを指していれば成功(空は自分のリポジトリ)。
is_own_repo() {
  [ -z "$1" ] && return 0
  [ -n "$own_repo" ] && [ "${1,,}" = "${own_repo,,}" ]
}

is_reason_kind() {
  local k
  for k in "${reason_kinds[@]}"; do
    [ "$k" != "$1" ] || return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Real state: gh and git / 実物: gh と git
# ---------------------------------------------------------------------------
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$@"
  else
    shift
    "$@"
  fi
}

gh_error=''

# Print "number<TAB>headRefName" for each open PR. Return 1 when gh is unusable.
# open の PR を「番号<TAB>ブランチ名」で出す。gh が使えなければ 1 を返す。
list_open_prs() {
  if ! command -v "$gh_cmd" >/dev/null 2>&1; then
    gh_error="gh コマンドが見つからない"
    return 1
  fi
  local rc=0
  (cd "$repo_root" && run_with_timeout "$gh_timeout" "$gh_cmd" pr list --state open --limit 200 \
    --json number,headRefName --jq '.[] | "\(.number)\t\(.headRefName)"') \
    >"$tmp_dir/prs" 2>"$tmp_dir/prs.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    gh_error="gh pr list が失敗した(exit $rc): $(head -n 3 "$tmp_dir/prs.err" | tr '\n' ' ')"
    return 1
  fi
  grep -E '^[0-9]+'$'\t' "$tmp_dir/prs" || true
}

# Print "path<TAB>branch" for each linked worktree (the main worktree excluded).
# linked worktree を「パス<TAB>ブランチ名」で出す(main の worktree は除く)。
list_worktrees() {
  "$git_cmd" -C "$repo_root" worktree list --porcelain | awk '
    function emit() { if (n > 1) print path "\t" branch }
    /^worktree / { if (n > 0) emit(); n++; path = substr($0, 10); branch = ""; next }
    /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch); next }
    END { if (n > 0) emit() }'
}

# ---------------------------------------------------------------------------
# Places / 置き場
# ---------------------------------------------------------------------------
repo_root=''
main_root=''
project=''
vault=''
mem_dir=''
wb_dir=''

# Resolve <project>, the memory directory and the workbench directory.
# Order: WTCLOSE_PROJECT -> autoMemoryDirectory of the main checkout -> its name.
# When WTCLOSE_VAULT is set, only the folder name is taken from
# autoMemoryDirectory, so tests never reach the real vault.
# <project>・記憶・作業記憶の場所を求める。順番は WTCLOSE_PROJECT →
# main のリポジトリの autoMemoryDirectory → main のディレクトリ名。
# WTCLOSE_VAULT があるときは autoMemoryDirectory からフォルダ名だけを使うので、
# テストが実物の vault に届くことはない。
resolve_places() {
  local common amd='' settings
  common="$("$git_cmd" -C "$work_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || common="$repo_root/.git"
  main_root="$(dirname "$common")"
  vault="${vault_override:-$default_vault}"
  settings="$main_root/.claude/settings.local.json"
  if [ -z "${WTCLOSE_PROJECT:-}" ] && [ -r "$settings" ] && have_jq; then
    amd="$(jq -r '.autoMemoryDirectory // empty | strings' "$settings" 2>/dev/null || true)"
  fi
  if [ -n "${WTCLOSE_PROJECT:-}" ]; then
    project="$WTCLOSE_PROJECT"
    mem_dir="$vault/AgentMemory/$project"
  elif [ -n "$amd" ]; then
    amd="$(norm_path "$amd")"
    project="$(basename "$amd")"
    if [ -n "$vault_override" ]; then
      mem_dir="$vault/AgentMemory/$project"
    else
      mem_dir="$amd"
      if [ "$(basename "$(dirname "$amd")")" = 'AgentMemory' ]; then
        vault="$(dirname "$(dirname "$amd")")"
      fi
    fi
  else
    project="$(basename "$main_root")"
    mem_dir="$vault/AgentMemory/$project"
  fi
  wb_dir="$vault/AgentMemory/workbench/$project"
}

own_repo=''

# owner/repo of this repository, from the origin URL (works without gh).
# 自分のリポジトリの owner/repo を origin の URL から求める(gh が無くても動く)。
resolve_own_repo() {
  local url re="[/:]($repo_re)\$"
  url="$("$git_cmd" -C "$repo_root" remote get-url origin 2>/dev/null)" || return 0
  url="${url%/}"
  url="${url%.git}"
  if [[ "$url" =~ $re ]]; then
    own_repo="${BASH_REMATCH[1]}"
  fi
}

# ---------------------------------------------------------------------------
# State files / 状態ファイル
# ---------------------------------------------------------------------------
own_state=''
stale_states=()   # "file<TAB>as_of<TAB>days"
unreadable_states=() # as_of cannot be parsed / as_of の値が読めない
locked_states=()     # the file itself cannot be read / ファイル自体を読めない

state_template() {
  local s
  printf -- '---\nname: state-<司令塔の名前>\ndescription: "<司令塔の名前> の状態(%s 時点)"\ntype: agent-memory\nkind: state\n%s: %s\n%s: %s\n---\n' \
    "$now" "$fm_session" "${session_id:-<セッション ID>}" "$fm_as_of" "$now"
  for s in "${state_sections[@]}"; do
    printf '\n## %s\n' "$s"
  done
}

# Find this commander's state file and classify the others (stale or root).
# この司令塔の状態ファイルを探し、ほかの状態ファイルを「古い」と「根」に分ける。
select_states() {
  local f sid asof days latest=''
  local -a own=() todays=()
  for f in "$mem_dir/$state_prefix"*.md; do
    [ -f "$f" ] || continue
    if [ ! -r "$f" ]; then
      # Cannot tell whose it is; reported by check_p1 or as a note.
      # 誰のものか分からない。check_p1 か注意で報告する。
      locked_states+=("$f")
      continue
    fi
    sid="$(fm_get "$f" "$fm_session")"
    asof="$(fm_get "$f" "$fm_as_of")"
    if [ -n "$session_id" ] && [ "$sid" = "$session_id" ]; then
      own+=("$f")
      continue
    fi
    if ! [[ "$asof" =~ $as_of_re ]]; then
      # Unreadable as_of: keep it as a root (do not forget) / 読めない時点: 根に残す
      unreadable_states+=("$f")
      continue
    fi
    if [ -z "$session_id" ] && [ "${asof%% *}" = "$today" ]; then
      todays+=("$f")
    fi
    days="$(days_since "${asof%% *}")"
    if [ -n "$days" ] && [ "$days" -gt "$dormant_days" ]; then
      stale_states+=("$f"$'\t'"$asof"$'\t'"$days")
    fi
  done
  if [ -z "$session_id" ] && [ "${#todays[@]}" -gt 0 ]; then
    # No session ID in the input: take the newest state file written today.
    # 入力に session_id が無い: 今日書かれた中でいちばん新しい状態ファイルを採る。
    for f in "${todays[@]}"; do
      if [ -z "$latest" ] || [[ "$(fm_get "$f" "$fm_as_of")" > "$(fm_get "$latest" "$fm_as_of")" ]]; then
        latest="$f"
      fi
    done
    own=("$latest")
    note "P1: session_id が分からないので、今日の ${fm_as_of} を持ついちばん新しい状態ファイル $(basename "$latest") を自分のものとみなした"
  fi
  if [ "${#own[@]}" -gt 1 ]; then
    fail P1 "同じ ${fm_session} の状態ファイルが ${#own[@]} 枚ある: $(printf '%s ' "${own[@]##*/}")" \
      "1 枚にまとめ、ほかのファイルの ${fm_session} を消す(状態ファイルは司令塔 1 体に 1 枚)"
  fi
  own_state="${own[0]:-}"
}

# P1: the state file exists and its as_of is today.
# P1: 状態ファイルがあり、as_of が今日である。
check_p1() {
  local asof f
  if [ -z "$own_state" ]; then
    for f in "${locked_states[@]}"; do
      fail P1 "状態ファイル ${f} を読めない(権限が無い)。このセッションの状態ファイルかどうかを確かめられない" \
        "自分の状態ファイルなら「chmod u+r ${f}」で読めるようにする"
    done
    fail P1 "このセッション(${fm_session}: ${session_id:-不明})の状態ファイルが ${mem_dir}/ に無い" \
      "${mem_dir}/${state_prefix}<司令塔の名前>.md を次の雛形で書く(既存の自分のファイルがあれば上書きし、${fm_session} を今のセッションに直す):"$'\n'"$(state_template)"
    return
  fi
  for f in "${locked_states[@]}"; do
    note "P1: 状態ファイル ${f} を読めないので、根として扱えなかった(chmod u+r で読めるようにする)"
  done
  asof="$(fm_get "$own_state" "$fm_as_of")"
  if ! [[ "$asof" =~ $as_of_re ]]; then
    fail P1 "$(basename "$own_state") の ${fm_as_of} が読めない(値: '${asof}')" \
      "frontmatter に「${fm_as_of}: ${now}」の形(YYYY-MM-DD HH:MM、ローカル時刻)で時点を書く"
  elif [ "${asof%% *}" != "$today" ]; then
    fail P1 "$(basename "$own_state") の ${fm_as_of} が ${asof} で、今日(${today})の時点ではない" \
      "状態ファイルを今の状態で上書きし、${fm_as_of} を「${now}」にする"
  fi
}

# P2: the state file is not longer than max_lines.
# P2: 状態ファイルが上限の行数を超えていない。
check_p2() {
  local lines
  [ -n "$own_state" ] || return 0
  lines="$(wc -l <"$own_state")"
  if [ "$lines" -gt "$max_lines" ]; then
    fail P2 "$(basename "$own_state") が ${lines} 行あり、上限の ${max_lines} 行を超えている" \
      "経過を消し、詳しい内容はセッションノートかメモリに移してリンクする(状態ファイルには今の状態と次の入口だけを書く)"
  fi
}

# P3: the "next entry" section exists and is not empty.
# P3: 「次の入口」の節があり、空でない。
check_p3() {
  local src="${own_state:-/dev/null}"
  if ! has_section "$src" "$sec_next"; then
    fail P3 "状態ファイルに「## ${sec_next}」の節が無い" \
      "「## ${sec_next}」の節を作り、次のセッションの司令塔が最初にすることを書く"
  elif ! section_body "$src" "$sec_next" | grep -qvE '^[[:space:]]*(<!--.*-->)?[[:space:]]*$'; then
    fail P3 "「## ${sec_next}」の節が空" \
      "次のセッションの司令塔が最初にすることを、節の中に 1 行以上書く"
  fi
}

# ---------------------------------------------------------------------------
# P4 and P8: open PRs and remaining worktrees / open の PR と残っている worktree
# ---------------------------------------------------------------------------
gh_ok=1
declare -A open_pr_branch=()
declare -A wt_branch=()

collect_real_state() {
  local line num branch path
  if ! list_open_prs >"$tmp_dir/open_prs"; then
    gh_ok=0
  fi
  while IFS=$'\t' read -r num branch; do
    [ -n "$num" ] || continue
    open_pr_branch[$num]="$branch"
  done <"$tmp_dir/open_prs"
  if ! list_worktrees >"$tmp_dir/worktrees" 2>"$tmp_dir/worktrees.err"; then
    note "P4: git worktree list が失敗したので、worktree は確かめなかった: $(head -n 1 "$tmp_dir/worktrees.err")"
    : >"$tmp_dir/worktrees"
  fi
  while IFS=$'\t' read -r path branch; do
    [ -n "$path" ] || continue
    line="$(norm_path "$path")"
    wt_branch[$line]="$branch"
  done <"$tmp_dir/worktrees"
}

# The only parser of the "remaining" section lines. Prints normalized records:
#   pr<TAB><number><TAB><kind><TAB><owner/repo or empty>
#   wt<TAB><path><TAB><kind> | p8<TAB><date> | p8bad<TAB><line> | bad<TAB><line>
# 「残っているもの」の行を読むのはこの関数だけ。正規化したレコードを出す。
parse_remaining() {
  local line tag rest
  local re_item='^[[:space:]]*[-*][[:space:]]+\[([^]]+)\][[:space:]]*(.*)$'
  local re_pr="^PR[[:space:]]*(${repo_re})?#([0-9]+)"
  # The backticks are literal: the path may be written as code. / バッククォートは文字どおり
  # shellcheck disable=SC2016
  local re_wt='^worktree[[:space:]]+`?([^[:space:]`]+)'
  local re_p8='^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+[0-9]{2}:[0-9]{2}'
  while IFS= read -r line; do
    [[ "$line" =~ $re_item ]] || continue
    tag="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    if [ "$tag" = "$pr_unverified_tag" ]; then
      if [[ "$rest" =~ $re_p8 ]]; then
        printf 'p8\t%s\n' "${BASH_REMATCH[1]}"
      else
        printf 'p8bad\t%s\n' "$line"
      fi
    elif ! is_reason_kind "$tag"; then
      if [[ "$rest" =~ $re_pr ]] || [[ "$rest" =~ $re_wt ]]; then
        printf 'bad\t%s\n' "$line"
      fi
    elif [[ "$rest" =~ $re_pr ]]; then
      printf 'pr\t%s\t%s\t%s\n' "${BASH_REMATCH[2]}" "$tag" "${BASH_REMATCH[1]}"
    elif [[ "$rest" =~ $re_wt ]]; then
      printf 'wt\t%s\t%s\n' "$(norm_path "${BASH_REMATCH[1]}")" "$tag"
    fi
  done < <(section_body "$1" "$sec_remaining")
}

check_p4_p8() {
  local src="${own_state:-/dev/null}" line kind key tag repo num path kinds_text p8_today=0
  local -A listed_pr=() listed_wt=()
  local -a bad_lines=() p8_bad=()
  kinds_text="$(printf '「%s」' "${reason_kinds[@]}")"

  while IFS=$'\t' read -r kind key tag repo; do
    case "$kind" in
      pr)
        if is_own_repo "$repo"; then
          listed_pr[$key]="$tag"
        else
          note "P4: 他のリポジトリ ${repo} の PR #${key} は、実物と照合していない"
        fi
        ;;
      wt) listed_wt[$key]="$tag" ;;
      p8) if [ "$key" = "$today" ]; then p8_today=1; else p8_bad+=("${key}"); fi ;;
      p8bad) p8_bad+=("$key") ;;
      bad) bad_lines+=("$key") ;;
    esac
  done < <(parse_remaining "$src")

  for line in "${bad_lines[@]}"; do
    fail P4 "「## ${sec_remaining}」の行の種類が 4 つの種類のどれでもない: ${line}" \
      "行頭の角括弧の中を ${kinds_text} のどれかと完全に一致させる"
  done

  # PRs (only when gh worked) / PR(gh が使えたときだけ)
  if [ "$gh_ok" -eq 1 ]; then
    for num in $(printf '%s\n' "${!open_pr_branch[@]}" | sort -n); do
      [ -z "${listed_pr[$num]:-}" ] || continue
      fail P4 "open の PR #${num}(${open_pr_branch[$num]})が「## ${sec_remaining}」に書いてない" \
        "「- [マージ待ち] PR #${num} <補足>」の形で書く。種類は ${kinds_text} から選ぶ(司令塔が作っていない PR は「別のセッションの管轄」)"
    done
    # Written but not open here: recorded, not blocked (it may be another repository's).
    # 書いてあるが自分のリポジトリでは open でない: 止めずに記録する(他のリポジトリのものかもしれない)。
    for num in $(printf '%s\n' "${!listed_pr[@]}" | sort -n); do
      [ -z "${open_pr_branch[$num]:-}" ] || continue
      note "P4: 「${sec_remaining}」の PR #${num} は、このリポジトリでは open ではない(終わったものなら消す。他のリポジトリのものなら PR owner/repo#${num} と修飾子を付ける)"
    done
  fi

  # Worktrees / worktree
  for path in $(printf '%s\n' "${!wt_branch[@]}" | sort); do
    [ -z "${listed_wt[$path]:-}" ] || continue
    fail P4 "残っている worktree ${path}(${wt_branch[$path]:-detached})が「## ${sec_remaining}」に書いてない" \
      "「- [worker 稼働中] worktree ${path} <補足>」の形で書く。種類は ${kinds_text} から選ぶ(司令塔が作っていない worktree は「別のセッションの管轄」)"
  done
  for path in $(printf '%s\n' "${!listed_wt[@]}" | sort); do
    [ -z "${wt_branch[$path]+set}" ] || continue
    note "P4: 「${sec_remaining}」の worktree ${path} は、このリポジトリの git worktree list に無い(消したものなら行を消す。他のリポジトリのものならそのままでよい)"
  done

  # P8: gh failed / gh が失敗した
  if [ "$gh_ok" -eq 0 ]; then
    if [ "$p8_today" -eq 1 ]; then
      note "P8: ${gh_error}。状態ファイルに未確認の記録があるので通した"
    else
      fail P8 "gh で PR の状態を確かめられなかった: ${gh_error}${p8_bad[0]:+(未確認の行はあるが、今日の日付ではない: ${p8_bad[0]})}" \
        "「## ${sec_remaining}」に「- [${pr_unverified_tag}] ${now} <補足>」と書く(日付は今日)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# P5: background waits must not remain (no exceptions).
# P5: 裏の待ち受けが残っていれば止める(例外を作らない)。
# ---------------------------------------------------------------------------
check_p5() {
  if [ "$mode" = 'check' ]; then
    note "P5: --check では確かめない(裏の待ち受けは Stop hook の入力にしか無い)"
    return
  fi
  if ! have_jq; then
    note "P5: jq が無いので、裏の待ち受けを確かめずに通した"
    return
  fi
  if ! printf '%s' "$input_json" | jq -e 'type == "object" and has("background_tasks")' >/dev/null 2>&1; then
    note "P5: hook 入力に background_tasks が無いので、未確認として通した"
    return
  fi
  local waits
  waits="$(printf '%s' "$input_json" | jq -r '
    def done_status: (.status // "running") | test("^(completed|failed|killed|stopped|done)$");
    ((.background_tasks // [])[] | select(done_status | not)
      | "裏タスク \(.id // "?")(\(.type // "?")): \(.description // "")\(if .command then " — " + .command else "" end)"),
    ((.session_crons // [])[]
      | "予約 \(.id // "?")(\(.schedule // "?")): \(.prompt // "")")' 2>/dev/null)" || {
    note "P5: hook 入力の background_tasks を読めなかったので、未確認として通した"
    return
  }
  if [ -n "$waits" ]; then
    fail P5 "裏の待ち受けが残っている。待ち受けは新しいセッションに引き継がれない:"$'\n'"$(printf '%s\n' "$waits" | sed 's/^/      - /')" \
      "TaskStop などで裏の待ち受けをすべて止め、待っていたものを状態ファイルの「稼働中の worker」に書く"
  fi
}

# ---------------------------------------------------------------------------
# P6 and P7: the reachability list / 到達の一覧
# ---------------------------------------------------------------------------
candidate_count=0

# The awk program resolves links from the roots, closes them over the
# workbench, and classifies every work product. One process for all files.
# awk は、根からのリンクを解決し、作業記憶の中で閉包を取り、作業物を分類する。
# 全部のファイルを 1 つのプロセスで扱う。
write_reach_awk() {
  cat >"$tmp_dir/reach.awk" <<'AWK'
# Days since 0000-03-01 for a YYYY-MM-DD string, -1 when invalid (POSIX awk).
# YYYY-MM-DD を通し番号の日に変える。不正なら -1(POSIX awk で動く)。
function civil(s,   y, m, d, era, yoe, doy) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m < 1 || m > 12 || d < 1 || d > 31) return -1
  if (m <= 2) y--
  era = int(y / 400); yoe = y - era * 400
  doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
}
function normpath(p,   n, parts, i, k, st, out) {
  n = split(p, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (k > 0) k--; continue }
    st[++k] = parts[i]
  }
  out = ""
  for (i = 1; i <= k; i++) out = out "/" st[i]
  return out == "" ? "/" : out
}
function hit(rel) {
  if (cur_kind == "R") reached[rel] = 1
  else if (rel != cur_rel) { ne++; esrc[ne] = cur_rel; edst[ne] = rel }
}
function try_rel(rel,   i) {
  if (rel in isfile) { hit(rel); return 1 }
  if ((rel ".md") in isfile) { hit(rel ".md"); return 1 }
  i = index(rel, ".md")
  if (i > 0 && (substr(rel, 1, i + 2) in isfile)) { hit(substr(rel, 1, i + 2)); return 1 }
  return 0
}
function try_abs(p) {
  p = normpath(p)
  if (index(p, wb "/") == 1) return try_rel(substr(p, length(wb) + 2))
  return 0
}
function try_wiki(t,   i, b, n, arr, j) {
  sub(/\|.*/, "", t); sub(/#.*/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
  if (t == "") return
  i = index(t, marker_short)
  if (i > 0) { try_rel(substr(t, i + length(marker_short))); return }
  b = t; sub(/.*\//, "", b); sub(/\.md$/, "", b)
  if (b in bykey) { n = split(bykey[b], arr, SUBSEP); for (j = 1; j <= n; j++) hit(arr[j]) }
  if (t in byname) { n = split(byname[t], arr, SUBSEP); for (j = 1; j <= n; j++) hit(arr[j]) }
}
function try_mdlink(t, dir) {
  if (t ~ /^<.*>$/) t = substr(t, 2, length(t) - 2)
  sub(/[ \t]+"[^"]*"$/, "", t)
  if (t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
  sub(/#.*/, "", t); gsub(/%20/, " ", t)
  if (t == "") return
  if (substr(t, 1, 2) == "~/") t = home substr(t, 2)
  if (substr(t, 1, 1) == "/") { if (!try_abs(t)) try_abs(vault t); return }
  try_abs(dir "/" t)
}
function scan(line, dir,   s, i, rest, tok) {
  s = line
  while (match(s, /\[\[[^]]+\]\]/)) { try_wiki(substr(s, RSTART + 2, RLENGTH - 4)); s = substr(s, RSTART + RLENGTH) }
  s = line
  while (match(s, /\]\([^)]+\)/)) { try_mdlink(substr(s, RSTART + 2, RLENGTH - 3), dir); s = substr(s, RSTART + RLENGTH) }
  s = line
  while ((i = index(s, marker)) > 0) {
    rest = substr(s, i + length(marker))
    if (match(rest, /^[^][ \t"'`<>|(){}]+/)) {
      tok = substr(rest, 1, RLENGTH); sub(/[.,;:!?]+$/, "", tok)
      try_rel(tok)
    }
    s = rest
  }
}
function add_key(arr, k, rel) { arr[k] = (k in arr) ? arr[k] SUBSEP rel : rel }
BEGIN {
  FS = "\t"
  marker = "AgentMemory/workbench/" proj "/"
  marker_short = "workbench/" proj "/"
  while ((getline line < files_list) > 0) {
    isfile[line] = 1; nf_++; order[nf_] = line
    b = line; sub(/.*\//, "", b); sub(/\.md$/, "", b); add_key(bykey, b, line)
  }
  while ((getline line < meta_list) > 0) {
    split(line, f, "\037")
    if (f[2] != "") add_key(byname, f[2], f[1])
    created[f[1]] = f[4]; missing[f[1]] = f[5]
  }
  while ((getline line < prev_list) > 0) { split(line, f, "\t"); prev[f[1]] = f[2] }
  # From match_units: "rel<TAB>held|note<TAB>reason" / match_units の結果
  while ((getline line < held_list) > 0) {
    split(line, f, "\t")
    if (f[2] == "held") held[f[1]] = f[3]; else unote[f[1]] = f[3]
  }
  # Sources: "R<TAB>abs path" (roots) or "W<TAB>rel path" (workbench md)
  while ((getline src < sources_list) > 0) {
    split(src, f, "\t"); cur_kind = f[1]
    if (cur_kind == "R") { path = f[2]; cur_rel = "" } else { cur_rel = f[2]; path = wb "/" cur_rel }
    dir = path; sub(/\/[^\/]*$/, "", dir)
    while ((getline line < path) > 0) scan(line, dir)
    close(path)
  }
  # Closure over the workbench / 作業記憶の中で閉包を取る
  do { changed = 0; for (e = 1; e <= ne; e++) if ((esrc[e] in reached) && !(edst[e] in reached)) { reached[edst[e]] = 1; changed = 1 } } while (changed)
  # Attachments linked from a held md are held too / held の md からリンクされた付属物も held
  do { changed = 0; for (e = 1; e <= ne; e++) if ((esrc[e] in held) && !(edst[e] in held)) { held[edst[e]] = held[esrc[e]]; changed = 1 } } while (changed)
  tday = civil(today)
  for (k = 1; k <= nf_; k++) {
    rel = order[k]; note_ = ""
    if (rel in reached) { last = today; state = "reached"; days = 0 }
    else {
      if (civil(prev[rel]) >= 0) last = prev[rel]
      else if (civil(created[rel]) >= 0) { last = created[rel]; note_ = "未到達(created から数える)" }
      else { last = today; note_ = "未到達(初めて見た日から数える)" }
      days = tday - civil(last)
      if (rel in held) { state = "held"; note_ = held[rel] (note_ == "" ? "" : "、" note_) }
      else if (days > dormant) state = "candidate"
      else state = "dormant"
    }
    if (rel in unote) note_ = note_ (note_ == "" ? "" : "、") unote[rel]
    if (missing[rel] == "!unreadable") note_ = note_ (note_ == "" ? "" : "、") "読めないので frontmatter を確かめていない"
    else if (missing[rel] != "") note_ = note_ (note_ == "" ? "" : "、") "frontmatter に無い: " missing[rel]
    print rel "\t" last "\t" state "\t" days "\t" note_
  }
}
AWK
}

# Print "rel, name, unit, created, missing keys" of workbench md files, separated
# by \037: unlike a tab it is not IFS whitespace, so empty fields survive read.
# 作業記憶の md の frontmatter を「相対パス・name・unit・created・欠けたキー」で出す。
# 区切りの \037 はタブと違って IFS の空白に当たらないので、空の欄が read でつぶれない。
workbench_meta() {
  awk -v base="$wb_dir" -v q="'" '
    function val(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+$/, "", s)
      if (substr(s, 1, 1) == "\"" || substr(s, 1, 1) == q) s = substr(s, 2, length(s) - 2)
      return s }
    /\.md$/ {
      rel = $0; f = base "/" rel; n = 0; infm = 0; r = 0
      split("", v)
      while ((r = (getline line < f)) > 0) {
        n++
        if (n == 1) { if (line != "---") break; infm = 1; continue }
        if (line == "---") break
        k = line; sub(/:.*/, "", k); if (!(k in v)) v[k] = val(line)
      }
      close(f)
      # An unreadable file is marked, not fatal / 読めないファイルは印を付けるだけにする
      if (r < 0) { print rel "\037\037\037\037!unreadable"; next }
      miss = ""
      split("type kind unit created", req, " ")
      for (i = 1; i <= 4; i++) if (!(req[i] in v) || v[req[i]] == "") miss = miss (miss == "" ? "" : ", ") req[i]
      print rel "\037" v["name"] "\037" v["unit"] "\037" v["created"] "\037" miss
    }' "$tmp_dir/files"
}

# The only matcher of unit against real state. Reads the meta list and prints
# "rel<TAB>held<TAB>reason" (excluded from candidates) or "rel<TAB>note<TAB>text".
#   "#663" | "PR #663" | "owner/repo#663" -> a PR; "feat/x" | "owner/repo@feat/x" -> a branch
# unit と実物を照合するのはこの関数だけ。候補から外すもの(held)と備考(note)を出す。
match_units() {
  local rel unit repo kind key
  local -A branches=()
  local re_qpr="^(${repo_re})#([0-9]+)\$" re_qbr="^(${repo_re})@(.+)\$" re_pr='^(PR[[:space:]]*)?#?([0-9]+)$'
  for key in "${!open_pr_branch[@]}"; do branches[${open_pr_branch[$key]}]="open の PR #${key}"; done
  for key in "${!wt_branch[@]}"; do
    [ -z "${wt_branch[$key]}" ] || branches[${wt_branch[$key]}]="残っている worktree ${key}"
  done
  while IFS=$'\037' read -r rel _ unit _ _; do
    [ -n "$unit" ] || continue
    repo=''
    if [[ "$unit" =~ $re_qpr ]]; then
      repo="${BASH_REMATCH[1]}"; kind='pr'; key="${BASH_REMATCH[2]}"
    elif [[ "$unit" =~ $re_qbr ]]; then
      repo="${BASH_REMATCH[1]}"; kind='branch'; key="${BASH_REMATCH[2]}"
    elif [[ "$unit" =~ $re_pr ]]; then
      kind='pr'; key="${BASH_REMATCH[2]}"
    else
      kind='branch'; key="$unit"
    fi
    if ! is_own_repo "$repo"; then
      printf '%s\tnote\t他のリポジトリ %s の単位で、open かどうかは確かめていない\n' "$rel" "$repo"
    elif [ "$kind" = 'pr' ] && [ "$gh_ok" -eq 0 ]; then
      printf '%s\theld\tPR #%s の状態は未確認\n' "$rel" "$key"
    elif [ "$kind" = 'pr' ] && [ -n "${open_pr_branch[$key]:-}" ]; then
      printf '%s\theld\topen の PR #%s\n' "$rel" "$key"
    elif [ "$kind" = 'branch' ] && [ -n "${branches[$key]:-}" ]; then
      printf '%s\theld\t%s\n' "$rel" "${branches[$key]}"
    fi
  done <"$tmp_dir/meta"
}

# find_readable <dir> <label> <out> [tests...]: write the paths relative to dir,
# sorted. Places find cannot read are skipped and noted, never fatal.
# Searching from "." keeps "! -path '*/.*'" from matching a dot directory above dir.
# dir からの相対パスを並べて out に書く。find が読めない場所は飛ばして注意に残し、
# 失敗にはしない。「.」から探すので、dir より上の . で始まるディレクトリに
# 「! -path '*/.*'」が当たらない。
find_readable() {
  local dir="$1" label="$2" out="$3"
  shift 3
  (cd "$dir" && find . "$@") 2>"$tmp_dir/find.err" | sed 's|^\./||' | LC_ALL=C sort >"$out" || true
  if [ -s "$tmp_dir/find.err" ]; then
    note "${label}の中の読めない場所を飛ばした: $(head -n 3 "$tmp_dir/find.err" | tr '\n' ' ')"
  fi
}

# Print "rel<TAB>last_reached" from the previous list / 前回の一覧から日付を読み戻す
previous_dates() {
  [ -f "$wb_dir/$index_name" ] || return 0
  if [ ! -r "$wb_dir/$index_name" ]; then
    note "P6: 前回の一覧 ${wb_dir}/${index_name} を読めないので、最後に辿れた日を引き継がなかった"
    return 0
  fi
  awk '
    /^## / { insec = ($0 == "## 一覧"); next }
    insec && /^\| `/ {
      n = split($0, c, "|"); p = c[2]; d = c[3]
      gsub(/^[ \t`]+|[ \t`]+$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", d)
      print p "\t" d
    }' "$wb_dir/$index_name"
}

build_reachability() {
  local f rel stale_rows='' row state days last rnote cand_rows='' all_rows='' created_idx
  local -A is_stale=()
  if ! mkdir -p "$wb_dir" 2>"$tmp_dir/mkdir.err"; then
    fail P7 "作業記憶 ${wb_dir} を作れない: $(head -n 1 "$tmp_dir/mkdir.err")" \
      "ディレクトリの権限と vault の場所を確かめる。直せなければユーザーに報告する"
    fail P6 "作業記憶が無いので、忘れる候補の一覧を出せない" "P7 を直す"
    return
  fi

  find_readable "$wb_dir" 'P7: 作業記憶' "$tmp_dir/files" \
    -type f ! -name "$index_name" ! -name "$log_name" ! -path '*/.*'
  workbench_meta >"$tmp_dir/meta"
  previous_dates >"$tmp_dir/prev"

  match_units >"$tmp_dir/held"

  # Roots: state files (except stale ones), memory, session notes
  # 根: 状態ファイル(古いものを除く)・記憶・セッションノート
  for row in "${stale_states[@]}"; do
    is_stale[${row%%$'\t'*}]=1
  done
  : >"$tmp_dir/mem_files"
  : >"$tmp_dir/note_files"
  if [ -d "$mem_dir" ]; then
    find_readable "$mem_dir" 'P7: 記憶' "$tmp_dir/mem_files" -type f -name '*.md' ! -path '*/.*'
  fi
  if [ -d "$vault/$notes_rel" ]; then
    find_readable "$vault/$notes_rel" 'P7: セッションノート' "$tmp_dir/note_files" -type f -name '*.md' ! -path '*/.*'
  fi
  {
    while IFS= read -r f; do
      [ -n "${is_stale[$mem_dir/$f]:-}" ] || printf 'R\t%s/%s\n' "$mem_dir" "$f"
    done <"$tmp_dir/mem_files"
    while IFS= read -r f; do
      printf 'R\t%s/%s/%s\n' "$vault" "$notes_rel" "$f"
    done <"$tmp_dir/note_files"
    while IFS= read -r f; do
      [[ "$f" != *.md ]] || printf 'W\t%s\n' "$f"
    done <"$tmp_dir/files"
  } >"$tmp_dir/sources"

  write_reach_awk
  if ! awk -v wb="$wb_dir" -v proj="$project" -v home="$HOME" -v vault="$vault" \
    -v today="$today" -v dormant="$dormant_days" \
    -v files_list="$tmp_dir/files" -v meta_list="$tmp_dir/meta" -v prev_list="$tmp_dir/prev" \
    -v held_list="$tmp_dir/held" -v sources_list="$tmp_dir/sources" \
    -f "$tmp_dir/reach.awk" >"$tmp_dir/rows" 2>"$tmp_dir/awk.err"; then
    fail P7 "リンクを辿れなかった: $(head -n 1 "$tmp_dir/awk.err")" \
      "検問スクリプトの不具合の可能性がある。ユーザーに報告する"
    fail P6 "到達を計算できなかったので、忘れる候補の一覧を出せない" "P7 を直す"
    return
  fi

  local shown
  while IFS=$'\t' read -r rel last state days rnote; do
    [ -n "$rel" ] || continue
    # No subshell per row: this loop runs for every work product / 行ごとにサブシェルを起こさない
    shown="$state"
    [ "$state" = reached ] || shown+=" ${days}d"
    row="| \`${rel}\` | ${last} | ${shown} | ${rnote} |"
    all_rows+="$row"$'\n'
    if [ "$state" = candidate ]; then
      candidate_count=$((candidate_count + 1))
      cand_rows+="| \`${rel}\` | ${last} | ${days} | ${rnote} |"$'\n'
    fi
  done <"$tmp_dir/rows"
  for row in "${stale_states[@]}"; do
    IFS=$'\t' read -r f last days <<<"$row"
    stale_rows+="| \`${f}\` | ${last} | ${days} |"$'\n'
  done

  created_idx=''
  if [ -r "$wb_dir/$index_name" ]; then
    created_idx="$(fm_get "$wb_dir/$index_name" created)"
  fi
  # Write to a temporary file, then rename (never leaves a half-written list).
  # 一時ファイルに書いてから名前を変える(書きかけの一覧を残さない)。
  if ! {
    printf -- '---\ntype: agent-workbench\nkind: index\nunit: wtclose\ncreated: %s\nupdated: %s\n---\n\n' "${created_idx:-$today}" "$now"
    printf '# 作業記憶の到達一覧(%s)\n\n' "$project"
    printf '検問スクリプト(wtclose の close_gate.sh)が、締めのたびにこの一覧を上書きする。手で書き換えない。\n'
    printf '「最後に辿れた日」は、状態ファイル・記憶・セッションノートからリンクを最後に辿れた日である。辿れなくなって %s 日を過ぎた作業物を、忘れる候補として出す。\n' "$dormant_days"
    printf '検問は作業物を消さない。候補を消すのは、ユーザーが OK を出した後に司令塔が行う。\n\n'
    printf '止めた回数と理由の記録: [%s](%s)\n\n' "$log_name" "$log_name"
    printf '## 忘れる候補\n\n'
    if [ -n "$cand_rows" ]; then
      printf '| path | last_reached | days | note |\n|---|---|---|---|\n%s\n' "$cand_rows"
    else
      printf 'なし\n\n'
    fi
    printf '## 古い状態ファイル\n\n'
    if [ -n "$stale_rows" ]; then
      printf '%s が %s 日より前の状態ファイルは、根として扱わない。\n\n| path | %s | days |\n|---|---|---|\n%s\n' \
        "$fm_as_of" "$dormant_days" "$fm_as_of" "$stale_rows"
    else
      printf 'なし\n\n'
    fi
    if [ "${#unreadable_states[@]}" -gt 0 ]; then
      printf '## 備考\n\n'
      for f in "${unreadable_states[@]}"; do
        printf -- "- \`%s\` は %s が読めないので、忘れない側に倒して根として扱った\n" "$f" "$fm_as_of"
      done
      printf '\n'
    fi
    printf '## 一覧\n\n| path | last_reached | state | note |\n|---|---|---|---|\n%s' "$all_rows"
  } >"$wb_dir/.${index_name}.tmp" 2>"$tmp_dir/write.err" \
    || ! mv -f "$wb_dir/.${index_name}.tmp" "$wb_dir/$index_name" 2>>"$tmp_dir/write.err"; then
    fail P7 "一覧 ${wb_dir}/${index_name} を書けなかった: $(head -n 1 "$tmp_dir/write.err")" \
      "ディレクトリの権限と空き容量を確かめる。直せなければユーザーに報告する"
    fail P6 "一覧を書けなかったので、忘れる候補を出せない" "P7 を直す"
    return
  fi
  if [ "$candidate_count" -gt 0 ] || [ "${#stale_states[@]}" -gt 0 ]; then
    note "P6: 忘れる候補 ${candidate_count} 件・古い状態ファイル ${#stale_states[@]} 件を一覧に出した(${wb_dir}/${index_name})。ユーザーに見せ、OK をもらってから消す"
  fi
}

# ---------------------------------------------------------------------------
# Record / 記録
# ---------------------------------------------------------------------------
elapsed_ms() {
  echo $((($(date +%s%N) - started_ns) / 1000000))
}

unique_ids() {
  local id out=''
  for id in "${fail_ids[@]}"; do
    case ",$out," in *",$id,"*) ;; *) out+="${out:+,}$id" ;; esac
  done
  printf '%s' "$out"
}

# Append one line per run to _gate_log.jsonl (never blocks on failure).
# 1 回の判定を _gate_log.jsonl に 1 行追記する(失敗しても止めない)。
write_log() {
  [ -d "$wb_dir" ] || return 0
  local result='pass' ids msg
  local -a reasons=() idlist=()
  [ "${#fail_ids[@]}" -eq 0 ] || result='block'
  for msg in "${fail_msgs[@]}"; do
    reasons+=("${msg%%$'\n'*}")
  done
  ids="$(unique_ids)"
  [ -z "$ids" ] || IFS=',' read -r -a idlist <<<"$ids"
  printf '{"ts":%s,"project":%s,"session_id":%s,"mode":%s,"result":%s,"failed":%s,"reasons":%s,"notes":%s,"stop_hook_active":%s,"candidates":%d,"elapsed_ms":%d}\n' \
    "$(json_str "$ts")" "$(json_str "$project")" "$(json_str "$session_id")" "$(json_str "$mode")" \
    "$(json_str "$result")" "$(json_array "${idlist[@]}")" "$(json_array "${reasons[@]}")" \
    "$(json_array "${notes[@]}")" "$stop_hook_active" "$candidate_count" "$(elapsed_ms)" \
    >>"$wb_dir/$log_name" 2>/dev/null || note "記録 ${wb_dir}/${log_name} に書けなかった"
}

# Record an unexpected failure (called from on_exit; only when the workbench exists).
# 想定外の失敗を記録する(on_exit から呼ぶ。作業記憶があるときだけ書く)。
# shellcheck disable=SC2329 # invoked from on_exit / on_exit から呼ばれる
write_error_log() {
  if [ -z "$wb_dir" ] || [ ! -d "$wb_dir" ]; then return 0; fi
  printf '{"ts":%s,"project":%s,"session_id":%s,"mode":%s,"result":"error","failed":[],"reasons":%s,"notes":%s,"stop_hook_active":%s,"candidates":0,"elapsed_ms":%d}\n' \
    "$(json_str "${ts:-}")" "$(json_str "${project:-}")" "$(json_str "${session_id:-}")" "$(json_str "$mode")" \
    "$(json_array "$1")" "$(json_array "${notes[@]}")" "${stop_hook_active:-false}" "$(elapsed_ms)" \
    >>"$wb_dir/$log_name"
}

# ---------------------------------------------------------------------------
# Output / 出力
# ---------------------------------------------------------------------------
# Pass without checking, telling the user why (e.g. no vault on this machine).
# 検問を省いて通し、理由をユーザーに知らせる(この機械に vault が無いときなど)。
skip_gate() {
  local msg="wtclose の検問を省いた: $1"
  if [ "$mode" = 'where' ]; then
    printf '%s\n' "$msg" >&2
    finish 3
  elif [ "$mode" = 'check' ]; then
    printf '%s\n' "$msg"
  else
    printf '{"systemMessage":%s}\n' "$(json_str "$msg")"
  fi
  finish 0
}

# Print the result and exit: 2 when any condition is unmet, 0 otherwise.
# 結果を出して終える。そろっていない条件が 1 つでもあれば 2、無ければ 0。
emit_result() {
  local hint="bash ~/.claude/skills/wtclose/close_gate.sh --check --session ${session_id:-<セッション ID>}"
  local notes_text=''
  if [ "${#notes[@]}" -gt 0 ]; then
    notes_text="$(printf '  - %s\n' "${notes[@]}")"
  fi
  if [ "${#fail_ids[@]}" -gt 0 ]; then
    {
      printf 'wtclose の検問: 締めの条件(%s)がそろっていない。下の %d 件を全部直すまで、ターンを終えられない。\n' "$(unique_ids)" "${#fail_ids[@]}"
      printf '%s\n' "${fail_msgs[@]}"
      [ -z "$notes_text" ] || printf '記録した注意:\n%s\n' "$notes_text"
      printf 'ターンを終える前に試すには: %s\n' "$hint"
    } >"$tmp_dir/report"
    if [ "$mode" = 'check' ]; then
      cat "$tmp_dir/report"
    else
      cat "$tmp_dir/report" >&2
    fi
    finish 2
  fi
  local msg="wtclose の検問を通過した。/compact で続けず、新しいセッションで続けて。"
  [ -z "$notes_text" ] || msg+=$'\n'"記録した注意:"$'\n'"$notes_text"
  if [ "$mode" = 'check' ]; then
    printf '%s\n' "$msg"
  else
    printf '{"systemMessage":%s}\n' "$(json_str "$msg")"
  fi
  finish 0
}

# ---------------------------------------------------------------------------
# Main / 本体
# ---------------------------------------------------------------------------
repo_root="$("$git_cmd" -C "$work_dir" rev-parse --show-toplevel 2>/dev/null)" \
  || skip_gate "$work_dir は git リポジトリの中ではない"
resolve_places
[ -d "$vault/AgentMemory" ] || skip_gate "vault($vault/AgentMemory)が無い"
resolve_own_repo

if [ "$mode" = 'where' ]; then
  case "$where_key" in
    '') printf 'project=%s\nmemory_dir=%s\nworkbench_dir=%s\n' "$project" "$mem_dir" "$wb_dir" ;;
    project) printf '%s\n' "$project" ;;
    memory_dir) printf '%s\n' "$mem_dir" ;;
    workbench_dir) printf '%s\n' "$wb_dir" ;;
    *) echo "close_gate.sh: unknown key for --where: $where_key" >&2; finish 64 ;;
  esac
  finish 0
fi

select_states
check_p1
check_p2
check_p3
collect_real_state
check_p4_p8
check_p5
build_reachability
# Forced failure for the tests of the safety net / 安全網のテストのための失敗
[ -z "${WTCLOSE_FAULT:-}" ] || (exit "$WTCLOSE_FAULT")
write_log
emit_result
