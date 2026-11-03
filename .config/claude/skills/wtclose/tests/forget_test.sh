#!/usr/bin/env bash
# Tests for forget.sh / 作業物をゴミ箱に移す forget.sh のテスト
#
# Every case builds its own fake workbench, memory directory and list
# _reachability.md under a temporary directory. forget.sh is copied into the
# temporary directory next to a fake close_gate.sh that answers --where with
# the fixture's places, because forget.sh has no override for its places.
# gio is a fake placed first on PATH that only records its arguments, so
# neither the real vault nor the real trash is touched. HOME is also pointed at
# the temporary directory.
# 各ケースは一時ディレクトリの下に、偽の作業記憶・記憶・一覧 _reachability.md
# を作る。forget.sh には置き場の差し替え口が無いので、forget.sh を一時
# ディレクトリに複製し、隣に偽の close_gate.sh(--where で fixture の置き場を
# 返す)を置く。gio は PATH の先頭に置いた偽物で、呼ばれた引数を記録するだけ
# なので、実物の vault にもゴミ箱にも触らない。HOME も一時ディレクトリに向ける。
#
# Usage / 使い方: bash .config/claude/skills/wtclose/tests/forget_test.sh [name-filter]
#
# The fixtures contain literal markdown with backticks.
# fixture は、バッククォートを含む markdown を文字どおりに書く。
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
real_forget="$script_dir/../forget.sh"
filter="${1:-}"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# Isolate from the user's environment / 利用者の環境から切り離す
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset WTCLOSE_FORGET_MAX_AGE_HOURS WTCLOSE_VAULT WTCLOSE_PROJECT WTCLOSE_GIT
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# forget.sh next to a fake close_gate.sh / forget.sh と偽の close_gate.sh
# FAKE_WB / FAKE_MEM : the places --where answers / --where が返す置き場
# FAKE_WHERE_FAIL=1  : --where fails like "no vault" / vault が無いときを真似る
# ---------------------------------------------------------------------------
mkdir -p "$root/skill"
cp "$real_forget" "$root/skill/forget.sh"
forget="$root/skill/forget.sh"
cat >"$root/skill/close_gate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = '--where' ] || exit 64
if [ -n "${FAKE_WHERE_FAIL:-}" ]; then
  echo 'wtclose の検問を省いた: vault が無い' >&2
  exit 3
fi
case "${2:-}" in
  workbench_dir) printf '%s\n' "$FAKE_WB" ;;
  memory_dir) printf '%s\n' "$FAKE_MEM" ;;
  *) exit 64 ;;
esac
EOF

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

# ---------------------------------------------------------------------------
# Fake stat / 偽の stat
# Passes through to the real stat. With FAKE_STAT_BUMP_ON=<n>, the n-th call
# from the start of the case answers another inode, as if close_gate.sh had
# replaced the list just before that call. forget.sh reads the generation
# 1) before reading the rows, 2) after reading them, 3) just before trashing.
# 本物の stat に渡す。FAKE_STAT_BUMP_ON=<n> のときは、ケースの初めから n 回目の
# 呼び出しだけ別の inode を返し、その直前に検問が一覧を置き換えたことを真似る。
# forget.sh が世代を読むのは、1) 行を読む前 2) 読んだ後 3) ゴミ箱に移す直前。
# ---------------------------------------------------------------------------
real_stat="$(command -v stat)"
cat >"$root/bin/stat" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -z "\${FAKE_STAT_BUMP_ON:-}" ]; then exec "$real_stat" "\$@"; fi
n=\$((\$(cat "\$FAKE_STAT_COUNT" 2>/dev/null || echo 0) + 1))
echo "\$n" >"\$FAKE_STAT_COUNT"
out="\$("$real_stat" "\$@")"
if [ "\$n" -eq "\$FAKE_STAT_BUMP_ON" ]; then out="999\${out}"; fi
printf '%s\n' "\$out"
EOF
chmod +x "$root/bin/stat"
export PATH="$root/bin:$PATH"

# ---------------------------------------------------------------------------
# PATH without gio / gio の無い PATH
# Only the commands forget.sh needs are linked, so "gio is missing" can be
# reproduced on a machine that has gio.
# forget.sh が使うコマンドだけを置き、gio がある機械でも「gio が無い」を再現する。
# ---------------------------------------------------------------------------
mkdir -p "$root/nogio-bin"
for c in bash env awk sed date realpath dirname basename; do
  p="$(command -v "$c" 2>/dev/null || true)"
  case "$p" in
    /*) ln -s "$p" "$root/nogio-bin/$c" ;;
  esac
done
ln -s "$real_stat" "$root/nogio-bin/stat"

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
  export FAKE_WB="$wb" FAKE_MEM="$mem"
  export FAKE_GIO_LOG="$case_dir/gio.log" FAKE_STAT_COUNT="$case_dir/stat.count"
  : >"$FAKE_GIO_LOG"
  unset FAKE_GIO_FAIL_ON FAKE_STAT_BUMP_ON FAKE_WHERE_FAIL
}

# write_list [-r <raw row>]... <candidate path>... -- <stale state path>...
# Writes _reachability.md in the format of close_gate.sh build_reachability().
# "-r <row>" puts a raw row into the candidate table as it is.
# close_gate.sh の build_reachability() と同じ書式で _reachability.md を書く。
# 「-r <行>」は、忘れる候補の表にその行をそのまま入れる。
write_list() {
  local -a cands=() stales=() raws=()
  local p in_stale=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -r) raws+=("$2"); shift ;;
      --) in_stale=1 ;;
      *) if [ -n "$in_stale" ]; then stales+=("$1"); else cands+=("$1"); fi ;;
    esac
    shift
  done
  {
    printf -- '---\ntype: agent-workbench\nkind: index\nunit: wtclose\ncreated: 2026-10-01\nupdated: 2026-11-04 09:00\n---\n\n'
    printf '# 作業記憶の到達一覧(proj)\n\n'
    printf '## 忘れる候補\n\n'
    if [ "$((${#cands[@]} + ${#raws[@]}))" -gt 0 ]; then
      printf '| path | last_reached | days | note |\n|---|---|---|---|\n'
      for p in "${cands[@]}"; do printf '| `%s` | 2026-10-01 | 34 |  |\n' "$p"; done
      for p in "${raws[@]}"; do printf '%s\n' "$p"; done
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
    printf '| `a.md` | 2026-11-04 | reached |  |\n'
  } >"$wb/_reachability.md"
}

rc=0
out=''
err=''

# run_in <dir> <command>...: run and capture / 実行して出力を取る
run_in() {
  local dir="$1"
  shift
  rc=0
  (cd "$dir" && "$@") >"$case_dir/out" 2>"$case_dir/err" </dev/null || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
}

# run_forget <args>...: the copy of forget.sh next to the fake close_gate.sh
# run_forget <引数>...: 偽の close_gate.sh の隣に置いた forget.sh の複製を呼ぶ
run_forget() { run_in "$case_dir" bash "$forget" "$@"; }

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
assert_err_lacks() { ! grep -qF -- "$1" <<<"$err" || flunk "stderr unexpectedly has: $1"; }
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
  : >"$wb/20261019-brief-x.md"
  : >"$wb/sub/report-y.md"
  : >"$wb/20261020-brief-z.md"
  : >"$mem/state_commander-proj-2.md"
  write_list 20261019-brief-x.md sub/report-y.md 20261020-brief-z.md -- "$mem/state_commander-proj-2.md"
  # Relative (as in the table), absolute, and the stale state file's absolute path.
  # 表のとおりの相対パス・絶対パス・古い状態ファイルの絶対パス。
  run_forget 20261019-brief-x.md sub/report-y.md "$wb/20261020-brief-z.md" "$mem/state_commander-proj-2.md"
  assert_exit 0
  assert_out_has "trashed $wb/20261019-brief-x.md"
  assert_out_has "trashed $wb/sub/report-y.md"
  assert_out_has "trashed $wb/20261020-brief-z.md"
  assert_out_has "trashed $mem/state_commander-proj-2.md"
  assert_gio_called "$wb/20261019-brief-x.md"
  assert_gio_called "$wb/sub/report-y.md"
  assert_gio_called "$wb/20261020-brief-z.md"
  assert_gio_called "$mem/state_commander-proj-2.md"
  assert_gio_calls 4
  assert_err_lacks 'ignored list row'
}

test_unnormalized_and_duplicate_arguments_match_once() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  run_forget "$wb/./sub/../b.md" b.md
  assert_exit 0
  assert_out_has "trashed $wb/b.md"
  assert_gio_calls 1
}

# ---------------------------------------------------------------------------
# 2. An unlisted path stops everything / 一覧に無いパスが混ざると何も動かさない
# ---------------------------------------------------------------------------
test_unlisted_path_moves_nothing() {
  new_case
  : >"$wb/b.md"
  : >"$wb/reached.md"
  : >"$wb/other.md"
  write_list b.md
  run_forget b.md other.md reached.md
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
  : >"$wb/b.md"
  : >"$case_dir/outside.md"
  ln -s "$case_dir/outside.md" "$wb/link.md"
  mkdir -p "$wb/olddir"
  write_list b.md link.md olddir
  run_forget link.md
  assert_exit 1
  assert_err_has 'refused link.md: symlink は消さない'
  run_forget olddir
  assert_exit 1
  assert_err_has 'refused olddir: ディレクトリは消さない'
  run_forget b.md link.md
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
  : >"$wb/b.md"
  write_list b.md
  touch -d '25 hours ago' "$wb/_reachability.md"
  run_forget b.md
  assert_exit 1
  assert_err_has 'refused b.md: 一覧が 25 時間前のもので、24 時間より古い'
  assert_err_has 'close_gate.sh --check --session <ID>'
  assert_gio_calls 0
  # The threshold can be changed / 閾値は変えられる
  run_in "$case_dir" env WTCLOSE_FORGET_MAX_AGE_HOURS=48 bash "$forget" b.md
  assert_exit 0
  assert_out_has "trashed $wb/b.md"
}

# ---------------------------------------------------------------------------
# 6. No gio: exit 2, nothing moved / gio が無いと終了コード 2 で何も動かさない
# ---------------------------------------------------------------------------
test_no_gio_moves_nothing() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  run_in "$case_dir" env "PATH=$root/nogio-bin" "$BASH" "$forget" b.md
  assert_exit 2
  assert_err_has 'gio が無い'
  assert_out_empty
  assert_gio_calls 0
  [ -e "$wb/b.md" ] || flunk 'b.md is gone'
}

# ---------------------------------------------------------------------------
# 7. No arguments: exit 2 / 引数が無いと終了コード 2
# ---------------------------------------------------------------------------
test_no_arguments_exit_2() {
  new_case
  write_list b.md
  run_forget
  assert_exit 2
  assert_err_has '引数が無い'
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# T1. Rows are taken verbatim / 一覧の行は変えずに取り出す
# ---------------------------------------------------------------------------
# "a.md" is still reached; a candidate named "a.md|old.md" must not authorize it.
# a.md はまだ辿られている。a.md|old.md という候補で a.md が許可されてはいけない。
test_pipe_in_listed_name_does_not_authorize_prefix() {
  new_case
  : >"$wb/a.md"
  write_list 'a.md|old.md'
  run_forget a.md
  assert_exit 1
  assert_err_has 'ignored list row: | `a.md|old.md` |'
  assert_err_has 'refused a.md: '
  assert_gio_calls 0
}

test_malformed_rows_are_ignored() {
  new_case
  : >"$wb/a.md"
  : >"$wb/c.md"
  : >"$wb/d.md"
  write_list -r '| ` a.md` | 2026-10-01 | 34 |  |' \
    -r '| `c.md`x | 2026-10-01 | 34 |  |' \
    -r '| `d.md | 2026-10-01 | 34 |  |'
  run_forget a.md c.md d.md
  assert_exit 1
  assert_err_has 'ignored list row: | ` a.md` |'
  assert_err_has 'ignored list row: | `c.md`x |'
  assert_err_has 'ignored list row: | `d.md |'
  assert_gio_calls 0
}

test_argument_with_pipe_or_backtick_is_refused() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  run_forget b.md 'b.md|x' 'b`.md'
  assert_exit 1
  assert_err_has 'refused b.md|x: | か ` を含むパスは受け付けない'
  assert_err_has 'refused b`.md: | か ` を含むパスは受け付けない'
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# T2. The list must not change while forget.sh runs / 一覧は途中で変わってはいけない
# ---------------------------------------------------------------------------
test_list_rewritten_while_reading_exit_2() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  export FAKE_STAT_BUMP_ON=2
  run_forget b.md
  assert_exit 2
  assert_err_has '一覧が読んでいる途中で書き換わった'
  assert_gio_calls 0
}

test_list_rewritten_before_trashing_exit_2() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  export FAKE_STAT_BUMP_ON=3
  run_forget b.md
  assert_exit 2
  assert_err_has '一覧が確かめている途中で書き換わった'
  assert_gio_calls 0
  [ -e "$wb/b.md" ] || flunk 'b.md is gone'
}

# ---------------------------------------------------------------------------
# R1. Rows must have the shape the gate writes / 表ごとの形でも確かめる
# ---------------------------------------------------------------------------
test_candidate_outside_workbench_is_ignored() {
  new_case
  : >"$case_dir/outside.md"
  : >"$vault/escape.md"
  write_list "$case_dir/outside.md" ../../escape.md
  run_forget "$case_dir/outside.md" "$vault/escape.md"
  assert_exit 1
  assert_err_has "ignored list row: | \`$case_dir/outside.md\` |"
  assert_err_has 'ignored list row: | `../../escape.md` |'
  assert_err_has "refused $case_dir/outside.md: "
  assert_err_has "refused $vault/escape.md: "
  assert_gio_calls 0
}

test_stale_row_outside_memory_or_not_state_is_ignored() {
  new_case
  mkdir -p "$mem/sub"
  : >"$case_dir/state_x.md"
  : >"$mem/notes.md"
  : >"$mem/sub/state_y.md"
  : >"$mem/state_z.txt"
  write_list -- "$case_dir/state_x.md" "$mem/notes.md" "$mem/sub/state_y.md" "$mem/state_z.txt"
  run_forget "$case_dir/state_x.md" "$mem/notes.md" "$mem/sub/state_y.md" "$mem/state_z.txt"
  assert_exit 1
  assert_err_has "ignored list row: | \`$case_dir/state_x.md\` |"
  assert_err_has "ignored list row: | \`$mem/notes.md\` |"
  assert_err_has "ignored list row: | \`$mem/sub/state_y.md\` |"
  assert_err_has "ignored list row: | \`$mem/state_z.txt\` |"
  assert_gio_calls 0
}

# A workbench path in the stale table, or a state file in the candidate table,
# is in the wrong table / 表を取り違えた行は捨てる
test_row_in_the_wrong_table_is_ignored() {
  new_case
  : >"$wb/b.md"
  : >"$mem/state_old.md"
  write_list "$mem/state_old.md" -- "$wb/b.md"
  run_forget b.md "$mem/state_old.md"
  assert_exit 1
  assert_err_has 'refused b.md: '
  assert_err_has "refused $mem/state_old.md: "
  assert_gio_calls 0
}

# ---------------------------------------------------------------------------
# Environment problems and failures / 環境の問題と途中の失敗
# ---------------------------------------------------------------------------
test_missing_list_exit_2() {
  new_case
  : >"$wb/b.md"
  run_forget b.md
  assert_exit 2
  assert_err_has '_reachability.md が無い'
  assert_gio_calls 0
}

test_where_failure_exit_2() {
  new_case
  : >"$wb/b.md"
  write_list b.md
  export FAKE_WHERE_FAIL=1
  run_forget b.md
  assert_exit 2
  assert_err_has 'workbench_dir を求められない'
  assert_gio_calls 0
}

test_gio_failure_midway_exit_3() {
  new_case
  : >"$wb/b.md"
  : >"$wb/c.md"
  : >"$wb/d.md"
  write_list b.md c.md d.md
  export FAKE_GIO_FAIL_ON="$wb/c.md"
  run_forget b.md c.md d.md
  assert_exit 3
  assert_out_has "trashed $wb/b.md"
  assert_err_has "gio trash が $wb/c.md で失敗した"
  assert_gio_calls 2
}

# ---------------------------------------------------------------------------
# R2. With the real close_gate.sh, the places cannot be redirected
# 本物の close_gate.sh と組むと、置き場は差し替えられない
# ---------------------------------------------------------------------------
# HOME points at the case, so the default vault ($HOME/Documents/Obsidian) is
# the fixture. WTCLOSE_VAULT points at another vault and must be ignored.
# HOME をケースに向けるので、既定の vault は fixture になる。WTCLOSE_VAULT は
# 別の vault に向け、forget.sh はそれを無視しなければならない。
test_real_close_gate_ignores_overrides() {
  new_case
  local home="$case_dir/home" repo="$case_dir/proj" other="$case_dir/other"
  vault="$home/Documents/Obsidian"
  wb="$vault/AgentMemory/workbench/proj"
  mkdir -p "$wb" "$vault/AgentMemory/proj" "$other/AgentMemory/workbench/proj" "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" commit -q --allow-empty -m init
  : >"$wb/b.md"
  write_list b.md
  # The other vault lists e.md / 別の vault は e.md を載せている
  : >"$other/AgentMemory/workbench/proj/e.md"
  cp "$wb/_reachability.md" "$other/AgentMemory/workbench/proj/_reachability.md"
  sed -i 's/`b.md`/`e.md`/' "$other/AgentMemory/workbench/proj/_reachability.md"
  run_in "$repo" env "HOME=$home" "WTCLOSE_VAULT=$other" bash "$real_forget" b.md
  assert_exit 0
  assert_out_has "trashed $wb/b.md"
  run_in "$repo" env "HOME=$home" "WTCLOSE_VAULT=$other" bash "$real_forget" "$other/AgentMemory/workbench/proj/e.md"
  assert_exit 1
  assert_gio_calls 1
  # Outside a git repository, close_gate.sh --where finds no places.
  # git リポジトリの外では、close_gate.sh --where は置き場を求められない。
  run_in "$case_dir" env "HOME=$home" bash "$real_forget" b.md
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
