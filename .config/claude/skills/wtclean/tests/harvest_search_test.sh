#!/usr/bin/env bash
# Tests for harvest_search.sh / 収穫ステップの検索 harvest_search.sh のテスト
#
# Every case builds its own fixtures (a git repository, a notes directory and
# a fake gh on PATH) under a temporary directory, so the real vault is never
# read and no network access is needed.
# 各ケースは一時ディレクトリの下に fixture(git リポジトリ・ノートの
# ディレクトリ・PATH の先頭の偽の gh)を作る。実物の vault は読まないし、
# ネットワークも使わない。
#
# Usage / 使い方: bash .config/claude/skills/wtclean/tests/harvest_search_test.sh [name-filter]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
search="$script_dir/../harvest_search.sh"
filter="${1:-}"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# Isolate from the user's environment / 利用者の環境から切り離す
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# Fake gh / 偽の gh
# "gh repo view":
#   FAKE_GH_REPO set   : prints it / それを出す
#   FAKE_GH_REPO empty : exit 1 like a network error / 通信の失敗を真似る
# "gh pr view" (its arguments are appended to FAKE_GH_LOG / 引数を FAKE_GH_LOG に追記する):
#   FAKE_GH_PR_CREATED unset : exit 1 like "no pull requests found"
#                              「PR が見つからない」失敗を真似る
#   FAKE_GH_PR_CREATED set   : prints it, even when empty / 空でもそのまま出す
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'repo view')
    [ -n "${FAKE_GH_REPO:-}" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
    echo "$FAKE_GH_REPO"
    ;;
  'pr view')
    printf '%s\n' "$*" >>"${FAKE_GH_LOG:-/dev/null}"
    [ -n "${FAKE_GH_PR_CREATED+set}" ] || { echo "no pull requests found" >&2; exit 1; }
    printf '%s\n' "$FAKE_GH_PR_CREATED"
    ;;
  *)
    echo "fake gh: unknown command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

case_dir=''
repo=''
notes=''

# new_case [origin URL]: a repository (origin as given, none when empty) and an
# empty notes directory; gh answers music-brain88/dotfiles, and "gh pr view"
# fails, so the creation-time filter is skipped unless a case sets it.
# new_case [origin の URL]: リポジトリ(origin は引数どおり。空なら無し)と、
# 空のノートのディレクトリ。gh は music-brain88/dotfiles と答え、"gh pr view" は
# 失敗する。ケースが設定しない限り、作成日時の絞り込みは省かれる。
new_case() {
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  repo="$case_dir/repo"
  notes="$case_dir/notes"
  mkdir -p "$repo" "$notes"
  git -C "$repo" init -q -b main
  [ -z "${1:-}" ] || git -C "$repo" remote add origin "$1"
  export FAKE_GH_REPO='music-brain88/dotfiles'
  unset FAKE_GH_PR_CREATED
  export FAKE_GH_LOG="$case_dir/gh.log"
}

# note <name> <body>: ClaudeCodeSession-<name>.md
note() {
  printf '%s\n' "$2" >"$notes/ClaudeCodeSession-$1.md"
}

# note_at <name> <date> <body>: a note whose mtime is <date> (touch -d)
# note_at <name> <日時> <本文>: mtime が <日時> のノート(touch -d)
note_at() {
  note "$1" "$3"
  touch -d "$2" -- "$notes/ClaudeCodeSession-$1.md"
}

rc=0
out=''
err=''

# run_search <args...>: runs inside the case repository / ケースのリポジトリの中で呼ぶ
run_search() {
  rc=0
  (cd "$repo" && bash "$search" "$@") >"$case_dir/out" 2>"$case_dir/err" </dev/null || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
}

current=''
failures=0
passed=0

flunk() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  printf '  exit=%s\n  stdout:\n    %s\n  stderr:\n    %s\n' "$rc" "${out//$'\n'/$'\n'    }" "${err//$'\n'/$'\n'    }"
  exit 1
}

assert_exit() { [ "$rc" -eq "$1" ] || flunk "exit code: want $1, got $rc"; }
assert_err_has() { grep -qF -- "$1" <<<"$err" || flunk "stderr lacks: $1"; }
# assert_hits <name...>: stdout is exactly these notes / stdout がちょうどこれらのノート
assert_hits() {
  local want='' n
  for n in "$@"; do want+="$notes/ClaudeCodeSession-$n.md"$'\n'; done
  [ "$(sort <<<"$out")" = "$(sort <<<"${want%$'\n'}")" ] || flunk "hits: want [$*]"
}

# ---------------------------------------------------------------------------
# The rule / 判定の規則
# ---------------------------------------------------------------------------

# The 2026-10-04 case (#667): another repository's #663 and its pull/663 only
# 2026-10-04 の実例(#667): 別リポジトリの #663 と、その pull/663 だけ
test_other_repo_only_does_not_hit() {
  new_case
  note other '- hyprwm/hyprland-plugins#663
[hyprwm/hyprland-plugins#663](https://github.com/hyprwm/hyprland-plugins/pull/663)'
  run_search 663 "$notes"
  assert_exit 1
  assert_hits
}

test_own_qualified_ref_hits() {
  new_case
  note own 'PR music-brain88/dotfiles#663 をマージした'
  run_search 663 "$notes"
  assert_exit 0
  assert_hits own
}

test_own_pull_url_hits() {
  new_case
  note own 'https://github.com/music-brain88/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_exit 0
  assert_hits own
}

# The usual form in the notes: [PR #534](https://github.com/.../pull/534)
# ノートでよく使う形
test_markdown_link_hits() {
  new_case
  note own '- [PR #534](https://github.com/music-brain88/dotfiles/pull/534)'
  run_search 534 "$notes"
  assert_hits own
}

# A bare #N cannot be tied to a repository; it hits on purpose
# 修飾なしの #N はリポジトリを決められないが、わざとヒットさせる
test_bare_ref_hits() {
  new_case
  note hash 'PR #663 の締め'
  note glued 'PR#663 の締め'
  note eol 'see #663'
  run_search 663 "$notes"
  assert_exit 0
  assert_hits hash glued eol
}

test_bare_ref_beside_other_repo_hits() {
  new_case
  note mixed 'hyprwm/hyprland-plugins#663 と、こちらの #663'
  run_search 663 "$notes"
  assert_hits mixed
}

test_other_repo_beside_own_url_hits() {
  new_case
  note mixed 'hyprwm/hyprland-plugins#663 / https://github.com/music-brain88/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_hits mixed
}

# The placeholder of the close gate format is another repository's form
# 検問の書式の例 owner/repo#N は、別リポジトリの形として扱う
test_placeholder_qualifier_does_not_hit() {
  new_case
  # The note body is literal markdown with backticks / 本文はバッククォートを含む markdown そのもの
  # shellcheck disable=SC2016
  note placeholder '書式は `- [マージ待ち] PR owner/repo#663`'
  run_search 663 "$notes"
  assert_exit 1
}

test_other_repo_url_does_not_hit() {
  new_case
  note other 'https://github.com/someone/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_exit 1
}

# The boundary kept from the old grep: N must not be followed by a digit
# 以前の grep から引き継いだ境界: N の直後に数字が続かない
test_longer_number_does_not_hit() {
  new_case
  note longer '#534 と music-brain88/dotfiles#534 と https://github.com/music-brain88/dotfiles/pull/534'
  run_search 53 "$notes"
  assert_exit 1
}

# GitHub ignores the case of owner/repo / GitHub は owner/repo の大文字小文字を区別しない
test_case_insensitive_owner_repo() {
  new_case
  note ref 'Music-Brain88/Dotfiles#663'
  note url 'https://GitHub.com/Music-Brain88/Dotfiles/pull/663'
  run_search 663 "$notes"
  assert_hits ref url
}

# A longer owner name that ends with ours is another repository
# 自分の owner で終わる、より長い owner は別のリポジトリ
test_longer_owner_does_not_hit() {
  new_case
  note other 'not-music-brain88/dotfiles#663 と https://github.com/not-music-brain88/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_exit 1
}

# A host that merely ends with github.com is another site (review of PR #686)
# github.com で終わるだけのホストは別のサイト(PR #686 のレビュー指摘)
test_subdomain_url_does_not_hit() {
  new_case
  note other 'https://not.github.com/music-brain88/dotfiles/pull/663 と https://notgithub.com/music-brain88/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_exit 1
}

# A dot in the repository name is literal / リポジトリ名のドットは文字どおり
test_dot_in_repo_name_is_literal() {
  new_case
  export FAKE_GH_REPO='o/a.b'
  note other 'o/axb#7 と https://github.com/o/axb/pull/7'
  note own 'o/a.b#7'
  run_search 7 "$notes"
  assert_hits own
}

# A long note whose bare #N comes first: the search must not stop with an
# error when it finds the match early (a pipe into "grep -q" broke this).
# 修飾なしの #N が先頭にある長いノート。早く一致しても、検索がエラーで
# 止まらないこと("grep -q" へのパイプがこれを壊した)。
test_long_note_with_early_bare_ref_hits() {
  new_case
  {
    printf '#663\n'
    for _ in $(seq 1 20000); do printf 'filler line of a long session note\n'; done
  } >"$notes/ClaudeCodeSession-long.md"
  run_search 663 "$notes"
  assert_exit 0
  assert_hits long
}

# Only ClaudeCodeSession-*.md is searched / ClaudeCodeSession-*.md だけを探す
test_other_notes_are_ignored() {
  new_case
  printf '#663\n' >"$notes/SomethingElse.md"
  run_search 663 "$notes"
  assert_exit 1
}

test_no_notes_exits_1() {
  new_case
  run_search 663 "$notes"
  assert_exit 1
  assert_hits
}

# ---------------------------------------------------------------------------
# The PR's creation time (#810) / PR の作成日時(#810)
# ---------------------------------------------------------------------------

# The 2026-11-14 case: notes last modified months before the PR was created
# cite another repository's issues as a bare #N
# 2026-11-14 の実例: PR の作成の数か月前に最後に更新されたノートが、別の
# リポジトリの Issue を修飾なしの #N で引用していた
test_note_older_than_pr_does_not_hit() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note_at table '2026-07-27 12:00:00 UTC' '| #331 | 対話プロトコル |'
  note_at prose '2026-08-12 12:00:00 UTC' '対話プロトコル(#331)'
  run_search 331 "$notes"
  assert_exit 1
  assert_hits
}

test_note_newer_than_pr_hits() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note_at old '2026-11-14 03:12:44 UTC' 'PR #331 の締め'
  note_at new '2026-11-14 03:12:46 UTC' 'PR #331 の締め'
  run_search 331 "$notes"
  assert_exit 0
  assert_hits new
}

# A note written in the same second as the PR is kept
# PR と同じ秒に書かれたノートは残す
test_note_at_pr_creation_hits() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note_at same '2026-11-14 03:12:45 UTC' 'PR #331 の締め'
  run_search 331 "$notes"
  assert_exit 0
  assert_hits same
}

# A symlinked note is judged by the file it points to: the link itself is
# older than the PR, the target was updated after it (review of PR #815)
# symlink のノートは先のファイルで判定する。symlink 自体は PR より古く、先の
# ファイルは PR の後に更新された(PR #815 のレビュー指摘)
test_symlinked_note_uses_target_mtime() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  local target="$case_dir/elsewhere.md"
  printf 'PR #331 の締め\n' >"$target"
  touch -d '2026-11-15 00:00:00 UTC' -- "$target"
  ln -s "$target" "$notes/ClaudeCodeSession-link.md"
  touch -h -d '2020-01-01 00:00:00 UTC' -- "$notes/ClaudeCodeSession-link.md"
  run_search 331 "$notes"
  assert_exit 0
  assert_hits link
}

# A broken symlink stops the candidate grep with exit 2, as before the filter;
# it never reaches stat -L (review of PR #815)
# 壊れた symlink は、絞り込みを足す前と同じく、候補の grep で終了コード 2 で
# 止まる。stat -L までは届かない(PR #815 のレビュー指摘)
test_broken_symlinked_note_exits_2() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note own '#331'
  ln -s "$case_dir/nowhere.md" "$notes/ClaudeCodeSession-broken.md"
  run_search 331 "$notes"
  assert_exit 2
  assert_hits
  assert_err_has 'grep failed in'
}

# The filter only drops notes; the rule still decides the rest
# 絞り込みはノートを除くだけで、残りは従来の規則が決める
test_newer_note_of_other_repo_does_not_hit() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note_at other '2026-11-15 00:00:00 UTC' 'hyprwm/hyprland-plugins#331'
  run_search 331 "$notes"
  assert_exit 1
}

# gh pr view is asked about this repository's PR / gh pr view には自分のリポジトリの PR を聞く
test_pr_view_names_this_repo() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note own '#331'
  run_search 331 "$notes"
  grep -sqF -- 'pr view 331 --repo music-brain88/dotfiles --json createdAt' "$FAKE_GH_LOG" ||
    flunk "gh pr view args: $(cat "$FAKE_GH_LOG" 2>/dev/null)"
}

# When gh cannot tell createdAt, an old note hits as before. An unset
# FAKE_GH_PR_CREATED also stands for a number that is not a PR here (an issue).
# gh で createdAt を求められないときは、古いノートも従来どおりヒットする。
# FAKE_GH_PR_CREATED が未設定の場合は、番号がここの PR ではない場合(Issue)も兼ねる。
test_old_note_hits_when_pr_view_fails() {
  new_case
  note_at old '2020-01-01 00:00:00 UTC' 'PR #331 の締め'
  run_search 331 "$notes"
  assert_exit 0
  assert_hits old
  [ -s "$FAKE_GH_LOG" ] || flunk 'gh pr view was not called'
}

test_old_note_hits_when_pr_view_prints_nothing() {
  new_case
  export FAKE_GH_PR_CREATED=''
  note_at old '2020-01-01 00:00:00 UTC' 'PR #331 の締め'
  run_search 331 "$notes"
  assert_exit 0
  assert_hits old
}

test_old_note_hits_when_date_cannot_parse() {
  new_case
  export FAKE_GH_PR_CREATED='not a date'
  note_at old '2020-01-01 00:00:00 UTC' 'PR #331 の締め'
  run_search 331 "$notes"
  assert_exit 0
  assert_hits old
}

# Without gh on PATH, owner/repo comes from origin and the filter is skipped
# PATH に gh が無いときは、owner/repo を origin から求め、絞り込みを省く
test_old_note_hits_without_gh() {
  new_case git@github.com:music-brain88/dotfiles.git
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note_at old '2020-01-01 00:00:00 UTC' 'PR #331 の締め'
  local nogh="$case_dir/nogh" cmd
  mkdir -p "$nogh"
  # What the script and run_search call, except gh / スクリプトと run_search が呼ぶもののうち gh 以外
  for cmd in bash git grep sed stat date timeout cat; do
    ln -s "$(command -v "$cmd")" "$nogh/$cmd"
  done
  PATH="$nogh" run_search 331 "$notes"
  assert_exit 0
  assert_hits old
  [ ! -s "$FAKE_GH_LOG" ] || flunk 'the fake gh was called'
}

# No candidate, no gh call / 候補が無ければ gh を呼ばない
test_no_candidate_skips_pr_view() {
  new_case
  export FAKE_GH_PR_CREATED='2026-11-14T03:12:45Z'
  note none 'nothing to see'
  run_search 331 "$notes"
  assert_exit 1
  [ ! -s "$FAKE_GH_LOG" ] || flunk 'gh pr view was called without a candidate'
}

# ---------------------------------------------------------------------------
# This repository's owner/repo / 自分の owner/repo
# ---------------------------------------------------------------------------

test_origin_ssh_fallback_when_gh_fails() {
  new_case git@github.com:music-brain88/dotfiles.git
  export FAKE_GH_REPO=''
  note own 'music-brain88/dotfiles#663'
  note other 'hyprwm/hyprland-plugins#663'
  run_search 663 "$notes"
  assert_exit 0
  assert_hits own
}

test_origin_https_fallback_when_gh_fails() {
  new_case https://github.com/music-brain88/dotfiles
  export FAKE_GH_REPO=''
  note own 'https://github.com/music-brain88/dotfiles/pull/663'
  run_search 663 "$notes"
  assert_hits own
}

test_gh_and_origin_both_fail() {
  new_case
  export FAKE_GH_REPO=''
  note own '#663'
  run_search 663 "$notes"
  assert_exit 2
  assert_hits
  assert_err_has "cannot tell this repository's owner/repo"
  assert_err_has 'no origin remote'
}

test_origin_ssh_scheme_fallback_when_gh_fails() {
  new_case ssh://git@github.com:22/music-brain88/dotfiles.git
  export FAKE_GH_REPO=''
  note own 'music-brain88/dotfiles#663'
  run_search 663 "$notes"
  assert_hits own
}

# A host that merely ends with github.com is not GitHub (review of PR #686)
# github.com で終わるだけのホストは GitHub ではない(PR #686 のレビュー指摘)
test_lookalike_origin_host_fails() {
  local url
  for url in https://notgithub.com/acme/repo.git git@notgithub.com:acme/repo.git; do
    new_case "$url"
    export FAKE_GH_REPO=''
    run_search 663 "$notes"
    assert_exit 2
    assert_err_has 'origin is not a GitHub repository URL'
  done
}

test_non_github_origin_fails() {
  new_case https://gitlab.com/music-brain88/dotfiles.git
  export FAKE_GH_REPO=''
  run_search 663 "$notes"
  assert_exit 2
  assert_err_has 'origin is not a GitHub repository URL'
}

# ---------------------------------------------------------------------------
# Arguments / 引数
# ---------------------------------------------------------------------------

test_pr_number_must_be_digits() {
  new_case
  run_search '#663' "$notes"
  assert_exit 2
  assert_err_has 'PR number must be digits'
}

test_missing_notes_dir() {
  new_case
  run_search 663 "$case_dir/nowhere"
  assert_exit 2
  assert_err_has 'notes directory not found'
}

# An unreadable directory must not read as "no hit" (review of PR #686)
# 読めないディレクトリを「ヒットなし」と見せない(PR #686 のレビュー指摘)
test_unreadable_notes_dir() {
  [ "$(id -u)" -ne 0 ] || return 0 # root ignores permissions / root は権限を無視する
  new_case
  note own '#663'
  chmod 000 "$notes"
  run_search 663 "$notes"
  chmod 755 "$notes"
  assert_exit 2
  assert_err_has 'notes directory is not readable'
}

test_no_arguments() {
  new_case
  run_search
  assert_exit 2
  assert_err_has 'usage:'
}

test_help() {
  new_case
  run_search --help
  assert_exit 0
  grep -qF 'Usage / 使い方' <<<"$out" || flunk 'help lacks the usage'
}

# ---------------------------------------------------------------------------
# Main / 実行
# ---------------------------------------------------------------------------
for t in $(declare -F | awk '{print $3}' | grep '^test_' || true); do
  [ -z "$filter" ] || [[ "$t" == *"$filter"* ]] || continue
  current="$t"
  if ("$t"); then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$t"
  else
    failures=$((failures + 1))
  fi
done

printf '\n%d passed, %d failed\n' "$passed" "$failures"
[ "$failures" -eq 0 ]
