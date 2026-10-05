#!/usr/bin/env bash
# Harvest search for /wtclean / /wtclean の収穫ステップの検索
#
# Step 9 of /wtclean runs this for each removed worktree, to find the
# ClaudeCodeSession notes that cite the merged PR of this repository.
# /wtclean の手順 9 が、削除した worktree ごとに呼び、マージ済みの PR を
# 引用した ClaudeCodeSession ノートを探す。
#
# A PR number alone does not name a repository. The old one-line grep also
# hit a note that cited another repository's PR with the same number (#667),
# so a note is kept only when it cites the PR of this repository.
# PR の番号だけではリポジトリが決まらない。以前の 1 行の grep は、別の
# リポジトリの同じ番号の PR を引用したノートにもヒットした(#667)。
# そこで、このリポジトリの PR を引用したノートだけを残す。
#
# A note hits when it contains any of these, where N is not followed by a digit:
# ノートは次のどれかを含むとヒットする(N の直後に数字が続かないこと):
#   (1) <this owner/repo>#N
#   (2) github.com/<this owner/repo>/pull/N
#   (3) #N without a repository qualifier, e.g. "#N" or "PR#N"
#       リポジトリの修飾が付かない #N(例: "#N"、"PR#N")
# A note that cites N only as <other owner/repo>#N or
# github.com/<other owner/repo>/pull/N does not hit.
# <別の owner/repo>#N と github.com/<別の owner/repo>/pull/N だけで N を
# 引用したノートはヒットしない。
#
# (3) is kept on purpose: a bare #N cannot be tied to a repository, but the
# notes usually cite this repository's PRs that way, and dropping it would miss
# more notes than it would wrongly hit.
# (3) はわざと残す。修飾なしの #N はリポジトリを決められないが、ノートは
# このリポジトリの PR をその形で引用することが多く、除くと取りこぼしの方が増える。
#
# This logic lives in a script instead of SKILL.md for two reasons: Claude
# Code replaces positional forms (a dollar sign followed by a digit) in a skill
# body with the words of the skill arguments (#666), and the rule above does
# not fit in one grep.
# この処理を SKILL.md ではなくスクリプトに置く理由は 2 つ。Claude Code は
# skill の本文にある位置引数の形(ドル記号と数字)を skill の引数の語に置き
# 換える(#666)。上の規則は 1 行の grep に収まらない。
#
# Usage / 使い方:
#   bash ~/.claude/skills/wtclean/harvest_search.sh <PR number> [<notes dir>]
#   Run it inside the repository; this repository's owner/repo comes from
#   "gh repo view", or from the origin URL when gh cannot tell.
#   リポジトリの中で呼ぶ。自分の owner/repo は "gh repo view" で求め、gh で
#   求められないときは origin の URL から求める。
#
# The notes are only read, never changed. / ノートは読むだけで、変更しない。
#
# Output / 出力 (stdout): the path of each hit note, one per line
#                          ヒットしたノートのパスを 1 行 1 件
#
# Exit codes / 終了コード:
#   0 one or more notes hit / 1 本以上ヒットした
#   1 no note hit / 1 本もヒットしなかった
#   2 the search could not run; the reason goes to stderr
#     検索できなかった。理由は stderr に書く
set -euo pipefail

readonly default_notes_dir='/home/archie/Documents/Obsidian/Zettelkasten/ResearchNotes'
# owner/repo as GitHub allows it / GitHub が許す owner/repo の文字
readonly repo_chars='A-Za-z0-9_.-'

fail() {
  echo "harvest_search.sh: $*" >&2
  exit 2
}

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d'
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail "usage: harvest_search.sh <PR number> [<notes dir>]"
pr="$1"
notes_dir="${2:-$default_notes_dir}"
[[ "$pr" =~ ^[0-9]+$ ]] || fail "PR number must be digits: $pr"
[ -d "$notes_dir" ] || fail "notes directory not found: $notes_dir"
# Without these, the glob below silently matches nothing and reads as "no hit"
# これが無いと、下のグロブが黙って何にも一致せず「ヒットなし」に見える
[ -r "$notes_dir" ] && [ -x "$notes_dir" ] || fail "notes directory is not readable: $notes_dir"

# ---------------------------------------------------------------------------
# This repository's owner/repo / 自分の owner/repo
# ---------------------------------------------------------------------------
valid_repo() {
  [[ "$1" =~ ^[$repo_chars]+/[$repo_chars]+$ ]]
}

resolve_repo() {
  local repo='' url='' why_gh why_origin
  if command -v gh >/dev/null 2>&1; then
    local -a run=(gh repo view --json nameWithOwner --jq .nameWithOwner)
    # Do not hang on the network / 通信で止まり続けない
    if command -v timeout >/dev/null 2>&1; then run=(timeout 30 "${run[@]}"); fi
    repo="$("${run[@]}" 2>/dev/null)" || repo=''
    if valid_repo "$repo"; then
      echo "$repo"
      return 0
    fi
    why_gh="gh repo view failed or printed no owner/repo"
  else
    why_gh="gh is not installed"
  fi

  # git@github.com:owner/repo.git | https://github.com/owner/repo(.git) | ssh://git@github.com/owner/repo.git
  url="$(git remote get-url origin 2>/dev/null)" || url=''
  url="${url%/}"
  url="${url%.git}"
  # The host must be exactly github.com, not a name that merely ends with it
  # ホストは github.com ちょうどに限る。github.com で終わるだけの名前は通さない
  if [[ "$url" =~ ^(git@github\.com:|https?://([^@/]+@)?github\.com/|ssh://([^@/]+@)?github\.com(:[0-9]+)?/)([$repo_chars]+/[$repo_chars]+)$ ]]; then
    echo "${BASH_REMATCH[5]}"
    return 0
  fi
  if [ -z "$url" ]; then
    why_origin="no origin remote here ($(pwd))"
  else
    why_origin="origin is not a GitHub repository URL: $url"
  fi
  fail "cannot tell this repository's owner/repo: $why_gh; $why_origin"
}

repo="$(resolve_repo)" || exit 2
# Dots in a repository name are literal / リポジトリ名のドットは文字どおりに比べる
repo_re="${repo//./\\.}"

# ---------------------------------------------------------------------------
# The rule / 判定の規則
# GitHub treats owner/repo case-insensitively, so (1) and (2) ignore case.
# GitHub は owner/repo の大文字小文字を区別しないので、(1) と (2) も区別しない。
# ---------------------------------------------------------------------------
end='([^0-9]|$)'
# (1) this owner/repo#N; the owner must not be glued to a longer name
#     自分の owner/repo#N。owner の前に名前の文字が続かないこと
pat_self_ref="(^|[^$repo_chars])$repo_re#$pr$end"
# (2) github.com/this owner/repo/pull/N; the host must not be a longer name
#     such as not.github.com
#     自分のリポジトリの PR の URL。not.github.com のような長いホスト名は除く
pat_self_url="(^|[^$repo_chars])github\\.com/$repo_re/pull/$pr$end"
# (3) after every qualified x/y#M is removed, a #N is left
#     修飾付きの x/y#M をすべて取り除いたあとに、#N が残る
pat_qualified="[$repo_chars]+/[$repo_chars]+#[0-9]+"
pat_bare="#$pr$end"
# The old search, used only to narrow the files to read
# 以前の検索。読むファイルを絞るためだけに使う
pat_candidate="#$pr$end|pull/$pr$end"

note_hits() {
  local note="$1" rc=0 stripped
  grep -qiE -e "$pat_self_ref" -e "$pat_self_url" -- "$note" || rc=$?
  [ "$rc" -le 1 ] || fail "cannot read $note"
  [ "$rc" -eq 1 ] || return 0
  # Take sed's output into a variable first: piping it into "grep -q" lets grep
  # quit at the first match, and sed then dies of SIGPIPE on a long note.
  # sed の出力は先に変数へ取る。"grep -q" にパイプすると grep が最初の一致で
  # 終わり、長いノートでは sed が SIGPIPE で死ぬため。
  stripped="$(sed -E "s|$pat_qualified||g" -- "$note")" || fail "cannot read $note"
  grep -qE -e "$pat_bare" <<<"$stripped"
}

shopt -s nullglob
notes=("$notes_dir"/ClaudeCodeSession-*.md)
[ "${#notes[@]}" -gt 0 ] || exit 1

rc=0
listing="$(grep -lE -e "$pat_candidate" -- "${notes[@]}")" || rc=$?
[ "$rc" -le 1 ] || fail "grep failed in $notes_dir"
candidates=()
[ -z "$listing" ] || mapfile -t candidates <<<"$listing"

found=1
for note in "${candidates[@]}"; do
  if note_hits "$note"; then
    printf '%s\n' "$note"
    found=0
  fi
done
exit "$found"
