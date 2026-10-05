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
# FAKE_GH_REPO set   : "gh repo view" prints it / それを出す
# FAKE_GH_REPO empty : exit 1 like a network error / 通信の失敗を真似る
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ -n "${FAKE_GH_REPO:-}" ] || { echo "error connecting to api.github.com" >&2; exit 1; }
echo "$FAKE_GH_REPO"
EOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

case_dir=''
repo=''
notes=''

# new_case [origin URL]: a repository (origin as given, none when empty) and an
# empty notes directory; gh answers music-brain88/dotfiles.
# new_case [origin の URL]: リポジトリ(origin は引数どおり。空なら無し)と、
# 空のノートのディレクトリ。gh は music-brain88/dotfiles と答える。
new_case() {
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  repo="$case_dir/repo"
  notes="$case_dir/notes"
  mkdir -p "$repo" "$notes"
  git -C "$repo" init -q -b main
  [ -z "${1:-}" ] || git -C "$repo" remote add origin "$1"
  export FAKE_GH_REPO='music-brain88/dotfiles'
}

# note <name> <body>: ClaudeCodeSession-<name>.md
note() {
  printf '%s\n' "$2" >"$notes/ClaudeCodeSession-$1.md"
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
