#!/usr/bin/env bash
# GPG passphrase cache check for /wt / /wt の GPG パスフレーズキャッシュの事前チェック
#
# The /wt commander runs this before delegating, to see whether the git
# signing key can sign without pinentry. Worker panes have no tty and cannot
# show pinentry, so a signature that needs a passphrase makes their signed
# commits hang.
# /wt の司令塔が委任の前に呼び、git の署名鍵が pinentry なしで署名できるかを
# 確かめる。worker pane は tty を持たず pinentry を出せないので、パスフレーズが
# 要る状態だと worker の署名コミットが詰まる。
#
# The check makes one trial signature with pinentry disabled
# (gpg --batch --pinentry-mode error --clearsign) and throws the output away.
# An earlier version read the cached column of the [S] subkey's KEYINFO line in
# gpg-agent, but that column stayed "-" while a trial signature succeeded, so
# it reported a usable key as cold (#814). A trial signature answers the real
# question regardless of the key layout or how gpg-agent caches passphrases.
# 判定には、pinentry を出さない設定の試しの署名を 1 回使い、出力は捨てる。
# 以前の版は gpg-agent の KEYINFO 行のうち [S] サブキーの cached の列を読んで
# いたが、その列が "-" のまま試しの署名は通り、使える鍵を冷えていると誤判定
# した(#814)。試しの署名なら、鍵の構成や gpg-agent のキャッシュの仕組みに
# 依らず、本来の問い(worker の署名が通るか)に答えられる。
#
# This logic lives in a script instead of SKILL.md because Claude Code
# replaces positional forms (a dollar sign followed by a digit) in a skill
# body with the words of the skill arguments, which broke an awk (#666).
# この処理を SKILL.md ではなくスクリプトに置くのは、Claude Code が skill の
# 本文にある位置引数の形(ドル記号と数字)を skill の引数の語に置き換え、
# awk を壊したため(#666)。
#
# Usage / 使い方:
#   bash ~/.claude/skills/wt/gpg_cache_check.sh
#
# Environment / 環境変数:
#   GPG_CACHE_CHECK_TIMEOUT  seconds before the trial signature is given up
#                            (default 10) / 試しの署名を打ち切るまでの秒数(既定 10)
#
# Output / 出力 (stdout, one line / 1 行):
#   cached=1   the key signs without pinentry / pinentry なしで署名できる
#   cached=0   the trial signature failed (a passphrase is needed, the key is
#              missing, ...); gpg's reason goes to stderr
#              試しの署名が失敗した(パスフレーズが要る、鍵が無いなど)。
#              gpg の理由は stderr に書く
#
# Exit codes / 終了コード:
#   0 cached=1
#   1 cached=0
#   2 user.signingkey is not set, gpg cannot be run, or the trial signature
#     timed out; the reason goes to stderr and nothing goes to stdout
#     user.signingkey が設定されていない、gpg を実行できない、または試しの
#     署名が時間切れになった。理由は stderr に書き、stdout には何も書かない
set -euo pipefail

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h | --help)
      sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d'
      exit 0
      ;;
    *)
      echo "gpg_cache_check.sh: unexpected argument: $1" >&2
      exit 2
      ;;
  esac
fi

# Every external command is guarded explicitly, so that its failure never
# leaks out as exit 1 (which means cached=0).
# 外部コマンドの失敗が exit 1(cached=0 の意味)として漏れないように、
# どの呼び出しも明示的にガードする。
fail() {
  echo "gpg_cache_check.sh: $*" >&2
  exit 2
}

# 1. The signing key ID / 署名鍵の ID
key_id="$(git config user.signingkey 2>/dev/null)" || key_id=''
[ -n "$key_id" ] || fail "git config user.signingkey is not set — cannot identify the signing key"

# 2. The commands for the trial signature / 試しの署名に使うコマンド
command -v gpg >/dev/null 2>&1 || fail "gpg is not found on PATH — cannot try a signature"
command -v timeout >/dev/null 2>&1 || fail "timeout is not found on PATH — cannot bound the trial signature"
limit="${GPG_CACHE_CHECK_TIMEOUT:-10}"

# 3. One trial signature without pinentry / pinentry を出さない試しの署名を 1 回
# --pinentry-mode error makes gpg fail instead of asking for a passphrase,
# and timeout stops it if gpg-agent does not answer. The signature goes to
# /dev/null, so no file is left behind; only gpg's stderr is kept as the reason.
# --pinentry-mode error で、パスフレーズが要るときは尋ねずに失敗させ、
# gpg-agent が応答しないときは timeout で止める。署名は /dev/null に捨てて
# ファイルを残さず、理由として gpg の stderr だけを取っておく。
code=0
gpg_err="$(printf 'gpg_cache_check\n' \
  | timeout -k 2 "$limit" gpg --batch --pinentry-mode error --clearsign -u "$key_id" -o /dev/null 2>&1 >/dev/null)" \
  || code=$?

# gpg itself exits 0, 1 or 2. 124 and 137 come from timeout (TERM, then KILL),
# and 125 to 127 mean timeout or gpg could not be started.
# gpg 自身の終了コードは 0・1・2。124 と 137 は timeout の打ち切り(TERM、
# その後の KILL)で、125〜127 は timeout か gpg を起動できなかったことを表す。
case "$code" in
  0)
    echo "cached=1"
    exit 0
    ;;
  124 | 137)
    fail "the trial signature with $key_id did not finish within ${limit}s — gpg-agent may not be answering"
    ;;
  125 | 126 | 127)
    fail "could not run the trial signature (exit $code): ${gpg_err##*$'\n'}"
    ;;
esac
echo "gpg_cache_check.sh: the trial signature with $key_id failed (gpg exit $code): ${gpg_err##*$'\n'}" >&2
echo "cached=0"
exit 1
