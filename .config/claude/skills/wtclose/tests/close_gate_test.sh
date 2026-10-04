#!/usr/bin/env bash
# Tests for close_gate.sh / 検問スクリプト close_gate.sh のテスト
#
# Every case builds its own fixtures (a git repository with worktrees, a fake
# vault and a fake gh) under a temporary directory. HOME is also pointed at the
# temporary directory, so the real vault ($HOME/Documents/Obsidian) is never
# read or written. No network access is needed.
# 各ケースは一時ディレクトリの下に fixture(worktree つきの git リポジトリ・
# 偽の vault・偽の gh)を作る。HOME も一時ディレクトリに向けるので、実物の
# vault には読みも書きもしない。ネットワークは使わない。
#
# Usage / 使い方: bash .config/claude/skills/wtclose/tests/close_gate_test.sh [name-filter]
#
# The expectations compare literal markdown that contains backticks.
# 期待値は、バッククォートを含む markdown を文字どおり比べる。
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/../close_gate.sh"
filter="${1:-}"

root="$(mktemp -d)"
trap 'chmod -R u+w "$root" 2>/dev/null || true; rm -rf "$root"' EXIT

# Isolate from the user's environment / 利用者の環境から切り離す
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# Fake gh / 偽の gh
# FAKE_GH_MODE=ok   : print $FAKE_GH_PRS (lines of "number<TAB>branch")
# FAKE_GH_MODE=fail : exit 1 like a network error / 通信の失敗を真似る
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/fake_gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_GH_MODE:-ok}" in
  ok) [ -z "${FAKE_GH_PRS:-}" ] || cat "$FAKE_GH_PRS" ;;
  fail) echo "error connecting to api.github.com" >&2; exit 1 ;;
  ansi) printf '\033[31merror\033[0m: bad \001 response\n' >&2; exit 1 ;;
esac
EOF
chmod +x "$root/bin/fake_gh"

# ---------------------------------------------------------------------------
# PATH without jq / jq の無い PATH
# Only the commands close_gate.sh needs are linked, so "jq is missing" can be
# reproduced on a machine that has jq.
# close_gate.sh が使うコマンドだけを置き、jq がある機械でも「jq が無い」を再現する。
# ---------------------------------------------------------------------------
mkdir -p "$root/nojq-bin"
for c in bash git awk sed grep date mktemp rm cat tr head timeout dirname basename \
  find wc sort mkdir mv cp ls readlink realpath printf env chmod; do
  p="$(command -v "$c" 2>/dev/null || true)"
  case "$p" in
    /*) ln -s "$p" "$root/nojq-bin/$c" ;;
  esac
done

# ---------------------------------------------------------------------------
# Fixture builders / fixture を作る関数
# ---------------------------------------------------------------------------
session='11111111-2222-3333-4444-555555555555'
now='2026-10-04 18:30'
case_dir=''
repo=''
vault=''
mem=''
wb=''

# new_case: repository "proj" (origin o/proj) and a vault with memory and notes.
# new_case: リポジトリ proj(origin は o/proj)と、記憶とセッションノートを持つ vault。
new_case() {
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  repo="$case_dir/proj"
  vault="$case_dir/vault"
  mem="$vault/AgentMemory/proj"
  wb="$vault/AgentMemory/workbench/proj"
  mkdir -p "$repo" "$mem" "$vault/Zettelkasten/ResearchNotes"
  git -C "$repo" init -q -b main
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" remote add origin git@github.com:o/proj.git
  : >"$case_dir/prs"
  export FAKE_GH_MODE=ok FAKE_GH_PRS="$case_dir/prs"
}

# add_worktree <branch>: prints the worktree path / worktree を足してパスを出す
add_worktree() {
  local path="$case_dir/wt-${1//\//-}"
  git -C "$repo" worktree add -q -b "$1" "$path"
  printf '%s\n' "$path"
}

# add_pr <number> <branch>
add_pr() {
  printf '%s\t%s\n' "$1" "$2" >>"$case_dir/prs"
}

# write_state [file] [as_of] [session_id] < extra lines of the "remaining" section
# 状態ファイルを書く。stdin の行は「残っているもの」の節に入る。
write_state() {
  local file="${1:-state_commander-proj.md}" asof="${2:-2026-10-04 18:00}" sid="${3:-$session}"
  {
    printf -- '---\nname: state-commander-proj\ntype: agent-memory\nkind: state\nsession_id: %s\nas_of: %s\n---\n\n' "$sid" "$asof"
    printf '# 司令塔の状態\n\n## 稼働中の worker\n\nなし\n\n## 残っているもの\n\n'
    cat
    printf '\n## 次の入口\n\n- 新しいセッションで #700 を委任する\n'
  } >"$mem/$file"
}

# write_state_nested [file] [as_of] [session_id] [top-level lines] < extra lines
# The state file as Claude Code rewrites it after the Write tool (observed with
# Claude Code 2.1.289 on 2026-10-04, #668): session_id and as_of move under
# "metadata:". The optional 4th argument adds top-level lines before metadata.
# Claude Code が Write ツールの後に書き換えた形の状態ファイル(2026-10-04 に
# Claude Code 2.1.289 で観測。#668)。session_id と as_of は「metadata:」の下に移る。
# 4 番目の引数は、metadata の前に一番上の階層の行を足す。
write_state_nested() {
  local file="${1:-state_commander-proj.md}" asof="${2:-2026-10-04 18:00}" sid="${3:-$session}"
  {
    printf -- '---\nname: state-commander-proj\ndescription: commander-proj の状態(%s 時点)。\n%s' "$asof" "${4:-}"
    printf 'metadata:\n  node_type: memory\n  type: project\n  kind: state\n  session_id: %s\n  as_of: %s\n' "$sid" "$asof"
    printf '  originSessionId: 00000000-0000-0000-0000-000000000000\n  modified: 2026-10-04T11:12:36.839Z\n---\n\n'
    printf '# 司令塔の状態\n\n## 稼働中の worker\n\nなし\n\n## 残っているもの\n\n'
    cat
    printf '\n## 次の入口\n\n- 新しいセッションで #700 を委任する\n'
  } >"$mem/$file"
}

# wb_file <rel> <kind> <unit> <created> [body]: a work product / 作業物を作る
wb_file() {
  mkdir -p "$(dirname "$wb/$1")"
  printf -- '---\ntype: agent-workbench\nkind: %s\nunit: "%s"\ncreated: %s\n---\n\n%s\n' "$2" "$3" "$4" "${5:-}" >"$wb/$1"
}

# hook_input [background_tasks JSON] [session_crons JSON] [cwd]
hook_input() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false,"background_tasks":%s,"session_crons":%s}' \
    "$session" "${3:-$repo}" "${1:-[]}" "${2:-[]}"
}

# ---------------------------------------------------------------------------
# Runner and assertions / 実行と検証
# Each test runs in a subshell, so an assertion failure exits that subshell.
# 各テストはサブシェルで走るので、検証の失敗はそのサブシェルを抜ける。
# ---------------------------------------------------------------------------
out=''
err=''
rc=0

# run_gate <stdin> [extra args...]; set NO_VAULT_OVERRIDE=1 to leave WTCLOSE_VAULT unset.
run_gate() {
  local input="$1"
  shift
  local -a envs=("WTCLOSE_NOW=$now" "WTCLOSE_GH=${GH_CMD:-$root/bin/fake_gh}")
  [ -n "${NO_VAULT_OVERRIDE:-}" ] || envs+=("WTCLOSE_VAULT=$vault")
  rc=0
  env "${envs[@]}" bash "$gate" "$@" <<<"$input" >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
}

# run_check: the commander's dry run / 司令塔の試し打ち
run_check() {
  rc=0
  (cd "$repo" && env "WTCLOSE_NOW=$now" "WTCLOSE_GH=$root/bin/fake_gh" "WTCLOSE_VAULT=$vault" \
    bash "$gate" --check --session "$session") >"$case_dir/out" 2>"$case_dir/err" </dev/null || rc=$?
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
assert_err_lacks() { ! grep -qF -- "$1" <<<"$err" || flunk "stderr unexpectedly has: $1"; }
assert_out_has() { grep -qF -- "$1" <<<"$out" || flunk "stdout lacks: $1"; }
assert_file_has() { grep -qF -- "$2" "$1" || flunk "$1 lacks: $2"; }
assert_file_lacks() { ! grep -qF -- "$2" "$1" || flunk "$1 unexpectedly has: $2"; }

# row <rel> <column>: a column of the "## 一覧" table (2 = last_reached, 3 = state, 4 = note)
# row <相対パス> <列>: 一覧の表の列を出す(2 = 最後に辿れた日、3 = 状態、4 = 備考)
row() {
  awk -v rel="$1" -v col="$2" '
    /^## / { insec = ($0 == "## 一覧"); next }
    insec && index($0, "| `" rel "` |") == 1 { n = split($0, c, "|"); v = c[col + 1]; gsub(/^ +| +$/, "", v); print v; exit }' \
    "$wb/_reachability.md"
}
assert_state() {
  local got
  got="$(row "$1" 3)"
  [[ "$got" == "$2"* ]] || flunk "state of $1: want $2*, got '$got'"
}

# ---------------------------------------------------------------------------
# Cases: passing / 通過
# ---------------------------------------------------------------------------
test_pass_all_conditions() {
  new_case
  write_state </dev/null
  run_gate "$(hook_input)"
  assert_exit 0
  assert_out_has 'systemMessage'
  assert_out_has '検問を通過した'
  assert_out_has '新しいセッションで続けて'
}

test_first_run_creates_workbench_and_list() {
  new_case
  write_state </dev/null
  [ ! -e "$vault/AgentMemory/workbench" ] || flunk 'fixture already has a workbench'
  run_gate "$(hook_input)"
  assert_exit 0
  [ -f "$wb/_reachability.md" ] || flunk 'list was not written'
  [ -f "$wb/_gate_log.jsonl" ] || flunk 'log was not written'
  assert_file_has "$wb/_reachability.md" 'type: agent-workbench'
  assert_file_has "$wb/_reachability.md" 'kind: index'
}

# ---------------------------------------------------------------------------
# P1: the state file and its time / 状態ファイルと時点
# ---------------------------------------------------------------------------
test_p1_missing_state_blocks_with_template() {
  new_case
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P1]'
  assert_err_has "session_id: $session"
  assert_err_has 'as_of: 2026-10-04 18:30'
  assert_err_has '## 次の入口'
}

test_p1_old_as_of_blocks() {
  new_case
  write_state state_commander-proj.md '2026-10-03 23:50' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P1]'
  assert_err_has '今日(2026-10-04)の時点ではない'
}

test_p1_unreadable_as_of_blocks() {
  new_case
  write_state state_commander-proj.md 'yesterday' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "as_of が読めない(値: 'yesterday')"
}

test_p1_other_sessions_state_is_not_mine() {
  new_case
  write_state state_commander-proj-2.md '2026-10-04 18:00' 'other-session' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P1]'
  assert_err_has '状態ファイルが'
}

test_p1_duplicate_session_blocks() {
  new_case
  write_state state_a.md </dev/null
  write_state state_b.md </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '同じ session_id の状態ファイルが 2 枚ある'
}

test_p1_without_session_id_takes_todays_newest() {
  new_case
  # The newest is in the middle of the glob order, so the comparison must work
  # (the first or the last in the glob order would pass a broken comparison).
  # いちばん新しいファイルを glob 順の真ん中に置き、比較が効くことを確かめる
  # (先頭や末尾に置くと、壊れた比較でも通ってしまう)。
  write_state state_a.md '2026-10-04 09:00' 'x' </dev/null
  write_state state_b.md '2026-10-04 18:00' 'y' </dev/null
  write_state state_c.md '2026-10-04 12:00' 'z' </dev/null
  run_gate "$(printf '{"cwd":"%s","background_tasks":[]}' "$repo")"
  assert_exit 0
  assert_out_has 'state_b.md を自分のものとみなした'
}

test_p1_without_session_id_tie_keeps_first_in_glob_order() {
  new_case
  # Two files share the newest as_of: the first one in the glob order is kept.
  # いちばん新しい as_of が 2 枚で同じ: glob 順で先に出たほうを残す。
  write_state state_a.md '2026-10-04 09:00' 'x' </dev/null
  write_state state_b.md '2026-10-04 18:00' 'y' </dev/null
  write_state state_c.md '2026-10-04 18:00' 'z' </dev/null
  run_gate "$(printf '{"cwd":"%s","background_tasks":[]}' "$repo")"
  assert_exit 0
  assert_out_has 'state_b.md を自分のものとみなした'
}

# ---------------------------------------------------------------------------
# P1 with the frontmatter rewritten by Claude Code (#668)
# Claude Code が書き換えた frontmatter での P1(#668)
# ---------------------------------------------------------------------------
test_nested_fm_passes() {
  new_case
  write_state_nested </dev/null
  ! grep -qE '^(session_id|as_of):' "$mem/state_commander-proj.md" || flunk 'fixture has top-level keys'
  run_gate "$(hook_input)"
  assert_exit 0
  assert_out_has '検問を通過した'
}

test_nested_fm_old_as_of_blocks() {
  new_case
  write_state_nested state_commander-proj.md '2026-10-03 23:50' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '今日(2026-10-04)の時点ではない'
}

test_nested_fm_other_session_is_not_mine() {
  new_case
  write_state_nested state_commander-proj.md '2026-10-04 18:00' 'other-session' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "このセッション(session_id: $session)の状態ファイルが"
}

test_nested_fm_top_level_wins() {
  new_case
  # metadata says another session and yesterday; the top level says this
  # session and today / metadata は別のセッションと昨日、一番上の階層はこのセッションと今日
  write_state_nested state_commander-proj.md '2026-10-03 10:00' 'other-session' \
    "session_id: $session"$'\n''as_of: 2026-10-04 18:00'$'\n' </dev/null
  run_gate "$(hook_input)"
  assert_exit 0
  # The reverse: another session at the top level hides this session in metadata
  # 逆向き: 一番上の階層の別のセッションが、metadata のこのセッションより優先される
  write_state_nested state_commander-proj.md '2026-10-04 18:00' "$session" \
    $'session_id: other-session\n' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "このセッション(session_id: $session)の状態ファイルが"
}

test_nested_fm_reads_only_direct_children_of_metadata() {
  new_case
  # Under another parent, and one level too deep under metadata
  # ほかの親キーの下と、metadata の 1 段深すぎる下
  {
    printf -- '---\nname: state-commander-proj\nother:\n  session_id: %s\n  as_of: 2026-10-04 18:00\n' "$session"
    printf 'metadata:\n  deep:\n    session_id: %s\n    as_of: 2026-10-04 18:00\n---\n' "$session"
    printf '\n## 次の入口\n\n- 新しいセッションで #700 を委任する\n'
  } >"$mem/state_commander-proj.md"
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "このセッション(session_id: $session)の状態ファイルが"
}

test_nested_fm_without_session_id_takes_todays_newest() {
  new_case
  # The newest is in the middle of the glob order, so the comparison must work
  # いちばん新しいファイルを glob 順の真ん中に置き、比較が効くことを確かめる
  write_state state_a.md '2026-10-04 09:00' 'x' </dev/null
  write_state_nested state_b.md '2026-10-04 18:00' 'y' </dev/null
  write_state_nested state_c.md '2026-10-04 12:00' 'z' </dev/null
  run_gate "$(printf '{"cwd":"%s","background_tasks":[]}' "$repo")"
  assert_exit 0
  assert_out_has 'state_b.md を自分のものとみなした'
}

# ---------------------------------------------------------------------------
# P2: size / 大きさ
# ---------------------------------------------------------------------------
test_p2_too_long_blocks() {
  new_case
  seq 1 200 | sed 's/^/- メモ /' | write_state
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P2]'
  assert_err_has '上限の 200 行を超えている'
}

test_p2_at_limit_passes() {
  new_case
  write_state </dev/null
  local lines
  lines="$(wc -l <"$mem/state_commander-proj.md")"
  seq 1 $((200 - lines)) | sed 's/^/x/' >>"$mem/state_commander-proj.md"
  run_gate "$(hook_input)"
  assert_err_lacks '[P2]'
}

# ---------------------------------------------------------------------------
# P3: next entry / 次の入口
# ---------------------------------------------------------------------------
test_p3_missing_section_blocks() {
  new_case
  write_state </dev/null
  sed -i '/^## 次の入口/,$d' "$mem/state_commander-proj.md"
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P3]'
  assert_err_has '「## 次の入口」の節が無い'
}

test_p3_empty_section_blocks() {
  new_case
  write_state </dev/null
  sed -i '/^- 新しいセッション/d' "$mem/state_commander-proj.md"
  printf '<!-- 空 -->\n\n' >>"$mem/state_commander-proj.md"
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '「## 次の入口」の節が空'
}

# ---------------------------------------------------------------------------
# P4: open PRs and remaining worktrees / open の PR と残っている worktree
# ---------------------------------------------------------------------------
test_p4_unlisted_pr_and_worktree_block() {
  new_case
  local wt
  wt="$(add_worktree feat/x)"
  add_pr 12 feat/x
  write_state </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has 'open の PR #12(feat/x)が'
  assert_err_has "残っている worktree $wt(feat/x)が"
}

test_p4_listed_with_kinds_passes() {
  new_case
  local wt
  wt="$(add_worktree feat/x)"
  add_pr 12 feat/x
  printf -- '- [マージ待ち] PR #12 CI 待ち\n- [worker 稼働中] worktree `%s` 実装中\n' "$wt" | write_state
  run_gate "$(hook_input)"
  assert_exit 0
}

test_p4_mixed_with_other_sessions_items() {
  # PRs and worktrees the commander did not create (another session, the flake.lock bot)
  # 司令塔が作っていない PR と worktree(別のセッション、flake.lock を更新する CI)
  new_case
  local mine others
  mine="$(add_worktree feat/mine)"
  others="$(add_worktree fix/other_session)"
  add_pr 20 feat/mine
  add_pr 21 update_flake_lock_action
  add_pr 22 fix/other_session
  {
    printf -- '- [レビュー待ち] PR #20\n- [worker 稼働中] worktree %s\n' "$mine"
    printf -- '- [別のセッションの管轄] PR #21 flake.lock の自動 PR\n'
    printf -- '- [別のセッションの管轄] PR #22\n- [別のセッションの管轄] worktree %s\n' "$others"
  } | write_state
  run_gate "$(hook_input)"
  assert_exit 0
}

test_p4_unknown_kind_blocks() {
  new_case
  add_pr 12 feat/x
  printf -- '- [あとで見る] PR #12\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '4 つの種類のどれでもない: - [あとで見る] PR #12'
}

test_p4_written_but_not_real_is_recorded_not_blocked() {
  new_case
  printf -- '- [マージ待ち] PR #99\n- [worker 稼働中] worktree /nowhere/wt\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 0
  assert_file_has "$wb/_gate_log.jsonl" 'PR #99 は、このリポジトリでは open ではない'
  assert_file_has "$wb/_gate_log.jsonl" 'worktree /nowhere/wt は、このリポジトリの git worktree list に無い'
}

test_p4_qualifier_omitted_and_own_qualifier_behave_the_same() {
  new_case
  add_pr 12 feat/x
  add_pr 13 feat/y
  printf -- '- [マージ待ち] PR #12\n- [マージ待ち] PR o/proj#13\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 0
  # The own qualifier is matched case-insensitively and still checked against gh.
  # 自分のリポジトリの修飾子は大文字小文字を区別せず、gh の実物と照合される。
  printf -- '- [マージ待ち] PR O/Proj#12\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has 'open の PR #13(feat/y)が'
  assert_err_lacks 'open の PR #12'
}

test_p4_other_repository_line_is_recorded_not_checked() {
  new_case
  printf -- '- [マージ待ち] PR other/infra#5 別のリポジトリ\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 0
  assert_file_has "$wb/_gate_log.jsonl" '他のリポジトリ other/infra の PR #5 は、実物と照合していない'
}

test_p4_other_repository_line_still_needs_a_kind() {
  new_case
  printf -- '- [たぶん] PR other/infra#5\n' | write_state
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P4]'
}

# ---------------------------------------------------------------------------
# P8: gh failures / gh の失敗
# ---------------------------------------------------------------------------
test_p8_gh_failure_blocks_without_record() {
  new_case
  write_state </dev/null
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P8]'
  assert_err_has 'error connecting to api.github.com'
  assert_err_has '- [PR の状態は未確認] 2026-10-04 18:30'
}

test_p8_gh_failure_passes_with_todays_record() {
  new_case
  printf -- '- [PR の状態は未確認] 2026-10-04 18:25 gh が通らない\n' | write_state
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 0
  assert_out_has 'P8:'
}

test_p8_old_record_blocks() {
  new_case
  printf -- '- [PR の状態は未確認] 2026-10-01 10:00\n' | write_state
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '今日の日付ではない'
}

test_p8_gh_failure_still_checks_worktrees() {
  new_case
  add_worktree feat/x >/dev/null
  printf -- '- [PR の状態は未確認] 2026-10-04 18:25\n' | write_state
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P4] 残っている worktree'
  assert_err_lacks '[P8]'
}

test_p8_missing_gh_is_handled() {
  new_case
  write_state </dev/null
  GH_CMD="$root/no-such-gh" run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P8] gh で PR の状態を確かめられなかった: gh コマンドが見つからない'
}

# ---------------------------------------------------------------------------
# P5: background waits / 裏の待ち受け
# ---------------------------------------------------------------------------
test_p5_blocks_running_background_task() {
  new_case
  write_state </dev/null
  run_gate "$(hook_input '[{"id":"b1","type":"shell","status":"running","description":"wait worker","command":"herdr agent wait claude-x"}]')"
  assert_exit 2
  assert_err_has '[P5]'
  assert_err_has 'herdr agent wait claude-x'
}

test_p5_blocks_session_cron() {
  new_case
  write_state </dev/null
  run_gate "$(hook_input '[]' '[{"id":"c1","schedule":"*/5 * * * *","recurring":true,"prompt":"check CI"}]')"
  assert_exit 2
  assert_err_has '[P5]'
  assert_err_has 'check CI'
}

test_p5_ignores_finished_task() {
  new_case
  write_state </dev/null
  run_gate "$(hook_input '[{"id":"b1","type":"shell","status":"completed","description":"done","command":"true"}]')"
  assert_exit 0
}

test_p5_missing_field_is_recorded_not_blocked() {
  new_case
  write_state </dev/null
  run_gate "$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop"}' "$session" "$repo")"
  assert_exit 0
  assert_out_has 'background_tasks が無い'
}

test_p5_without_jq_is_recorded_not_blocked() {
  new_case
  write_state </dev/null
  local input
  input="$(hook_input '[{"id":"b1","type":"shell","status":"running","description":"x","command":"sleep 9"}]')"
  rc=0
  PATH="$root/nojq-bin" WTCLOSE_VAULT="$vault" WTCLOSE_NOW="$now" WTCLOSE_GH="$root/bin/fake_gh" \
    "$root/nojq-bin/bash" "$gate" <<<"$input" >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
  assert_exit 0
  assert_err_lacks 'command not found'
  assert_out_has 'jq が無い'
}

# ---------------------------------------------------------------------------
# P6 and P7: reachability / 到達の一覧
# ---------------------------------------------------------------------------
test_p6_reachability_by_every_link_kind() {
  new_case
  wb_file 20261001-brief-abs.md brief feat/a 2026-09-01
  wb_file 20261001-brief-wiki.md brief feat/b 2026-09-01
  printf -- '---\nname: verdict-by-name\ntype: agent-workbench\nkind: verdict\nunit: feat/c\ncreated: 2026-09-01\n---\n' >"$wb/named.md"
  wb_file 20261001-report-rel.md report feat/d 2026-09-01
  wb_file 20261001-memorial-note.md memorial feat/e 2026-09-01 'ログ: [待ち受け](logs/wait.log)'
  mkdir -p "$wb/logs" && echo '{}' >"$wb/logs/wait.log"
  wb_file 20261001-brief-orphan.md brief feat/f 2026-09-01
  printf -- '- [[verdict-by-name]] と [[20261001-brief-wiki|指示書]]\n- [報告](../workbench/proj/20261001-report-rel.md)\n' >"$mem/project_x.md"
  printf -- '供養: ~/Documents/x/AgentMemory/workbench/proj/20261001-memorial-note.md、以上\n' \
    >"$vault/Zettelkasten/ResearchNotes/ClaudeCodeSession-20261004-X.md"
  printf -- '- 指示書は %s\n' "$wb/20261001-brief-abs.md" | write_state
  run_gate "$(hook_input)"
  assert_exit 0
  assert_state 20261001-brief-abs.md reached
  assert_state 20261001-brief-wiki.md reached
  assert_state named.md reached
  assert_state 20261001-report-rel.md reached
  assert_state 20261001-memorial-note.md reached
  assert_state logs/wait.log reached
  assert_state 20261001-brief-orphan.md candidate
  assert_file_has "$wb/_reachability.md" '| `20261001-brief-orphan.md` | 2026-09-01 | 33 |'
}

test_p6_dormant_boundary_is_14_days() {
  new_case
  write_state </dev/null
  wb_file d14.md brief feat/a 2026-09-20
  wb_file d15.md brief feat/b 2026-09-19
  run_gate "$(hook_input)"
  assert_state d14.md 'dormant 14d'
  assert_state d15.md 'candidate 15d'
}

test_p6_last_reached_date_is_kept_between_runs() {
  new_case
  wb_file brief.md brief feat/a 2026-09-01
  now='2026-09-10 10:00'
  printf -- "- [[brief]]\n" | write_state state_commander-proj.md '2026-09-10 09:00'
  run_gate "$(hook_input)"
  assert_state brief.md reached
  now='2026-10-04 18:30'
  write_state </dev/null
  run_gate "$(hook_input)"
  [ "$(row brief.md 2)" = '2026-09-10' ] || flunk "last_reached: want 2026-09-10, got $(row brief.md 2)"
  assert_state brief.md 'candidate 24d'
}

test_p6_open_units_are_held() {
  new_case
  local wt
  wt="$(add_worktree feat/live)"
  add_pr 30 feat/pr_branch
  printf -- '- [マージ待ち] PR #30\n- [worker 稼働中] worktree %s\n' "$wt" | write_state
  wb_file by-branch.md brief feat/live 2026-08-01 '[ログ](by-branch.log)'
  echo x >"$wb/by-branch.log"
  wb_file by-pr.md verdict '#30' 2026-08-01
  wb_file by-pr-branch.md brief feat/pr_branch 2026-08-01
  wb_file by-own-qualifier.md verdict 'o/proj#30' 2026-08-01
  wb_file closed.md brief feat/gone 2026-08-01
  run_gate "$(hook_input)"
  assert_exit 0
  assert_state by-branch.md held
  assert_state by-branch.log held
  assert_state by-pr.md held
  assert_state by-pr-branch.md held
  assert_state by-own-qualifier.md held
  assert_state closed.md candidate
}

test_p6_other_repository_unit_is_not_held() {
  new_case
  write_state </dev/null
  wb_file other-pr.md verdict 'other/infra#30' 2026-08-01
  wb_file other-branch.md brief 'other/infra@feat/live' 2026-08-01
  run_gate "$(hook_input)"
  assert_state other-pr.md candidate
  assert_state other-branch.md candidate
  [[ "$(row other-pr.md 4)" == *'他のリポジトリ other/infra の単位で、open かどうかは確かめていない'* ]] \
    || flunk "note of other-pr.md: $(row other-pr.md 4)"
}

test_p6_gh_failure_holds_pr_units() {
  new_case
  printf -- '- [PR の状態は未確認] 2026-10-04 18:25\n' | write_state
  wb_file by-pr.md verdict '#30' 2026-08-01
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 0
  assert_state by-pr.md held
}

test_p6_stale_state_file_is_not_a_root() {
  new_case
  write_state </dev/null
  write_state state_commander-proj-2.md '2026-09-15 10:00' 'old-session' </dev/null
  printf -- '- [[from-stale]]\n' >>"$mem/state_commander-proj-2.md"
  write_state state_commander-proj-3.md 'いつか' 'odd-session' </dev/null
  printf -- '- [[from-unreadable]]\n' >>"$mem/state_commander-proj-3.md"
  wb_file from-stale.md brief feat/a 2026-08-01
  wb_file from-unreadable.md brief feat/b 2026-08-01
  run_gate "$(hook_input)"
  assert_exit 0
  assert_state from-stale.md candidate
  assert_state from-unreadable.md reached
  assert_file_has "$wb/_reachability.md" "| \`$mem/state_commander-proj-2.md\` | 2026-09-15 10:00 | 19 |"
  assert_file_has "$wb/_reachability.md" 'state_commander-proj-3.md` は as_of が読めないので'
  [ -f "$mem/state_commander-proj-2.md" ] || flunk 'the gate deleted a stale state file'
}

test_p6_nested_stale_state_file_is_not_a_root() {
  new_case
  write_state_nested </dev/null
  write_state_nested state_commander-proj-2.md '2026-09-15 10:00' 'old-session' </dev/null
  printf -- '- [[from-stale]]\n' >>"$mem/state_commander-proj-2.md"
  write_state_nested state_commander-proj-3.md 'いつか' 'odd-session' </dev/null
  printf -- '- [[from-unreadable]]\n' >>"$mem/state_commander-proj-3.md"
  wb_file from-stale.md brief feat/a 2026-08-01
  wb_file from-unreadable.md brief feat/b 2026-08-01
  run_gate "$(hook_input)"
  assert_exit 0
  assert_state from-stale.md candidate
  assert_state from-unreadable.md reached
  assert_file_has "$wb/_reachability.md" "| \`$mem/state_commander-proj-2.md\` | 2026-09-15 10:00 | 19 |"
  assert_file_has "$wb/_reachability.md" 'state_commander-proj-3.md` は as_of が読めないので'
}

test_p6_gate_never_deletes_work_products() {
  new_case
  write_state </dev/null
  wb_file old.md brief feat/a 2026-01-01
  local before after
  before="$(find "$vault" -type f ! -name '_reachability.md' ! -name '_gate_log.jsonl' | sort)"
  run_gate "$(hook_input)"
  after="$(find "$vault" -type f ! -name '_reachability.md' ! -name '_gate_log.jsonl' | sort)"
  [ "$before" = "$after" ] || flunk 'files changed under the vault'
  assert_state old.md candidate
}

test_p6_list_and_log_are_not_work_products() {
  new_case
  write_state </dev/null
  run_gate "$(hook_input)"
  run_gate "$(hook_input)"
  assert_file_lacks "$wb/_reachability.md" '| `_reachability.md`'
  assert_file_lacks "$wb/_reachability.md" '| `_gate_log.jsonl`'
}

test_p7_unwritable_workbench_blocks() {
  new_case
  write_state </dev/null
  mkdir -p "$wb"
  chmod 555 "$wb"
  run_gate "$(hook_input)"
  chmod 755 "$wb"
  if [ "$(id -u)" -eq 0 ]; then return 0; fi # root ignores permissions / root は権限を無視する
  assert_exit 2
  assert_err_has '[P7]'
  assert_err_has '[P6]'
}

# ---------------------------------------------------------------------------
# Unreadable files and unexpected failures / 読めないファイルと想定外の失敗
# exit 2 must only mean "conditions are unmet, here is how to pass".
# exit 2 は「条件がそろっていない。こう書けば通る」のときだけに使う。
# ---------------------------------------------------------------------------
is_root() { [ "$(id -u)" -eq 0 ]; } # root ignores permissions / root は権限を無視する

test_unreadable_own_state_blocks_with_reason() {
  new_case
  is_root && return 0
  write_state </dev/null
  chmod 000 "$mem/state_commander-proj.md"
  run_gate "$(hook_input)"
  chmod 644 "$mem/state_commander-proj.md"
  assert_exit 2
  assert_err_has "[P1] 状態ファイル $mem/state_commander-proj.md を読めない"
  assert_err_has "chmod u+r $mem/state_commander-proj.md"
  assert_err_lacks 'awk: fatal'
  [ "$(wc -l <"$wb/_gate_log.jsonl")" -eq 1 ] || flunk 'the block was not recorded'
}

test_unreadable_other_state_is_noted() {
  new_case
  is_root && return 0
  write_state </dev/null
  write_state state_other.md '2026-10-04 12:00' 'other-session' </dev/null
  chmod 000 "$mem/state_other.md"
  run_gate "$(hook_input)"
  chmod 644 "$mem/state_other.md"
  assert_exit 0
  assert_out_has 'state_other.md を読めないので、根として扱えなかった'
}

test_unreadable_workbench_dir_is_skipped() {
  new_case
  is_root && return 0
  write_state </dev/null
  mkdir -p "$wb/locked"
  wb_file ok.md brief feat/a 2026-10-01
  chmod 000 "$wb/locked"
  run_gate "$(hook_input)"
  chmod 755 "$wb/locked"
  assert_exit 0
  assert_out_has 'P7: 作業記憶の中の読めない場所を飛ばした'
  assert_state ok.md dormant
  [ "$(wc -l <"$wb/_gate_log.jsonl")" -eq 1 ] || flunk 'the run was not recorded'
}

test_unreadable_work_product_is_noted() {
  new_case
  is_root && return 0
  write_state </dev/null
  wb_file secret.md brief feat/a 2026-10-01
  chmod 000 "$wb/secret.md"
  run_gate "$(hook_input)"
  chmod 644 "$wb/secret.md"
  assert_exit 0
  [[ "$(row secret.md 4)" == *'読めないので frontmatter を確かめていない'* ]] || flunk "note: $(row secret.md 4)"
}

test_unexpected_failure_exits_1_and_is_recorded() {
  new_case
  write_state </dev/null
  WTCLOSE_FAULT=2 run_gate "$(hook_input)"
  assert_exit 1
  assert_err_has 'wtclose の検問は、条件を確かめられなかった'
  assert_err_has '終了コード 2'
  assert_err_has 'このターンは止めない'
  [ "$(jq -r '.result' "$wb/_gate_log.jsonl")" = 'error' ] || flunk 'error was not recorded'
}

test_failed_as_of_read_exits_1_and_is_recorded() {
  new_case
  write_state state_a.md '2026-10-04 09:00' 'x' </dev/null
  write_state state_b.md '2026-10-04 18:00' 'y' </dev/null
  write_state state_c.md '2026-10-04 12:00' 'z' </dev/null
  mkdir -p "$wb" "$case_dir/failawk-bin"
  # A fake awk that fails only the n-th read of as_of by fm_get (FAIL_AT = n).
  # Failing each read in turn shows that none of them is swallowed, e.g. by a
  # command substitution inside a condition.
  # fm_get が as_of を読む n 回目だけ失敗する偽の awk(FAIL_AT = n)。読む呼び出しを
  # 1 つずつ失敗させ、どれも握りつぶされない(条件式の中の置換など)ことを確かめる。
  cat >"$case_dir/failawk-bin/awk" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *' key=as_of '*)
    n=\$((\$(cat "$case_dir/awk_count" 2>/dev/null || echo 0) + 1))
    echo "\$n" >"$case_dir/awk_count"
    if [ "\$n" -eq "\${FAIL_AT:-0}" ]; then : >"$case_dir/awk_failed"; exit 7; fi
    ;;
esac
exec "$(command -v awk)" "\$@"
EOF
  chmod +x "$case_dir/failawk-bin/awk"
  local n input name="$current" covered=''
  input="$(printf '{"cwd":"%s","background_tasks":[]}' "$repo")"
  for n in $(seq 1 20); do
    current="$name (read #$n of as_of failed)"
    rm -f "$case_dir/awk_count" "$case_dir/awk_failed" "$wb/_gate_log.jsonl"
    rc=0
    PATH="$case_dir/failawk-bin:$PATH" FAIL_AT="$n" WTCLOSE_VAULT="$vault" WTCLOSE_NOW="$now" \
      WTCLOSE_GH="$root/bin/fake_gh" bash "$gate" <<<"$input" >"$case_dir/out" 2>"$case_dir/err" || rc=$?
    out="$(cat "$case_dir/out")"
    err="$(cat "$case_dir/err")"
    # Every read has been failed once / すべての読み取りを 1 回ずつ失敗させ終えた
    [ -f "$case_dir/awk_failed" ] || { covered=1; break; }
    [ "$rc" -ne 2 ] || flunk 'the gate must not exit 2'
    assert_exit 1
    assert_err_has 'wtclose の検問は、条件を確かめられなかった'
    [[ "$err" =~ [0-9]+\ 行目、終了コード\ 7 ]] || flunk 'stderr lacks the line number and the exit code'
    [ "$(jq -r '.result' "$wb/_gate_log.jsonl")" = 'error' ] || flunk 'error was not recorded'
  done
  current="$name"
  [ "$n" -gt 3 ] || flunk "as_of was read only $((n - 1)) times; the fake awk did not take effect"
  [ -n "$covered" ] || flunk 'as_of was read 20 times or more'
}

test_unexpected_failure_before_places_exits_1() {
  new_case
  now='bogus'
  run_gate "$(hook_input)"
  assert_exit 1
  assert_err_has 'wtclose の検問は、条件を確かめられなかった'
}

test_log_escapes_control_characters() {
  new_case
  write_state </dev/null
  FAKE_GH_MODE=ansi run_gate "$(hook_input)"
  assert_exit 2
  jq -e . "$wb/_gate_log.jsonl" >/dev/null || flunk 'log line is not valid JSON'
  jq -r '.reasons[]' "$wb/_gate_log.jsonl" | grep -qF 'gh pr list が失敗した' || flunk 'reason is missing'
}

test_vault_below_a_dot_directory() {
  new_case
  mkdir -p "$case_dir/.hidden"
  mv "$vault" "$case_dir/.hidden/vault"
  vault="$case_dir/.hidden/vault"
  mem="$vault/AgentMemory/proj"
  wb="$vault/AgentMemory/workbench/proj"
  printf -- '- [[linked]]\n' | write_state
  wb_file linked.md brief feat/a 2026-09-01
  run_gate "$(hook_input)"
  assert_exit 0
  assert_state linked.md reached
}

# ---------------------------------------------------------------------------
# Temporary list file, impossible times, paths with spaces (review 2)
# 一覧の一時ファイル、存在しない日時、空白を含むパス(レビュー 2)
# ---------------------------------------------------------------------------
assert_no_temp_list() {
  local left
  left="$(find "$wb" -maxdepth 1 -name '._reachability.md.*' 2>/dev/null)"
  [ -z "$left" ] || flunk "temporary list left behind: $left"
}

test_temp_list_never_left_behind() {
  new_case
  run_gate "$(hook_input)"          # block / 停止
  assert_exit 2
  assert_no_temp_list
  write_state </dev/null
  run_gate "$(hook_input)"          # pass / 通過
  assert_exit 0
  assert_no_temp_list
  WTCLOSE_FAULT=2 run_gate "$(hook_input)" # unexpected exit / 想定外の終了
  assert_exit 1
  assert_no_temp_list
  rm -f "$wb/_reachability.md"
  mkdir -p "$wb/_reachability.md/x"  # the rename fails / 置き換えが失敗する
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P7] 一覧'
  assert_no_temp_list
}

test_concurrent_gates_both_write_a_whole_list() {
  new_case
  write_state </dev/null
  wb_file a.md brief feat/a 2026-10-01
  local i rc1 rc2
  for i in 1 2 3; do
    rc1=0
    rc2=0
    WTCLOSE_VAULT="$vault" WTCLOSE_NOW="$now" WTCLOSE_GH="$root/bin/fake_gh" \
      bash "$gate" <<<"$(hook_input)" >/dev/null 2>"$case_dir/e1" &
    local p1=$!
    WTCLOSE_VAULT="$vault" WTCLOSE_NOW="$now" WTCLOSE_GH="$root/bin/fake_gh" \
      bash "$gate" <<<"$(hook_input)" >/dev/null 2>"$case_dir/e2" &
    local p2=$!
    wait "$p1" || rc1=$?
    wait "$p2" || rc2=$?
    if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then flunk "run $i: rc1=$rc1 rc2=$rc2 $(cat "$case_dir/e1" "$case_dir/e2")"; fi
    assert_file_has "$wb/_reachability.md" '| `a.md` |'
    assert_no_temp_list
  done
}

test_impossible_times_are_unreadable() {
  new_case
  write_state state_commander-proj.md '2026-10-04 99:99' </dev/null
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "as_of が読めない(値: '2026-10-04 99:99')"
  write_state </dev/null
  write_state state_other.md '2026-02-30 10:00' 'other-session' </dev/null
  run_gate "$(hook_input)"
  assert_exit 0
  assert_file_has "$wb/_reachability.md" 'state_other.md` は as_of が読めないので'
}

test_p8_impossible_time_blocks() {
  new_case
  printf -- '- [PR の状態は未確認] 2026-10-04 99:99\n' | write_state
  FAKE_GH_MODE=fail run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has '[P8]'
}

test_p4_worktree_path_with_spaces() {
  new_case
  local wt="$case_dir/My Repo/wt x"
  mkdir -p "$case_dir/My Repo"
  git -C "$repo" worktree add -q -b feat/space "$wt"
  printf -- '- [worker 稼働中] worktree `%s` 実装中\n' "$wt" | write_state
  run_gate "$(hook_input)"
  assert_exit 0
  printf -- '- [worker 稼働中] worktree %s\n' "$wt" | write_state
  run_gate "$(hook_input)"
  assert_exit 2
  assert_err_has "残っている worktree $wt(feat/space)が"
  assert_err_has "worktree \`$wt\` <補足>"
}

# ---------------------------------------------------------------------------
# Record / 記録
# ---------------------------------------------------------------------------
test_log_records_blocks_and_passes() {
  new_case
  run_gate "$(hook_input)"
  write_state </dev/null
  run_gate "$(hook_input)"
  [ "$(wc -l <"$wb/_gate_log.jsonl")" -eq 2 ] || flunk 'want 2 log lines'
  jq -e . "$wb/_gate_log.jsonl" >/dev/null || flunk 'log is not valid JSON lines'
  [ "$(jq -r '.result' "$wb/_gate_log.jsonl" | paste -sd, -)" = 'block,pass' ] || flunk 'results'
  # Without a state file both P1 and P3 are unmet / 状態ファイルが無いと P1 と P3 がそろわない
  [ "$(head -n 1 "$wb/_gate_log.jsonl" | jq -r '.failed | join(",")')" = 'P1,P3' ] || flunk 'failed ids'
  [ "$(head -n 1 "$wb/_gate_log.jsonl" | jq -r '.session_id')" = "$session" ] || flunk 'session_id'
}

# ---------------------------------------------------------------------------
# Places / 置き場
# ---------------------------------------------------------------------------
test_places_from_linked_worktree_use_main_name() {
  new_case
  local wt
  wt="$(add_worktree feat/x)"
  run_gate '' --where --cwd "$wt"
  assert_exit 0
  assert_out_has 'project=proj'
  assert_out_has "workbench_dir=$wb"
}

test_places_from_auto_memory_directory() {
  new_case
  mkdir -p "$repo/.claude" "$vault/AgentMemory/renamed"
  printf '{"autoMemoryDirectory": "~/Documents/Obsidian/AgentMemory/renamed/"}\n' >"$repo/.claude/settings.local.json"
  run_gate '' --where --cwd "$repo"
  assert_out_has 'project=renamed'
  assert_out_has "memory_dir=$vault/AgentMemory/renamed"
  assert_out_has "workbench_dir=$vault/AgentMemory/workbench/renamed"
}

test_places_auto_memory_directory_without_vault_override() {
  new_case
  mkdir -p "$repo/.claude" "$HOME/Documents/Obsidian/AgentMemory/renamed"
  printf '{"autoMemoryDirectory": "~/Documents/Obsidian/AgentMemory/renamed"}\n' >"$repo/.claude/settings.local.json"
  NO_VAULT_OVERRIDE=1 run_gate '' --where --cwd "$repo"
  assert_out_has "memory_dir=$HOME/Documents/Obsidian/AgentMemory/renamed"
  assert_out_has "workbench_dir=$HOME/Documents/Obsidian/AgentMemory/workbench/renamed"
}

test_places_project_override_wins() {
  new_case
  mkdir -p "$repo/.claude"
  printf '{"autoMemoryDirectory": "~/Documents/Obsidian/AgentMemory/renamed"}\n' >"$repo/.claude/settings.local.json"
  WTCLOSE_PROJECT=forced run_gate '' --where project --cwd "$repo"
  [ "$out" = 'forced' ] || flunk "project: $out"
}

test_skip_without_vault() {
  new_case
  rm -rf "$vault/AgentMemory"
  run_gate "$(hook_input)"
  assert_exit 0
  assert_out_has 'vault('
  assert_out_has 'が無い'
  run_gate '' --where --cwd "$repo"
  assert_exit 3
}

test_skip_outside_git_repository() {
  new_case
  mkdir -p "$case_dir/plain"
  run_gate "$(hook_input '[]' '[]' "$case_dir/plain")"
  assert_exit 0
  assert_out_has 'systemMessage'
  assert_out_has 'git リポジトリの中ではない'
}

# ---------------------------------------------------------------------------
# --check: the commander's dry run / 司令塔の試し打ち
# ---------------------------------------------------------------------------
test_check_mode_reports_on_stdout() {
  new_case
  run_check
  assert_exit 2
  assert_out_has '[P1]'
  assert_out_has 'P5: --check では確かめない'
  write_state </dev/null
  run_check
  assert_exit 0
  assert_out_has '検問を通過した'
  [ "$(jq -r '.mode' "$wb/_gate_log.jsonl" | sort -u)" = 'check' ] || flunk 'log mode'
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
