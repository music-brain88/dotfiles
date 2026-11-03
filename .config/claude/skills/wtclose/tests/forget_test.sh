#!/usr/bin/env bash
# Tests for forget.sh / 作業物をゴミ箱に移す forget.sh のテスト
#
# Every case builds its own fake workbench, memory directory and list
# _reachability.md under a temporary directory. gio is a fake placed first on
# PATH that only records its arguments, so neither the real vault nor the real
# trash is touched. HOME is also pointed at the temporary directory.
# 各ケースは一時ディレクトリの下に、偽の作業記憶・記憶・一覧 _reachability.md
# を作る。gio は PATH の先頭に置いた偽物で、呼ばれた引数を記録するだけなので、
# 実物の vault にもゴミ箱にも触らない。HOME も一時ディレクトリに向ける。
#
# Usage / 使い方: bash .config/claude/skills/wtclose/tests/forget_test.sh [name-filter]
#
# The fixtures contain literal markdown with backticks.
# fixture は、バッククォートを含む markdown を文字どおりに書く。
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
forget="$script_dir/../forget.sh"
filter="${1:-}"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# Isolate from the user's environment / 利用者の環境から切り離す
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset WTCLOSE_WORKBENCH_DIR WTCLOSE_FORGET_MAX_AGE_HOURS WTCLOSE_VAULT WTCLOSE_PROJECT
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# Fake gio / 偽の gio
# Appends one line per call to $FAKE_GIO_LOG. With FAKE_GIO_FAIL_ON=<path>, the
# call for that path fails like a real error.
# 呼ばれるたびに $FAKE_GIO_LOG に 1 行足す。FAKE_GIO_FAIL_ON=<パス> のときは、
# そのパスの呼び出しを失敗させる。
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/gio" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GIO_LOG"
last="${*: -1}"
if [ -n "${FAKE_GIO_FAIL_ON:-}" ] && [ "$last" = "$FAKE_GIO_FAIL_ON" ]; then
  echo "gio: $last: Error trashing file" >&2
  exit 1
fi
EOF
chmod +x "$root/bin/gio"
export PATH="$root/bin:$PATH"

# ---------------------------------------------------------------------------
# PATH without gio / gio の無い PATH
# Only the commands forget.sh needs are linked, so "gio is missing" can be
# reproduced on a machine that has gio.
# forget.sh が使うコマンドだけを置き、gio がある機械でも「gio が無い」を再現する。
# ---------------------------------------------------------------------------
mkdir -p "$root/nogio-bin"
for c in bash awk sed date stat realpath dirname basename; do
  p="$(command -v "$c" 2>/dev/null || true)"
  case "$p" in
    /*) ln -s "$p" "$root/nogio-bin/$c" ;;
  esac
done

# ---------------------------------------------------------------------------
# Fixture builders / fixture を作る関数
# ---------------------------------------------------------------------------
case_dir=''
vault=''
mem=''
wb=''

# new_case: a vault with a memory directory and a workbench (project "proj").
# new_case: 記憶と作業記憶を持つ vault(プロジェクト名は proj)。
new_case() {
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  vault="$case_dir/vault"
  mem="$vault/AgentMemory/proj"
  wb="$vault/AgentMemory/workbench/proj"
  mkdir -p "$mem" "$wb"
  export FAKE_GIO_LOG="$case_dir/gio.log"
  : >"$FAKE_GIO_LOG"
  unset FAKE_GIO_FAIL_ON
}

# write_list <candidate rel>... -- <stale state abs>...
# Writes _reachability.md in the format of close_gate.sh build_reachability().
# close_gate.sh の build_reachability() と同じ書式で _reachability.md を書く。
write_list() {
  local -a cands=() stales=()
  local p in_stale=''
  for p in "$@"; do
    if [ "$p" = '--' ]; then in_stale=1; continue; fi
    if [ -n "$in_stale" ]; then stales+=("$p"); else cands+=("$p"); fi
  done
  {
    printf -- '---\ntype: agent-workbench\nkind: index\nunit: wtclose\ncreated: 2026-10-01\nupdated: 2026-11-04 09:00\n---\n\n'
    printf '# 作業記憶の到達一覧(proj)\n\n'
    printf '## 忘れる候補\n\n'
    if [ "${#cands[@]}" -gt 0 ]; then
      printf '| path | last_reached | days | note |\n|---|---|---|---|\n'
      for p in "${cands[@]}"; do printf '| `%s` | 2026-10-01 | 34 |  |\n' "$p"; done
      printf '\n'
    else
      printf 'なし\n\n'
    fi
    printf '## 古い状態ファイル\n\n'
    if [ "${#stales[@]}" -gt 0 ]; then
      printf 'as_of が 14 日より前の状態ファイルは、根として扱わない。\n\n| path | as_of | days |\n|---|---|---|\n'
      for p in "${stales[@]}"; do printf '| `%s` | 2026-10-01 10:00 | 34 |\n' "$p"; done
      printf '\n'
    else
      printf 'なし\n\n'
    fi
    # A reached work product, listed only in "## 一覧" / 「## 一覧」にだけ載る作業物
    printf '## 一覧\n\n| path | last_reached | state | note |\n|---|---|---|---|\n'
    printf '| `reached.md` | 2026-11-04 | reached |  |\n'
  } >"$wb/_reachability.md"
}

rc=0
out=''
err=''

# run_forget <args>...: forget.sh with the workbench override / 置き場を差し替えて呼ぶ
run_forget() {
  rc=0
  (cd "$case_dir" && env "WTCLOSE_WORKBENCH_DIR=$wb" bash "$forget" "$@") \
    >"$case_dir/out" 2>"$case_dir/err" </dev/null || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
}

current=''
failures=0
passed=0

flunk() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  printf '  exit=%s\n  stdout:\n    %s\n  stderr:\n    %s\n  gio calls:\n    %s\n' \
    "$rc" "${out//$'\n'/$'\n'    }" "${err//$'\n'/$'\n'    }" "$(sed 's/^/    /' "$FAKE_GIO_LOG" 2>/dev/null)"
  exit 1
}

assert_exit() { [ "$rc" -eq "$1" ] || flunk "exit code: want $1, got $rc"; }
assert_err_has() { grep -qF -- "$1" <<<"$err" || flunk "stderr lacks: $1"; }
assert_out_has() { grep -qxF -- "$1" <<<"$out" || flunk "stdout lacks the line: $1"; }
assert_out_empty() { [ -z "$out" ] || flunk 'stdout is not empty'; }
assert_gio_called() { grep -qxF -- "trash -- $1" "$FAKE_GIO_LOG" || flunk "gio was not called for: $1"; }
assert_gio_calls() {
  local n
  n="$(wc -l <"$FAKE_GIO_LOG")"
  [ "$n" -eq "$1" ] || flunk "gio calls: want $1, got $n"
}

# ---------------------------------------------------------------------------
# 1. Listed paths go to the trash / 一覧に載ったパスはゴミ箱に移る
# ---------------------------------------------------------------------------
test_listed_relative_and_absolute_paths_are_trashed() {
  new_case
  mkdir -p "$wb/sub"
  : >"$wb/20261019-brief-a.md"
  : >"$wb/sub/report-b.md"
  : >"$wb/20261020-brief-c.md"
  : >"$mem/state_commander-proj-2.md"
  write_list 20261019-brief-a.md sub/report-b.md 20261020-brief-c.md -- "$mem/state_commander-proj-2.md"
  # Relative (as in the table), absolute, and the stale state file's absolute path.
  # 表のとおりの相対パス・絶対パス・古い状態ファイルの絶対パス。
  run_forget 20261019-brief-a.md sub/report-b.md "$wb/20261020-brief-c.md" "$mem/state_commander-proj-2.md"
  assert_exit 0
  assert_out_has "trashed $wb/20261019-brief-a.md"
  assert_out_has "trashed $wb/sub/report-b.md"
  assert_out_has "trashed $wb/20261020-brief-c.md"
  assert_out_has "trashed $mem/state_commander-proj-2.md"
  assert_gio_called "$wb/20261019-brief-a.md"
  assert_gio_called "$wb/sub/report-b.md"
  assert_gio_called "$wb/20261020-brief-c.md"
  assert_gio_called "$mem/state_commander-proj-2.md"
  assert_gio_calls 4
}

test_unnormalized_and_duplicate_arguments_match_once() {
  new_case
  : >"$wb/a.md"
  write_list a.md
  run_forget "$wb/./sub/../a.md" a.md
  assert_exit 0
  assert_out_has "trashed $wb/a.md"
  assert_gio_calls 1
}

# ---------------------------------------------------------------------------
# 2. An unlisted path stops everything / 一覧に無いパスが混ざると何も動かさない
# ---------------------------------------------------------------------------
test_unlisted_path_moves_nothing() {
  new_case
  : >"$wb/a.md"
  : >"$wb/reached.md"
  : >"$wb/other.md"
  write_list a.md
  run_forget a.md other.md reached.md
  assert_exit 1
  assert_err_has 'refused other.md: '
  assert_err_has 'refused reached.md: '
  assert_out_empty
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# 3. Symlinks and directories are refused / symlink とディレクトリは拒否する
# ---------------------------------------------------------------------------
test_symlink_and_directory_are_refused() {
  new_case
  : >"$wb/a.md"
  : >"$case_dir/outside.md"
  ln -s "$case_dir/outside.md" "$wb/link.md"
  mkdir -p "$wb/olddir"
  write_list a.md link.md olddir
  run_forget link.md
  assert_exit 1
  assert_err_has 'refused link.md: symlink は消さない'
  run_forget olddir
  assert_exit 1
  assert_err_has 'refused olddir: ディレクトリは消さない'
  run_forget a.md link.md
  assert_exit 1
  assert_gio_calls 0
  [ -e "$case_dir/outside.md" ] || flunk 'symlink target is gone'
}

test_missing_file_is_refused() {
  new_case
  write_list gone.md
  run_forget gone.md
  assert_exit 1
  assert_err_has 'refused gone.md: 通常のファイルとして存在しない'
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# 4. The list and the log themselves are refused / 一覧と記録そのものは拒否する
# ---------------------------------------------------------------------------
test_list_and_log_are_refused() {
  new_case
  : >"$wb/_gate_log.jsonl"
  # Even when a broken list names them / 壊れた一覧が載せていても拒否する
  write_list _reachability.md _gate_log.jsonl
  run_forget _reachability.md
  assert_exit 1
  assert_err_has 'refused _reachability.md: 検問の一覧と記録'
  run_forget "$wb/_gate_log.jsonl"
  assert_exit 1
  assert_err_has "refused $wb/_gate_log.jsonl: 検問の一覧と記録"
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# 5. A stale list is refused / 古い一覧は拒否する
# ---------------------------------------------------------------------------
test_stale_list_is_refused() {
  new_case
  : >"$wb/a.md"
  write_list a.md
  touch -d '25 hours ago' "$wb/_reachability.md"
  run_forget a.md
  assert_exit 1
  assert_err_has 'refused a.md: 一覧が 25 時間前のもので、24 時間より古い'
  assert_err_has 'close_gate.sh --check --session <ID>'
  assert_gio_calls 0
  # The threshold can be changed / 閾値は変えられる
  rc=0
  (cd "$case_dir" && env "WTCLOSE_WORKBENCH_DIR=$wb" WTCLOSE_FORGET_MAX_AGE_HOURS=48 bash "$forget" a.md) \
    >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
  assert_exit 0
  assert_out_has "trashed $wb/a.md"
}

# ---------------------------------------------------------------------------
# 6. No gio: exit 2, nothing moved / gio が無いと終了コード 2 で何も動かさない
# ---------------------------------------------------------------------------
test_no_gio_moves_nothing() {
  new_case
  : >"$wb/a.md"
  write_list a.md
  rc=0
  (cd "$case_dir" && env "PATH=$root/nogio-bin" "WTCLOSE_WORKBENCH_DIR=$wb" "$BASH" "$forget" a.md) \
    >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
  assert_exit 2
  assert_err_has 'gio が無い'
  assert_out_empty
  assert_gio_calls 0
  [ -e "$wb/a.md" ] || flunk 'a.md is gone'
}

# ---------------------------------------------------------------------------
# 7. No arguments: exit 2 / 引数が無いと終了コード 2
# ---------------------------------------------------------------------------
test_no_arguments_exit_2() {
  new_case
  write_list a.md
  run_forget
  assert_exit 2
  assert_err_has '引数が無い'
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# Environment problems and failures / 環境の問題と途中の失敗
# ---------------------------------------------------------------------------
test_missing_list_exit_2() {
  new_case
  : >"$wb/a.md"
  run_forget a.md
  assert_exit 2
  assert_err_has '_reachability.md が無い'
  assert_gio_calls 0
}

test_gio_failure_midway_exit_3() {
  new_case
  : >"$wb/a.md"
  : >"$wb/b.md"
  : >"$wb/c.md"
  write_list a.md b.md c.md
  export FAKE_GIO_FAIL_ON="$wb/b.md"
  run_forget a.md b.md c.md
  assert_exit 3
  assert_out_has "trashed $wb/a.md"
  assert_err_has "gio trash が $wb/b.md で失敗した"
  assert_gio_calls 2
}

# Without the override, the workbench comes from close_gate.sh --where.
# 差し替えが無ければ、置き場は close_gate.sh --where で求める。
test_default_workbench_from_close_gate() {
  new_case
  local repo="$case_dir/proj"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" commit -q --allow-empty -m init
  : >"$wb/a.md"
  write_list a.md
  rc=0
  (cd "$repo" && env "WTCLOSE_VAULT=$vault" bash "$forget" a.md) \
    >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
  assert_exit 0
  assert_out_has "trashed $wb/a.md"
  # Outside a git repository, close_gate.sh --where finds no places.
  # git リポジトリの外では、close_gate.sh --where は置き場を求められない。
  rc=0
  (cd "$case_dir" && env "WTCLOSE_VAULT=$vault" bash "$forget" a.md) \
    >"$case_dir/out" 2>"$case_dir/err" || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
  assert_exit 2
  assert_err_has 'workbench_dir を求められない'
  assert_gio_calls 1
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
