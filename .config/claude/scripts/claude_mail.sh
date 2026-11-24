#!/usr/bin/env bash
# Ring a bell for a /wt commander on another machine / 別の機械の司令塔に呼び鈴を置く
#
# The body of a message is a markdown file in the vault's workbench (carried by
# Obsidian Sync). This script carries only the bell, "a body has arrived", as a
# one-line value in "atuin kv": who rang, when, which document to read, and a
# one-line subject. The SessionStart hook and the close gate of wtclose read it.
# 連絡の本文は、vault の作業記憶に置いた md である(Obsidian Sync が運ぶ)。この
# スクリプトは「本文が届いた」という知らせ(呼び鈴)だけを、atuin kv の 1 行の値
# として運ぶ。値は、差出人・置いた時刻・読んでほしい文書・1 行の用件を持つ。
# SessionStart の hook と、wtclose の検問が呼び鈴を読む。
#
# An address is commander-<project>, where <project> is what
# "close_gate.sh --where project" prints. It is not the herdr agent name: a
# commander named commander-<project>-2 still reads commander-<project>.
# 宛先は commander-<project> である。<project> は close_gate.sh --where project
# が出す名前で、herdr の agent 名ではない。commander-<project>-2 を名乗る司令塔も、
# 読むのは commander-<project> である。
#
# Usage / 使い方:
#   claude_mail.sh send <address> <document> <subject>
#     Put a bell, then sync. <document> must be an existing .md file inside
#     AgentMemory/workbench/ of the vault.
#     呼び鈴を置いて同期する。<document> は、vault の AgentMemory/workbench/ の
#     中に実在する md に限る。
#   claude_mail.sh list [--to <address>]
#     Sync first, then print the bells. Without --to, the address is this
#     place's own commander-<project>, and nothing happens in a linked worktree
#     (workers must not see the commander's bells) or for a project that has no
#     AgentMemory/<project> in the vault (nobody can ring there).
#     先に同期してから、呼び鈴を出す。--to が無いときの宛先は、この場所の
#     commander-<project> である。linked worktree では何もしない(worker に
#     司令塔あての呼び鈴を見せないため)。vault に AgentMemory/<project> が無い
#     プロジェクトでも何もしない(誰もそこへ呼び鈴を置けないため)。
#   claude_mail.sh ack <address> <key>
#     Delete one bell, then sync. The document stays in the vault.
#     呼び鈴を 1 件消して同期する。文書は vault に残る。
#
# Output / 出力:
#   stdout: send: "sent <address> <key>" / ack: "acked <address> <key>"
#           list: one line per bell, oldest first; nothing when there is none
#                 呼び鈴 1 件を 1 行で、古い順に出す。無ければ何も出さない
#   stderr: one line per problem, starting with "claude_mail.sh: "
#           問題 1 件を 1 行で出す(行頭は「claude_mail.sh: 」)
#
# Exit codes / 終了コード:
#   0  done. list returns 0 for every problem below except 64, so that the hook
#      and the gate never stop; it is silent when --where finds no place.
#      できた。list は 64 を除くどの問題でも 0 で終わり、hook と検問を止めない。
#      --where が置き場を求められない場所では、何も出さない。
#   1  refused; nothing was changed / 拒否した。何も変えていない
#   2  environment problem (no places, no atuin, no timeout, bad tunable);
#      nothing was changed
#      環境の問題(置き場を求められない・atuin が無い・timeout が無い・閾値が不正)。
#      何も変えていない
#   3  atuin kv failed; nothing was changed, or unknown when it timed out
#      atuin kv が失敗した。何も変えていない(時間切れのときは分からない)
#   4  this machine was changed, but the sync failed; the next atuin sync
#      carries it / この機械では変えたが、同期に失敗した。次の atuin sync で届く
#   5  unexpected failure / 想定外の失敗
#   64 wrong usage / 使い方の誤り
#
# Tunables (seconds) / 閾値(秒):
#   CLAUDE_MAIL_SYNC_TIMEOUT  : one "atuin sync" (list 10, send and ack 30)
#   CLAUDE_MAIL_KV_TIMEOUT    : one "atuin kv" (list 2, send and ack 5)
#   CLAUDE_MAIL_TOTAL_TIMEOUT : the whole run (list 15, send and ack 45)
set -euo pipefail

# Bytes, not characters: the checks below must not depend on the locale.
# 文字ではなくバイトで数える。下の検査を、ロケールに左右されないようにする。
LC_ALL=C

# ---------------------------------------------------------------------------
# Format contract / 書式の契約
# Namespace: mail-<address>. Key: <YYYYMMDD-HHMMSS>-<sender>-<random>, in UTC,
# so that the keys of machines in different time zones sort by time.
# Value: "v1", sender, time, vault-relative path and subject, joined by tabs.
# The subject comes last and never contains a tab when written by send, and a
# reader takes everything after the fourth tab as the subject.
# 名前空間は mail-<宛先>、キーは <YYYYMMDD-HHMMSS>-<差出人>-<乱数>。キーの時刻は
# UTC で書く。タイムゾーンの違う機械のキーも、時刻の順に並ぶようにするためである。
# 値は「v1」・差出人・時刻・vault の中の相対パス・用件を、タブでつないだ 1 行。
# 用件は最後に置く。send が書く用件にタブは入らず、読む側は 4 つ目のタブより
# 後ろの全部を用件として読む。
# ---------------------------------------------------------------------------
readonly ns_prefix='mail-'
readonly addr_prefix='commander-'
readonly addr_re='^commander-[A-Za-z0-9][A-Za-z0-9._-]*$'
readonly key_re='^[0-9]{8}-[0-9]{6}-[A-Za-z0-9][A-Za-z0-9._-]*$'
readonly time_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$'
readonly wb_rel='AgentMemory/workbench'
readonly subject_max_bytes=600 # about 200 Japanese characters / 日本語で約 200 字
readonly addr_hint='宛先は herdr の名前ではなく、commander-<--where project> で書く(<--where project> は、宛先の司令塔が動く場所で close_gate.sh --where project が出す名前)'
# Exit 0 is not enough to call a sync done: require this line as well, so that
# a sync that did nothing is reported instead of looking like "no bells".
# 終了コード 0 だけでは同期できたとみなさず、この行も求める。何もしなかった同期が
# 「呼び鈴なし」に見えるのを避けるためである。
readonly sync_done='Sync complete!'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/../skills/wtclose/close_gate.sh"

# ---------------------------------------------------------------------------
# Leaving / 終わり方
# Every intended exit goes through finish. Anything else is an unexpected
# failure, and list must not turn it into a non-zero exit.
# 意図した終わり方は、すべて finish を通る。それ以外は想定外の失敗で、list では
# それも 0 にする。
# ---------------------------------------------------------------------------
cmd="${1:-}"
clean_exit=''
err_file=''

finish() {
  clean_exit=1
  exit "$1"
}

# shellcheck disable=SC2329 # invoked by the EXIT trap / EXIT の trap から呼ばれる
on_exit() {
  local rc=$?
  [ -z "$err_file" ] || rm -f "$err_file"
  [ -z "$clean_exit" ] || return 0
  printf 'claude_mail.sh: 想定外の失敗で終わった(終了コード %s)\n' "$rc" >&2
  [ "$cmd" != list ] || exit 0
  exit 5
}
trap on_exit EXIT

warn() { printf 'claude_mail.sh: %s\n' "$1" >&2; }

# stop <exit code> <reason>: report and leave; list always leaves with 0.
# 理由を 1 行で出して終える。list はいつも 0 で終わる。
stop() {
  warn "$2"
  [ "$cmd" != list ] || finish 0
  finish "$1"
}

usage() {
  warn "$1(使い方: claude_mail.sh send <宛先> <文書のパス> <用件> | list [--to <宛先>] | ack <宛先> <キー>)"
  finish 64
}

# ---------------------------------------------------------------------------
# Small helpers / 小さな道具
# ---------------------------------------------------------------------------
has_cntrl() { [[ "$1" == *[[:cntrl:]]* ]]; }

# Control characters become spaces, so that one bell stays one line.
# 制御文字を空白にして、呼び鈴 1 件を 1 行に保つ。
printable() { printf '%s' "${1//[[:cntrl:]]/ }"; }

# The first non-blank line, for a one-line reason / 理由を 1 行にするための、最初の空でない行
first_line() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] || { printable "$line"; return 0; }
  done <<<"$1"
}

# bounded <seconds> <command>...: run within the step limit and within what is
# left of the whole run. Returns 124 when there is no time left.
# その段の上限と、全体の残り時間の、短いほうで区切って走らせる。残り時間が無ければ
# 124 を返す。
bounded() {
  local limit="$1" left
  shift
  left=$((total_limit - SECONDS))
  [ "$left" -gt 0 ] || return 124
  [ "$limit" -le "$left" ] || limit="$left"
  timeout -k 1 "$limit" "$@" </dev/null
}

timed_out() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; }

# why <exit code> <output>: the tail of a one-line reason / 理由の後半
why() {
  local line
  if timed_out "$1"; then
    printf '時間切れになった'
    return 0
  fi
  line="$(first_line "$2")"
  printf '失敗した(終了コード %s%s)' "$1" "${line:+: $line}"
}

read_limit() {
  local name="$1" value="${!1:-$2}"
  [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] || stop 2 "$name が 1〜9999 の整数ではない: $(printable "$value")"
  limit_value="$value"
}

limit_value=''
sync_limit=''
kv_limit=''
total_limit=''
set_limits() {
  read_limit CLAUDE_MAIL_SYNC_TIMEOUT "$1"; sync_limit="$limit_value"
  read_limit CLAUDE_MAIL_KV_TIMEOUT "$2"; kv_limit="$limit_value"
  read_limit CLAUDE_MAIL_TOTAL_TIMEOUT "$3"; total_limit="$limit_value"
  SECONDS=0
  command -v timeout >/dev/null 2>&1 || stop 2 'timeout コマンドが無いので、時間を区切れない'
  err_file="$(mktemp)" || stop 2 '一時ファイルを作れない'
}

need_atuin() {
  command -v atuin >/dev/null 2>&1 || stop 2 'atuin が無いので、呼び鈴を扱えない'
}

check_addr() {
  [[ "$1" =~ $addr_re ]] || stop 1 "宛先を拒否した($(printable "$1")): 形が commander-<project> ではない。$addr_hint"
}

# ---------------------------------------------------------------------------
# Places / 置き場
# The overrides of close_gate.sh are removed from its environment, as forget.sh
# does: a permission rule may allow this script without asking.
# close_gate.sh の差し替えは、forget.sh と同じく、呼ぶときの環境から外す。この
# スクリプトは、permission rule で確認なしに呼ばれうるためである。
# ---------------------------------------------------------------------------
project=''
vault=''
places_rc=0

# Resolve project and vault; on failure leave the exit code in places_rc.
# project と vault を求める。失敗したら、終了コードを places_rc に残す。
resolve_places() {
  local out line wb=''
  places_rc=0
  out="$(bounded 5 env -u WTCLOSE_VAULT -u WTCLOSE_PROJECT -u WTCLOSE_GIT -u WTCLOSE_NOW \
    bash "$gate" --where 2>/dev/null)" || places_rc=$?
  [ "$places_rc" -eq 0 ] || return 1
  while IFS= read -r line; do
    case "$line" in
      project=*) project="${line#project=}" ;;
      workbench_dir=*) wb="${line#workbench_dir=}" ;;
    esac
  done <<<"$out"
  # workbench_dir is <vault>/AgentMemory/workbench/<project>
  case "$wb" in
    */"$wb_rel"/*) vault="${wb%/"$wb_rel"/*}" ;;
    *) places_rc=1; return 1 ;;
  esac
}

# A linked worktree has its own git dir / linked worktree は自分の git dir を持つ
in_linked_worktree() {
  local dirs
  dirs="$(bounded 2 git rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)" || return 1
  [ "${dirs%%$'\n'*}" != "${dirs##*$'\n'}" ]
}

# Compare names as strings: -d would accept "Obsidian" for "obsidian" on a
# case-insensitive file system, and such a bell would never be read.
# 名前を文字列で比べる。大文字小文字を区別しないファイルシステムでは、-d が
# 「obsidian」に対して「Obsidian」を通してしまい、その呼び鈴は誰にも読まれない。
has_project() {
  local dir
  for dir in "$vault/AgentMemory"/*/; do
    dir="${dir%/}"
    [ "${dir##*/}" != "$1" ] || return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Documents / 文書
# The sender and the reader use the same check, on the real path: a link inside
# the workbench of either machine may point anywhere.
# 送る側も読む側も、同じ検査を実体のパスに対して行う。どちらの機械の作業記憶でも、
# 中に置かれたリンクはどこでも指せるためである。
# ---------------------------------------------------------------------------
doc_rel=''   # the real path, relative to the vault / 実体のパス(vault からの相対)
doc_error='' # never holds a path / パスを含まない

# resolve_doc <path>: sets doc_rel and returns 0, or sets doc_error and returns
# 1 (refused) or 2 (no workbench).
# doc_rel を決めて 0 を返す。だめなら doc_error を決めて、1(拒否)か 2(作業記憶が
# 無い)を返す。
resolve_doc() {
  local real wb_real
  doc_rel=''
  doc_error='実在しないファイルを指している'
  real="$(realpath -e -- "$1" 2>/dev/null)" || return 1
  doc_error="指す作業記憶($wb_rel/)が vault に無い"
  wb_real="$(realpath -e -- "$vault/$wb_rel" 2>/dev/null)" || return 2
  doc_error='制御文字を含むパスを指している'
  ! has_cntrl "$real" || return 1
  doc_error='作業記憶の外を指している'
  [[ "$real" == "$wb_real"/* ]] || return 1
  doc_error='通常の md ファイルではない'
  [[ -f "$real" && "$real" == *.md ]] || return 1
  doc_error=''
  doc_rel="$wb_rel/${real#"$wb_real"/}"
}

# ---------------------------------------------------------------------------
# atuin
# ---------------------------------------------------------------------------
sync_error=''
sync_now() {
  local out rc=0
  out="$(bounded "$sync_limit" atuin sync 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    sync_error="atuin sync が$(why "$rc" "$out")"
    return 1
  fi
  if [[ "$out" != *"$sync_done"* ]]; then
    sync_error="atuin sync が「$sync_done」を出さずに終わった($(first_line "$out"))"
    return 1
  fi
}

# kv <args>...: stdout in kv_out, exit code as is, stderr in err_file.
# 標準出力を kv_out に、標準エラーを err_file に入れ、終了コードはそのまま返す。
kv_out=''
kv() {
  local rc=0
  kv_out="$(bounded "$kv_limit" atuin kv "$@" 2>"$err_file")" || rc=$?
  return "$rc"
}

# ---------------------------------------------------------------------------
# send
# ---------------------------------------------------------------------------
cmd_send() {
  [ "$#" -eq 3 ] || usage 'send の引数は 3 つ'
  local addr="$1" doc="$2" subject="$3"
  local from epoch time key value rc=0
  set_limits 30 5 45
  check_addr "$addr"
  ! [[ "$subject" =~ ^[[:space:]]*$ ]] || stop 1 '用件を拒否した: 空である'
  ! has_cntrl "$subject" || stop 1 '用件を拒否した: 改行・タブなどの制御文字を含む'
  [ "${#subject}" -le "$subject_max_bytes" ] \
    || stop 1 "用件を拒否した: ${#subject} バイトあり、上限の $subject_max_bytes バイトを超えている。詳しい内容は文書に書く"
  resolve_places || stop 2 'vault とプロジェクトを求められない(close_gate.sh --where が失敗した)'
  has_project "${addr#"$addr_prefix"}" \
    || stop 1 "宛先を拒否した($addr): vault に AgentMemory/${addr#"$addr_prefix"} が無いので、誰も読まない。$addr_hint"

  resolve_doc "$doc" || stop "$?" "文書を拒否した($(printable "$doc")): $doc_error"

  from="$addr_prefix$project"
  [[ "$from" =~ $addr_re ]] || stop 2 "差出人の名前を作れない($(printable "$from"))"
  need_atuin
  epoch="$(date +%s)"
  time="$(date -d "@$epoch" '+%Y-%m-%dT%H:%M:%S%z')"
  # The random part keeps two bells rung in the same second apart.
  # 同じ秒に置いた 2 通は、乱数の部分で分かれる。
  key="$(date -u -d "@$epoch" '+%Y%m%d-%H%M%S')-$from-$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
  value="v1"$'\t'"$from"$'\t'"$time"$'\t'"$doc_rel"$'\t'"$subject"
  kv set -n "$ns_prefix$addr" -k "$key" "$value" || rc=$?
  [ "$rc" -eq 0 ] || stop 3 "atuin kv set が$(why "$rc" "$(cat "$err_file")")。$(timed_out "$rc" && printf '呼び鈴を置けたかどうかは分からない' || printf '呼び鈴は置いていない')"
  printf 'sent %s %s\n' "$addr" "$key"
  sync_now || stop 4 "$sync_error。呼び鈴はこの機械に置いた。次の atuin sync で相手に届くので、送り直さない(送り直すと 2 通になる)"
  finish 0
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
# Print one bell as one line / 呼び鈴 1 件を 1 行で出す
show_bell() {
  local addr="$1" key="$2" rest from time rel rc=0
  local head="呼び鈴 $key 宛先=$addr"
  local hint="| 読んで対応したら: bash ~/.claude/scripts/claude_mail.sh ack $addr $key"
  kv get -n "$ns_prefix$addr" "$key" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s 値を読めなかった(atuin kv get が%s)\n' "$head" "$(why "$rc" "$(cat "$err_file")")"
    return 0
  fi
  rest="$kv_out"
  if [[ "$rest" == *$'\n'* || "$rest" != v1$'\t'*$'\t'*$'\t'*$'\t'* ]]; then
    printf '%s 値の形が合わない %s\n' "$head" "$hint"
    return 0
  fi
  rest="${rest#*$'\t'}"
  from="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  time="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  rel="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
  # The path must stay inside the workbench even in a value written by hand.
  # 手で書かれた値でも、パスは作業記憶の中に限る。
  if ! [[ "$from" =~ $addr_re && "$time" =~ $time_re ]] || has_cntrl "$rel" \
    || [[ "$rel" != "$wb_rel"/*.md || "/$rel/" == */../* ]]; then
    printf '%s 値の形が合わない %s\n' "$head" "$hint"
    return 0
  fi
  head+=" 差出人=$from 時刻=$time"
  if [ ! -e "$vault/$rel" ] && [ ! -L "$vault/$rel" ]; then
    printf '%s 文書=%s (本文がまだ届いていない。届くまで ack しない) 用件=%s\n' "$head" "$vault/$rel" "$(printable "$rest")"
  elif resolve_doc "$vault/$rel"; then
    printf '%s 文書=%s 用件=%s %s\n' "$head" "$vault/$rel" "$(printable "$rest")" "$hint"
  else
    # Neither the path nor the ack: the reader must not open it, and the bell stays.
    # パスも ack の案内も出さない。読ませず、呼び鈴は残す。
    printf '%s 文書が%s。読まない 用件=%s\n' "$head" "$doc_error" "$(printable "$rest")"
  fi
}

cmd_list() {
  local addr='' key keys rc=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --to)
        [ "$#" -ge 2 ] || usage '--to に宛先が無い'
        addr="$2"
        shift 2
        ;;
      *) usage "list が知らない引数: $(printable "$1")" ;;
    esac
  done
  set_limits 10 2 15
  if ! resolve_places; then
    # 3 = no vault, or not in a repository: nothing to read here.
    # 3 は、vault が無いか、リポジトリの外。ここで読むものは無い。
    [ "$places_rc" -ne 3 ] || finish 0
    stop 2 "close_gate.sh --where が$(why "$places_rc" '')。呼び鈴を確かめていない"
  fi
  if [ -z "$addr" ]; then
    # The hook runs in every session, so leave before the sync when nobody can
    # have rung here: send refuses a project that has no folder in the vault.
    # hook は全部のセッションで走る。send は vault にフォルダの無いプロジェクトを
    # 拒否するので、ここあての呼び鈴はありえない。同期の前に終わる。
    has_project "$project" || finish 0
    ! in_linked_worktree || finish 0
    addr="$addr_prefix$project"
  fi
  check_addr "$addr"
  need_atuin
  # The receiver cannot read a value before it syncs / 受け取る側は、同期の前には値を読めない
  sync_now || stop 3 "$sync_error。呼び鈴を確かめていない"
  kv list -n "$ns_prefix$addr" || rc=$?
  [ "$rc" -eq 0 ] || stop 3 "atuin kv list が$(why "$rc" "$(cat "$err_file")")。呼び鈴を確かめていない"
  keys="$(sort <<<"$kv_out")"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if [[ "$key" =~ $key_re ]]; then
      show_bell "$addr" "$key"
    else
      warn "$ns_prefix$addr に、形の合わないキーがある: $(printable "$key")"
    fi
  done <<<"$keys"
  finish 0
}

# ---------------------------------------------------------------------------
# ack
# ---------------------------------------------------------------------------
cmd_ack() {
  [ "$#" -eq 2 ] || usage 'ack の引数は 2 つ'
  local addr="$1" key="$2" rc=0
  set_limits 30 5 45
  check_addr "$addr"
  [[ "$key" =~ $key_re ]] || stop 1 "キーを拒否した($(printable "$key")): 形が合わない。list が出すキーをそのまま渡す"
  need_atuin
  kv list -n "$ns_prefix$addr" || rc=$?
  [ "$rc" -eq 0 ] || stop 3 "atuin kv list が$(why "$rc" "$(cat "$err_file")")。呼び鈴は消していない"
  grep -qxF -- "$key" <<<"$kv_out" \
    || stop 1 "キーを拒否した($key): $addr あての呼び鈴に無い(既に消したか、まだ同期していない)"
  kv delete -n "$ns_prefix$addr" "$key" || rc=$?
  [ "$rc" -eq 0 ] || stop 3 "atuin kv delete が$(why "$rc" "$(cat "$err_file")")。$(timed_out "$rc" && printf '呼び鈴を消せたかどうかは分からない' || printf '呼び鈴は消していない')"
  printf 'acked %s %s\n' "$addr" "$key"
  sync_now || stop 4 "$sync_error。呼び鈴はこの機械では消した。次の atuin sync でほかの機械からも消える"
  finish 0
}

# ---------------------------------------------------------------------------
# Main / 本体
# ---------------------------------------------------------------------------
case "$cmd" in
  send) shift; cmd_send "$@" ;;
  list) shift; cmd_list "$@" ;;
  ack) shift; cmd_ack "$@" ;;
  -h | --help) sed -n '2,/^set -euo/{/^#/p}' "$0"; finish 0 ;;
  '') usage 'サブコマンドが無い' ;;
  *) usage "知らないサブコマンド: $(printable "$cmd")" ;;
esac
