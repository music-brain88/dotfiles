#!/usr/bin/env bash
# GPG passphrase cache check for /wt / /wt の GPG パスフレーズキャッシュの事前チェック
#
# The /wt commander runs this before delegating, to see whether gpg-agent
# still holds the passphrase of the git signing key. Worker panes have no tty
# and cannot show pinentry, so a cold cache makes their signed commits hang.
# /wt の司令塔が委任の前に呼び、git の署名鍵のパスフレーズが gpg-agent に
# キャッシュされているかを確かめる。worker pane は tty を持たず pinentry を
# 出せないので、キャッシュが冷えていると worker の署名コミットが詰まる。
#
# This logic lives in a script instead of SKILL.md because Claude Code
# replaces positional forms (a dollar sign followed by a digit) in a skill
# body with the words of the skill arguments, which broke the awk (#666).
# この処理を SKILL.md ではなくスクリプトに置くのは、Claude Code が skill の
# 本文にある位置引数の形(ドル記号と数字)を skill の引数の語に置き換え、
# awk を壊すため(#666)。
#
# Usage / 使い方:
#   bash ~/.claude/skills/wt/gpg_cache_check.sh
#
# Output / 出力 (stdout, one line / 1 行):
#   cached=1   the signing key is cached / 署名鍵がキャッシュされている
#   cached=0   the signing key is not cached / 署名鍵がキャッシュされていない
#
# Exit codes / 終了コード:
#   0 cached=1
#   1 cached=0
#   2 the signing key cannot be identified, or gpg-agent cannot be queried;
#     the reason goes to stderr and nothing goes to stdout
#     署名鍵を特定できない、または gpg-agent に問い合わせられない。
#     理由は stderr に書き、stdout には何も書かない
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

# 2. The keygrip of the [S] subkey / [S] サブキーの keygrip
# user.signingkey names the primary key, but gpg signs with the subkey that
# has the [S] flag, so read the Keygrip line right after that ssb line.
# user.signingkey は primary 鍵を指すが、署名に使われるのは [S] フラグ付きの
# サブキーなので、その ssb 行の直後の Keygrip 行を読む。
#
# Do not take the Keygrip of the first ssb line. gpg lists ssb [E] before
# ssb [S] by default, and an older awk that printed the third field of the
# first ssb's Keygrip line queried the [E] subkey and reported a warm cache as
# cold (#583).
# 最初の ssb 行の Keygrip を拾ってはいけない。gpg は既定で ssb [E] を ssb [S]
# より先に並べる。以前の awk は最初の ssb の Keygrip 行の 3 列目を出していたため、
# [E] サブキーで照会し、温まっていたキャッシュを冷えていると誤判定した(#583)。
#
# The state is reset at every key record (sec or ssb line), so that an [S]
# record without a Keygrip line never borrows the keygrip of the next record.
# 鍵のレコード(sec 行と ssb 行)ごとに状態を戻す。Keygrip 行の無い [S] の
# レコードが、次のレコードの keygrip を借りないようにするため。
listing="$(gpg --list-secret-keys --with-keygrip "$key_id" 2>/dev/null)" || listing=''
keygrip="$(awk '/^(sec|ssb)/ {found = (/^ssb/ && /\[S\]/); next} found && /Keygrip/ {gsub(/ /,"",$0); sub(/Keygrip=/,""); print; exit}' \
  <<<"$listing")"
# An empty keygrip would match every KEYINFO line and read the cached flag of
# an unrelated key, so stop before asking the agent (review of PR #625).
# keygrip が空だと全 KEYINFO 行にマッチし、無関係な鍵の cached フラグを読んで
# しまうので、agent に問い合わせる前に止める(PR #625 のレビュー指摘)。
[ -n "$keygrip" ] || fail "no [S] subkey keygrip found for $key_id — cannot identify the signing key"

# 3. The cached flag in gpg-agent / gpg-agent の cached フラグ
# Line format: "S KEYINFO <keygrip> D - - <cached> P - - -"; field 7 is 1 when cached.
# 行の形式は "S KEYINFO <keygrip> D - - <cached> P - - -"。7 列目が 1 ならキャッシュあり。
keyinfo="$(gpg-connect-agent 'keyinfo --list' /bye 2>/dev/null)" \
  || fail "gpg-connect-agent failed — cannot query gpg-agent"
cached="$(awk -v grip="$keygrip" '$2 == "KEYINFO" && $3 == grip {print $7; exit}' <<<"$keyinfo")"
[ -n "$cached" ] || fail "gpg-agent does not list keygrip $keygrip of $key_id"

if [ "$cached" = "1" ]; then
  echo "cached=1"
  exit 0
fi
echo "cached=0"
exit 1
