#!/usr/bin/env bash
# Tests for precompact_checkpoint.sh / compact の前の控えを書く hook のテスト
#
# Every case builds its own fake vault, git repository and transcript under a
# temporary directory. HOME points there too, and the real close_gate.sh is
# linked into it, so the hook asks the real --where and WTCLOSE_VAULT keeps the
# answer inside the fixture. gh, git and herdr are fakes placed first on PATH.
# close_gate.sh itself keeps the real git through WTCLOSE_GIT.
# 各ケースは一時ディレクトリの下に、偽の vault・git リポジトリ・transcript を作る。
# HOME もそこへ向け、本物の close_gate.sh をリンクする。hook は本物の --where に
# 聞き、WTCLOSE_VAULT が答えを fixture の中に留める。gh・git・herdr は PATH の
# 先頭の偽物で、close_gate.sh だけは WTCLOSE_GIT で本物の git を使う。
#
# Usage / 使い方: bash .config/claude/scripts/tests/precompact_checkpoint_test.sh [name-filter]
#
# The fixtures contain literal "$" and quotes of raw transcript text.
# fixture は、transcript の生テキストの $ と引用符を文字どおりに書く。
# shellcheck disable=SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$script_dir/../precompact_checkpoint.sh"
real_gate="$script_dir/../../skills/wtclose/close_gate.sh"
filter="${1:-}"

root="$(mktemp -d)"
trap 'chmod -R u+w "$root"; rm -rf "$root"' EXIT

# Isolate from the user's environment / 利用者の環境から切り離す
real_git="$(command -v git)"
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export WTCLOSE_GIT="$real_git"
export WTCLOSE_PROJECT=proj
unset HERDR_ENV HERDR_PANE_ID WTCLOSE_VAULT
mkdir -p "$HOME/.claude/skills/wtclose"
ln -s "$real_gate" "$HOME/.claude/skills/wtclose/close_gate.sh"

# ---------------------------------------------------------------------------
# Fakes / 偽物
# FAKE_GH    : (unset) two PRs | empty | fail | hang
# FAKE_HERDR : (unset) answers | fail | hang
# FAKE_GIT   : (unset) answers | fail | hang
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_GH:-}" in
  fail) echo 'gh: boom' >&2; exit 1 ;;
  hang) exec sleep 60 ;;
  empty) echo '[]'; exit 0 ;;
esac
cat <<'JSON'
[{"number":801,"title":"feat: 一つ目","headRefName":"feat/one","isDraft":false},
 {"number":802,"title":"fix: 二つ目","headRefName":"fix/two","isDraft":true}]
JSON
EOF
cat >"$root/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_HERDR:-}" in
  fail) echo 'herdr: boom' >&2; exit 1 ;;
  hang) exec sleep 60 ;;
esac
case "$1 $2" in
  'agent list')
    cat <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list","agents":[
 {"name":"commander-fixture","pane_id":"w1:p1","agent_status":"working","cwd":"/work/main"},
 {"pane_id":"w2:p1","agent_status":"idle","cwd":"/work/nameless"}]}}
JSON
    ;;
  'agent get') echo '{"id":"cli:agent:get","result":{"agent":{"name":"commander-fixture","pane_id":"w1:p1"}}}' ;;
  *) exit 64 ;;
esac
EOF
cat >"$root/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_GIT:-}" in
  fail) echo 'git: boom' >&2; exit 1 ;;
  hang) exec sleep 60 ;;
esac
case "$1 $2" in
  'branch --show-current') echo 'feat/fixture' ;;
  'worktree list')
    printf 'worktree /work/main\nHEAD aaaa\nbranch refs/heads/main\n\n'
    printf 'worktree /work/feat one\nHEAD bbbb\nbranch refs/heads/feat/one\n\n'
    printf 'worktree /work/loose\nHEAD cccc\ndetached\n\n'
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$root/bin/gh" "$root/bin/herdr" "$root/bin/git"
export PATH="$root/bin:$PATH"

# ---------------------------------------------------------------------------
# Fixture builders / fixture を作る関数
# ---------------------------------------------------------------------------
case_dir=''
repo=''
wb=''
mem=''
transcript=''
out=''
rc=0

new_case() {
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  repo="$case_dir/repo"
  mem="$case_dir/vault/AgentMemory/proj"
  wb="$case_dir/vault/AgentMemory/workbench/proj"
  transcript="$case_dir/transcript.jsonl"
  out="$wb/_checkpoint-sess-1.md"
  export WTCLOSE_VAULT="$case_dir/vault"
  mkdir -p "$mem"
  "$real_git" init -q "$repo"
  # Raw JSON lines, with the escaped quotes a real transcript has.
  # 本物の transcript と同じく、引用符がエスケープされた JSON の行。
  cat >"$transcript" <<'EOF'
{"type":"user","message":{"content":"#101 と #202 を見て"}}
{"type":"assistant","message":{"content":"#101 はもう閉じた。https://app.clickup.com/t/86abc123 を更新する"}}
{"type":"tool_use","input":{"command":"herdr agent prompt \"commander-fixture\" \"報告\""}}
{"type":"tool_use","input":{"command":"herdr agent wait claude-worker > /tmp/out"}}
{"type":"tool_use","input":{"command":"herdr agent start \"claude-$slug\" --kind claude"}}
{"type":"tool_use","input":{"command":"herdr agent wait --until done"}}
EOF
}

# hook_input [session_id] [transcript]: the hook input JSON
# hook_input [session_id] [transcript]: hook 入力の JSON
hook_input() {
  jq -n --arg s "${1-sess-1}" --arg t "${2-$transcript}" --arg c "$repo" \
    '{session_id: $s, transcript_path: $t, cwd: $c, hook_event_name: "PreCompact", trigger: "auto", custom_instructions: null}'
}

run_hook() {
  rc=0
  printf '%s' "$1" | bash "$hook" 2>"$case_dir/stderr" || rc=$?
}

# ---------------------------------------------------------------------------
# Assertions / 判定
# ---------------------------------------------------------------------------
passed=0
failures=0
current=''

fail() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  exit 1
}

assert_exit_0() {
  [ "$rc" -eq 0 ] || fail "終了コードが 0 でない: $rc"
}

assert_written() {
  [ -f "$out" ] || fail "控えが書かれていない: $out"
}

assert_has() {
  grep -qF -- "$1" "$out" || fail "控えに無い: $1"$'\n'"$(cat "$out")"
}

assert_lacks() {
  if grep -qF -- "$1" "$out"; then fail "控えに余計なものがある: $1"$'\n'"$(cat "$out")"; fi
}

# Nothing, not even a temporary file, may stay in the workbench.
# 作業記憶には、一時ファイルも含めて何も残らない。
assert_nothing_written() {
  if [ -d "$wb" ] && [ -n "$(ls -A "$wb")" ]; then fail "何か書かれた: $(ls -A "$wb")"; fi
}

# ---------------------------------------------------------------------------
# Cases / ケース
# ---------------------------------------------------------------------------
test_writes_every_section() {
  new_case
  cat >"$mem/state_commander-fixture.md" <<'EOF'
---
name: state-commander-fixture
metadata:
  kind: state
  as_of: 2026-11-01 09:00
---

本文の as_of: 2000-01-01 00:00 は読まない
EOF
  HERDR_PANE_ID=w1:p1 run_hook "$(hook_input)"
  assert_exit_0
  assert_written
  # The four keys the gate requires, and the rest of the frontmatter
  # 検問が必須とする 4 つの鍵と、frontmatter の残り
  assert_has 'type: agent-workbench'
  assert_has 'kind: checkpoint'
  assert_has 'unit: "feat/fixture"'
  grep -qE '^created: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$out" || fail 'created の形が違う'
  assert_has 'session_id: sess-1'
  grep -qE '^as_of: [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$' "$out" || fail 'as_of の形が違う'
  assert_has 'trigger: auto'
  assert_has '未回答の質問は拾えない'
  assert_has '## セッション'
  assert_has "- cwd: $repo"
  assert_has '- pane: w1:p1'
  assert_has '- agent の名前: commander-fixture'
  assert_has '## 稼働中の agent(herdr agent list)'
  assert_has '- commander-fixture: working、/work/main'
  assert_has '- w2:p1: idle、/work/nameless'
  assert_has '## open の PR(gh pr list --state open)'
  assert_has '- #801 feat: 一つ目(feat/one、ready)'
  assert_has '- #802 fix: 二つ目(fix/two、draft)'
  assert_has '## worktree(git worktree list)'
  assert_has '- /work/main [main]'
  assert_has '- /work/feat one [feat/one]'
  assert_has '- /work/loose [detached]'
  assert_has '## 会話に出た番号(transcript の末尾 400 行から機械抽出)'
  assert_has '- Issue / PR: #101, #202'
  assert_has '- ClickUp: 86abc123'
  # The escaped name is found; names cut by a variable or a flag are dropped.
  # エスケープされた名前を拾い、変数やフラグで切れたものは捨てる。
  assert_has '- herdr の agent: claude-worker, commander-fixture'
  assert_has '## 次に読むもの'
  assert_has "- 状態ファイル: $mem/state_commander-fixture.md(as_of: 2026-11-01 09:00)"
  assert_lacks '未確認'
}

test_gh_failure_still_writes() {
  new_case
  HERDR_PANE_ID=w1:p1 FAKE_GH=fail run_hook "$(hook_input)"
  assert_exit_0
  assert_written
  assert_has '- PR の状態は未確認('
  assert_lacks '#801'
  assert_has '- commander-fixture: working、/work/main'
  assert_has '- /work/main [main]'
}

test_every_command_failing_still_writes() {
  new_case
  HERDR_PANE_ID=w1:p1 FAKE_GH=fail FAKE_HERDR=fail FAKE_GIT=fail run_hook "$(hook_input)"
  assert_exit_0
  assert_written
  assert_has 'unit: "session"'
  assert_has '- agent の名前: 未確認('
  assert_has '- 状態ファイル: 未確認('
  [ "$(grep -c '^- 未確認(' "$out")" -eq 2 ] || fail 'agent と worktree の節が未確認になっていない'
}

test_no_session_id_writes_nothing() {
  new_case
  run_hook "$(jq -n --arg c "$repo" '{cwd: $c, trigger: "auto"}')"
  assert_exit_0
  assert_nothing_written
}

test_bad_input_writes_nothing() {
  new_case
  run_hook 'not json'
  assert_exit_0
  assert_nothing_written
  run_hook '[]'
  assert_exit_0
  assert_nothing_written
  # session_id is part of a file name / session_id はファイル名の一部になる
  run_hook "$(hook_input '../../escape')"
  assert_exit_0
  assert_nothing_written
  [ ! -e "$case_dir/vault/AgentMemory/escape.md" ] || fail 'session_id で置き場の外に書いた'
}

test_no_vault_writes_nothing() {
  new_case
  rm -rf "$case_dir/vault/AgentMemory"
  run_hook "$(hook_input)"
  assert_exit_0
  [ ! -e "$case_dir/vault/AgentMemory" ] || fail 'vault が無いのに作った'
}

test_outside_herdr() {
  new_case
  run_hook "$(hook_input)"
  assert_exit_0
  assert_has '- pane: herdr の外'
  assert_has '- agent の名前: なし'
  assert_has '- 状態ファイル: なし'
}

test_no_state_file_reads_none() {
  new_case
  HERDR_PANE_ID=w1:p1 run_hook "$(hook_input)"
  assert_exit_0
  assert_has '- 状態ファイル: なし'
}

test_unreadable_transcript_is_unknown() {
  new_case
  run_hook "$(hook_input sess-1 "$case_dir/missing.jsonl")"
  assert_exit_0
  assert_written
  assert_has '- Issue / PR: 未確認('
  assert_has '- ClickUp: 未確認('
  assert_has '- herdr の agent: 未確認('
}

test_empty_answers_read_none() {
  new_case
  : >"$transcript"
  FAKE_GH=empty run_hook "$(hook_input)"
  assert_exit_0
  grep -A2 '^## open の PR' "$out" | grep -qxF -- '- なし' || fail 'PR の節が「なし」でない'
  assert_has '- Issue / PR: なし'
  assert_has '- ClickUp: なし'
  assert_has '- herdr の agent: なし'
}

test_keeps_the_30_most_recent_numbers() {
  new_case
  for n in $(seq 100 139); do echo "{\"text\":\"#$n\"}"; done >"$transcript"
  echo '{"text":"#100 にまた触れた"}' >>"$transcript"
  run_hook "$(hook_input)"
  assert_exit_0
  line="$(grep '^- Issue / PR: ' "$out")"
  [[ "$line" == '- Issue / PR: #100, #139, #138,'* ]] || fail "新しい順でない: $line"
  [ "$(grep -o '#[0-9]*' <<<"$line" | wc -l)" -eq 30 ] || fail "30 件でない: $line"
  [[ "$line" == *'#111'* ]] || fail "30 件目が無い: $line"
  [[ "$line" != *'#110'* ]] || fail "31 件目が残った: $line"
}

test_reads_only_the_last_400_lines() {
  new_case
  echo '{"text":"#555"}' >"$transcript"
  for _ in $(seq 1 400); do echo '{"text":"#777"}'; done >>"$transcript"
  run_hook "$(hook_input)"
  assert_exit_0
  assert_has '- Issue / PR: #777'
  assert_lacks '#555'
}

test_overwrites_and_leaves_no_temporary_file() {
  new_case
  run_hook "$(hook_input)"
  FAKE_GH=fail run_hook "$(hook_input)"
  assert_exit_0
  assert_has '- PR の状態は未確認('
  assert_lacks '#801'
  [ "$(ls -A "$wb")" = '_checkpoint-sess-1.md' ] || fail "控え以外が残った: $(ls -A "$wb")"
}

test_keeps_checkpoints_of_other_sessions() {
  new_case
  mkdir -p "$wb"
  echo old >"$wb/_checkpoint-old-session.md"
  run_hook "$(hook_input)"
  assert_exit_0
  assert_written
  [ "$(cat "$wb/_checkpoint-old-session.md")" = 'old' ] || fail '別のセッションの控えを触った'
}

test_unwritable_workbench_still_exits_0() {
  new_case
  mkdir -p "$wb"
  chmod 555 "$wb"
  run_hook "$(hook_input)"
  chmod 755 "$wb"
  assert_exit_0
  assert_nothing_written
}

# The hook entry has 30 seconds. Hanging commands must stop at their own
# timeout and leave time to write, which only holds when they run in parallel.
# hook の持ち時間は 30 秒。止まったコマンドは各自の timeout で切れ、控えを書く
# 時間が残らなければならない。これは並列に走るときだけ成り立つ。
test_hanging_commands_fit_the_hook_timeout() {
  new_case
  local started elapsed
  started="$(date +%s)"
  HERDR_PANE_ID=w1:p1 FAKE_GH=hang FAKE_HERDR=hang FAKE_GIT=hang run_hook "$(hook_input)"
  elapsed="$(($(date +%s) - started))"
  assert_exit_0
  assert_written
  assert_has '- PR の状態は未確認('
  [ "$elapsed" -lt 20 ] || fail "時間がかかりすぎた: ${elapsed} 秒"
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
