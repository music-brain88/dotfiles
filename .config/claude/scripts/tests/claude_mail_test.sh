#!/usr/bin/env bash
# Tests for claude_mail.sh / 別の機械の司令塔への呼び鈴 claude_mail.sh のテスト
#
# The real atuin is never called: a fake one is placed first on PATH, and HOME
# points at a temporary directory, so the user's synced data and the real vault
# are never touched. claude_mail.sh and the real close_gate.sh are copied into a
# temporary ~/.claude, because the places always come from close_gate.sh --where.
# 実物の atuin は一度も呼ばない。偽の atuin を PATH の先頭に置き、HOME も一時
# ディレクトリに向けるので、利用者の同期データにも実物の vault にも触らない。
# 置き場は常に close_gate.sh --where で求めるので、claude_mail.sh と本物の
# close_gate.sh を、一時ディレクトリの ~/.claude に複製して使う。
#
# Usage / 使い方: bash .config/claude/scripts/tests/claude_mail_test.sh [name-filter]
#
# The test functions are called by name at the end of the file, and some
# expectations contain literal "$" and "~".
# テスト関数はファイルの末尾で名前から呼ぶ。期待値には文字どおりの「$」と「~」がある。
# shellcheck disable=SC2329,SC2016
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$(cd "$script_dir/../.." && pwd)"
filter="${1:-}"

root="$(mktemp -d)"
trap 'chmod -R u+w "$root" 2>/dev/null || true; rm -rf "$root"' EXIT
root="$(realpath "$root")"

# Isolate from the user's environment / 利用者の環境から切り離す
export HOME="$root/home"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset WTCLOSE_VAULT WTCLOSE_PROJECT WTCLOSE_GIT WTCLOSE_NOW
unset CLAUDE_MAIL_SYNC_TIMEOUT CLAUDE_MAIL_KV_TIMEOUT CLAUDE_MAIL_TOTAL_TIMEOUT

mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/skills/wtclose" "$root/bin"
cp "$config_dir/scripts/claude_mail.sh" "$HOME/.claude/scripts/claude_mail.sh"
cp "$config_dir/skills/wtclose/close_gate.sh" "$HOME/.claude/skills/wtclose/close_gate.sh"
mail="$HOME/.claude/scripts/claude_mail.sh"
vault="$HOME/Documents/Obsidian"

# ---------------------------------------------------------------------------
# Fake atuin / 偽の atuin
# FAKE_LOCAL  : the data of one machine / 1 台の機械のデータ
# FAKE_REMOTE : the sync server shared by the machines / 機械どうしが共有するサーバー
# A value set on one machine is readable on another only after both have run
# "atuin sync", as observed with atuin 18.24.4 on 2026-11-24 (#826).
# 片方の機械で置いた値は、両方が atuin sync を実行した後にだけ、もう片方で読める
# (2026-11-24 に atuin 18.24.4 で観測。#826)。
# FAKE_SYNC   : ok | fail | hang | quiet (exit 0 without "Sync complete!")
# FAKE_KV_FAIL: the kv subcommand that fails / 失敗させる kv のサブコマンド
# FAKE_KV_HANG: the kv subcommand that hangs / 止まらせる kv のサブコマンド
# Every call appends its arguments to $FAKE_LOCAL/calls.
# 呼ばれるたびに、引数を $FAKE_LOCAL/calls に足す。
# ---------------------------------------------------------------------------
cat >"$root/bin/atuin" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$FAKE_LOCAL/state" "$FAKE_LOCAL/pending" "$FAKE_REMOTE"
printf '%s\n' "$*" >>"$FAKE_LOCAL/calls"
apply() { # apply <op file>
  local op ns key
  { IFS= read -r op; IFS= read -r ns; IFS= read -r key; } <"$1"
  mkdir -p "$FAKE_LOCAL/state/$ns"
  if [ "$op" = set ]; then tail -n +4 "$1" >"$FAKE_LOCAL/state/$ns/$key"; else rm -f "$FAKE_LOCAL/state/$ns/$key"; fi
}
next() { printf '%s/%06d' "$1" "$(($(find "$1" -type f | wc -l) + 1))"; }
if [ "$1" = sync ]; then
  case "${FAKE_SYNC:-ok}" in
    ok) ;;
    fail) printf 'Error: could not connect to the server\nLocation: somewhere\n' >&2; exit 1 ;;
    hang) exec sleep 60 ;;
    quiet) echo 'Nothing was done'; exit 0 ;;
  esac
  for f in "$FAKE_LOCAL/pending"/*; do
    [ ! -f "$f" ] || mv "$f" "$(next "$FAKE_REMOTE")"
  done
  rm -rf "$FAKE_LOCAL/state"
  for f in "$FAKE_REMOTE"/*; do [ ! -f "$f" ] || apply "$f"; done
  echo '0/0 up/down to record store'
  echo 'Sync complete! 0 items in history database, force: false'
  exit 0
fi
[ "$1" = kv ] || exit 64
sub="$2"
shift 2
[ "${FAKE_KV_FAIL:-}" != "$sub" ] || { echo "Error: kv $sub is broken" >&2; exit 1; }
[ "${FAKE_KV_HANG:-}" != "$sub" ] || exec sleep 60
ns=default
key=''
pos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n) ns="$2"; shift ;;
    -k) [ "$sub" = set ] || exit 2; key="$2"; shift ;;
    *) pos+=("$1") ;;
  esac
  shift
done
case "$sub" in
  set)
    [ -n "$key" ] || exit 2
    op="$(next "$FAKE_LOCAL/pending")"
    printf 'set\n%s\n%s\n%s\n' "$ns" "$key" "${pos[0]}" >"$op"
    apply "$op"
    ;;
  get) [ ! -f "$FAKE_LOCAL/state/$ns/${pos[0]}" ] || cat "$FAKE_LOCAL/state/$ns/${pos[0]}" ;;
  delete)
    op="$(next "$FAKE_LOCAL/pending")"
    printf 'delete\n%s\n%s\n' "$ns" "${pos[0]}" >"$op"
    apply "$op"
    ;;
  list) [ ! -d "$FAKE_LOCAL/state/$ns" ] || ls "$FAKE_LOCAL/state/$ns" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$root/bin/atuin"
export PATH="$root/bin:$PATH"
[ "$(command -v atuin)" = "$root/bin/atuin" ] || { echo 'the fake atuin is not first on PATH' >&2; exit 1; }

# ---------------------------------------------------------------------------
# PATH without atuin / atuin の無い PATH
# Only the commands the scripts need are linked, so "atuin is missing" can be
# reproduced on a machine that has atuin.
# 必要なコマンドだけを置き、atuin がある機械でも「atuin が無い」を再現する。
# ---------------------------------------------------------------------------
mkdir -p "$root/noatuin-bin" "$root/notimeout-bin"
for c in bash env git sed sort date timeout realpath dirname basename mktemp rm cat grep awk tr head jq; do
  p="$(command -v "$c" 2>/dev/null || true)"
  case "$p" in
    /*)
      ln -s "$p" "$root/noatuin-bin/$c"
      [ "$c" = timeout ] || ln -s "$p" "$root/notimeout-bin/$c"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Fixtures / fixture
# ---------------------------------------------------------------------------
case_dir=''
alpha=''
beta=''
doc=''

# new_case: a vault, the repositories "alpha" (the sender's) and "beta" (the
# receiver's), one document, and two machines A and B around one server.
# vault と、送る側のリポジトリ alpha・受け取る側の beta・文書 1 枚と、1 つの
# サーバーにつながる 2 台の機械 A・B を作る。
new_case() {
  local r
  case_dir="$(mktemp -d "$root/case.XXXXXX")"
  rm -rf "$vault"
  alpha="$case_dir/alpha"
  beta="$case_dir/beta"
  for r in alpha beta; do
    mkdir -p "$case_dir/$r" "$vault/AgentMemory/$r" "$vault/AgentMemory/workbench/$r"
    git -C "$case_dir/$r" init -q -b main
    git -C "$case_dir/$r" commit -q --allow-empty -m init
  done
  doc="$vault/AgentMemory/workbench/alpha/20261124-handoff-x.md"
  printf -- '---\ntype: agent-workbench\nkind: handoff\n---\n\n本文\n' >"$doc"
  export FAKE_REMOTE="$case_dir/server"
  on_machine A
}

on_machine() { export FAKE_LOCAL="$case_dir/machine-$1"; }

out=''
err=''
rc=0

# run_in <dir> <command>... / run <dir> <arguments of claude_mail.sh>...
run_in() {
  local dir="$1"
  shift
  rc=0
  (cd "$dir" && "$@") >"$case_dir/out" 2>"$case_dir/err" </dev/null || rc=$?
  out="$(cat "$case_dir/out")"
  err="$(cat "$case_dir/err")"
}
run() {
  local dir="$1"
  shift
  run_in "$dir" bash "$mail" "$@"
}

# raw_set <namespace> <key> <value>: a value written by hand, already synced.
# 手で書かれて、同期も済んだ値。
raw_set() {
  atuin kv set -n "$1" -k "$2" "$3"
  atuin sync >/dev/null
}

sent_key() { sed -n 's/^sent [^ ]* //p' <<<"$1"; }
calls() { cat "$FAKE_LOCAL/calls" 2>/dev/null || true; }
lines() { grep -c '' <<<"$1" || true; }

current=''
failures=0
passed=0

flunk() {
  printf 'FAIL %s: %s\n' "$current" "$1"
  printf '  exit=%s\n  stdout:\n    %s\n  stderr:\n    %s\n' "$rc" "${out//$'\n'/$'\n'    }" "${err//$'\n'/$'\n'    }"
  exit 1
}
assert_exit() { [ "$rc" -eq "$1" ] || flunk "exit code: want $1, got $rc"; }
assert_out_has() { grep -qF -- "$1" <<<"$out" || flunk "stdout lacks: $1"; }
assert_out_lacks() { ! grep -qF -- "$1" <<<"$out" || flunk "stdout unexpectedly has: $1"; }
assert_err_has() { grep -qF -- "$1" <<<"$err" || flunk "stderr lacks: $1"; }
assert_no_out() { [ -z "$out" ] || flunk 'stdout must be empty'; }
assert_no_err() { [ -z "$err" ] || flunk 'stderr must be empty'; }
assert_one_err_line() { [ -n "$err" ] && [ "$(lines "$err")" -eq 1 ] || flunk 'stderr must be one line'; }
# Nothing was written or synced / 何も置かれず、同期もされていない
assert_untouched() {
  ! grep -qE '^(sync|kv (set|delete))' <<<"$(calls)" || flunk "atuin was called: $(calls)"
}

# ---------------------------------------------------------------------------
# send, list, ack / 送る・読む・消す
# ---------------------------------------------------------------------------
test_send_list_ack_across_two_machines() {
  new_case
  run "$alpha" send commander-beta "$doc" 'この文書を読んでほしい'
  assert_exit 0
  assert_no_err
  local key
  key="$(sent_key "$out")"
  [[ "$key" =~ ^[0-9]{8}-[0-9]{6}-commander-alpha-[0-9a-f]{8}$ ]] || flunk "unexpected key: $key"
  [ "$(calls | sed -n 1p)" = "$(calls | grep '^kv set -n mail-commander-beta -k ')" ] || flunk 'set must come first'
  [ "$(calls | sed -n 2p)" = 'sync' ] || flunk 'sync must follow set'
  [ "$(lines "$(calls)")" -eq 2 ] || flunk "unexpected calls: $(calls)"

  on_machine B
  run "$beta" list
  assert_exit 0
  assert_no_err
  [ "$(lines "$out")" -eq 1 ] || flunk 'one bell must be one line'
  assert_out_has "呼び鈴 $key 宛先=commander-beta 差出人=commander-alpha 時刻=20"
  assert_out_has "文書=$doc 用件=この文書を読んでほしい"
  assert_out_has "bash ~/.claude/scripts/claude_mail.sh ack commander-beta $key"

  run "$beta" ack commander-beta "$key"
  assert_exit 0
  assert_no_err
  [ "$out" = "acked commander-beta $key" ] || flunk 'unexpected stdout'
  [ "$(calls | tail -n 1)" = 'sync' ] || flunk 'ack must sync at the end'
  run "$beta" list
  assert_exit 0
  assert_no_out
  [ -f "$doc" ] || flunk 'the document must stay'

  on_machine A
  run "$alpha" list --to commander-beta
  assert_exit 0
  assert_no_out
}

test_list_syncs_before_reading() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  on_machine B
  run "$beta" list
  assert_exit 0
  assert_out_has '用件=用件'
  [ "$(calls | sed -n 1p)" = 'sync' ] || flunk 'the first call must be sync'
  [ "$(calls | sed -n 2p)" = 'kv list -n mail-commander-beta' ] || flunk 'list must come after sync'
}

test_list_is_silent_without_bells() {
  new_case
  run "$beta" list
  assert_exit 0
  assert_no_out
  assert_no_err
}

test_list_reads_only_its_own_address() {
  new_case
  run "$beta" send commander-alpha "$doc" 'alpha あて'
  run "$alpha" send commander-beta "$doc" 'beta あて'
  run "$beta" list
  assert_out_has 'beta あて'
  assert_out_lacks 'alpha あて'
  run "$beta" list --to commander-alpha
  assert_out_has 'alpha あて'
  assert_out_lacks 'beta あて'
}

test_list_prints_oldest_first() {
  new_case
  raw_set mail-commander-beta 20261124-090016-commander-alpha-00000002 $'v1\tcommander-alpha\t2026-11-24T09:00:16+0900\tAgentMemory/workbench/alpha/20261124-handoff-x.md\t後'
  raw_set mail-commander-beta 20261124-090015-commander-alpha-00000009 $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/alpha/20261124-handoff-x.md\t先'
  run "$beta" list
  assert_exit 0
  [[ "$(sed -n 1p <<<"$out")" == *'用件=先 '* ]] || flunk 'the older bell must come first'
  [[ "$(sed -n 2p <<<"$out")" == *'用件=後 '* ]] || flunk 'the newer bell must come second'
}

# fake_clock: a date in $case_dir/bin whose "now" is $FAKE_EPOCH.
# 現在時刻が $FAKE_EPOCH になる date を $case_dir/bin に置く。
fake_clock() {
  mkdir -p "$case_dir/bin"
  printf '#!/usr/bin/env bash\n[[ " $* " == *" -d "* ]] && exec %s "$@"\nexec %s -d "@$FAKE_EPOCH" "$@"\n' \
    "$(command -v date)" "$(command -v date)" >"$case_dir/bin/date"
  chmod +x "$case_dir/bin/date"
}

# Machines in different time zones: the order is the order of sending, and the
# time shown keeps the sender's own offset.
# タイムゾーンの違う機械から送っても、並びは送った順になり、表示する時刻は差出人の
# 時差のまま残る。
test_order_does_not_depend_on_the_time_zone() {
  new_case
  fake_clock
  FAKE_EPOCH=1795478415 run_in "$alpha" env TZ=JST-9 "PATH=$case_dir/bin:$PATH" bash "$mail" send commander-beta "$doc" '先'
  assert_exit 0
  FAKE_EPOCH=1795478425 run_in "$alpha" env TZ=UTC0 "PATH=$case_dir/bin:$PATH" bash "$mail" send commander-beta "$doc" '後'
  assert_exit 0
  run "$beta" list
  assert_exit 0
  [[ "$(sed -n 1p <<<"$out")" == *'時刻=2026-11-24T09:00:15+0900 '*'用件=先 '* ]] || flunk 'the bell sent first must come first'
  [[ "$(sed -n 2p <<<"$out")" == *'時刻=2026-11-24T00:00:25+0000 '*'用件=後 '* ]] || flunk 'the bell sent later must come second'
}

test_two_sends_in_the_same_second_do_not_collide() {
  new_case
  fake_clock
  export FAKE_EPOCH=1795478415 # 2026-11-24T00:00:15Z
  local k1 k2
  run_in "$alpha" env "PATH=$case_dir/bin:$PATH" bash "$mail" send commander-beta "$doc" '1 通目'
  assert_exit 0
  k1="$(sent_key "$out")"
  run_in "$alpha" env "PATH=$case_dir/bin:$PATH" bash "$mail" send commander-beta "$doc" '2 通目'
  assert_exit 0
  k2="$(sent_key "$out")"
  [[ "$k1" == 20261124-000015-* && "$k2" == 20261124-000015-* ]] || flunk "the fake date did not take effect: $k1 $k2"
  [ "$k1" != "$k2" ] || flunk 'the keys collide'
  run "$beta" list
  [ "$(lines "$out")" -eq 2 ] || flunk 'both bells must be there'
}

test_suffixed_commanders_read_the_plain_address() {
  new_case
  run "$alpha" send commander-beta-2 "$doc" '用件'
  assert_exit 1
  assert_err_has '宛先は herdr の名前ではなく、commander-<--where project> で書く'
  assert_untouched
}

# ---------------------------------------------------------------------------
# Values / 値
# ---------------------------------------------------------------------------
test_subject_round_trips_with_separators_and_japanese() {
  new_case
  local subject
  for subject in \
    'a|b,c;d:e=f' \
    '{"json": "風", "k": [1]}' \
    "シングル'とダブル\"と \`バッククォート\` と \$HOME と \\n" \
    '--先頭がハイフン' \
    '日本語と  二重の空白と末尾の空白 ' \
    '用件=を含む | 読んで対応したら: を含む'; do
    new_case
    run "$alpha" send commander-beta "$doc" "$subject"
    assert_exit 0
    on_machine B
    run "$beta" list
    assert_exit 0
    [ "$(lines "$out")" -eq 1 ] || flunk 'one bell must be one line'
    assert_out_has "用件=$subject | 読んで対応したら: bash"
  done
}

test_value_holds_no_body_and_a_vault_relative_path() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local value
  value="$(cat "$FAKE_LOCAL/state/mail-commander-beta/$(sent_key "$out")")"
  [ "$(lines "$value")" -eq 1 ] || flunk 'the value must be one line'
  [[ "$value" == v1$'\t'commander-alpha$'\t'20*$'\t'AgentMemory/workbench/alpha/20261124-handoff-x.md$'\t'用件 ]] || flunk "unexpected value: $value"
  [[ "$value" != *本文* && "$value" != *"$HOME"* ]] || flunk "the value leaks the body or a local path: $value"
}

test_subject_with_a_tab_written_by_hand_is_not_cut() {
  new_case
  raw_set mail-commander-beta 20261124-090015-commander-alpha-00000001 $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/alpha/20261124-handoff-x.md\t前\t\t後\033[31m'
  run "$beta" list
  assert_exit 0
  assert_out_has '用件=前  後 [31m'
}

test_subject_refusals() {
  new_case
  local bad
  for bad in '' '   ' $'改行\nあり' $'タブ\tあり' $'制御\033[31m文字' "$(printf 'あ%.0s' $(seq 1 201))"; do
    run "$alpha" send commander-beta "$doc" "$bad"
    assert_exit 1
    assert_one_err_line
    assert_err_has '用件を拒否した'
    assert_no_out
    assert_untouched
  done
  run "$alpha" send commander-beta "$doc" "$(printf 'あ%.0s' $(seq 1 200))"
  assert_exit 0
}

test_broken_values_are_shown_and_can_be_acked() {
  new_case
  local i=0 key value
  for value in \
    'plain text' \
    $'v2\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/a.md\t用件' \
    $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/a.md' \
    $'v1\tsomeone\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/a.md\t用件' \
    $'v1\tcommander-alpha\tyesterday\tAgentMemory/workbench/a.md\t用件' \
    $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/../../x.md\t用件' \
    $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\t/etc/passwd\t用件' \
    $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/a.md\t用件\n2 行目'; do
    new_case
    i=$((i + 1))
    key="20261124-09001$i-commander-alpha-00000001"
    raw_set mail-commander-beta "$key" "$value"
    run "$beta" list
    assert_exit 0
    [ "$(lines "$out")" -eq 1 ] || flunk "value $i must be shown as one line"
    assert_out_has "呼び鈴 $key 宛先=commander-beta 値の形が合わない"
    assert_out_lacks 'passwd'
    run "$beta" ack commander-beta "$key"
    assert_exit 0
  done
}

test_malformed_key_is_reported_on_stderr_only() {
  new_case
  raw_set mail-commander-beta 'handmade' 'x'
  run "$beta" list
  assert_exit 0
  assert_no_out
  assert_one_err_line
  assert_err_has '形の合わないキーがある: handmade'
}

# ---------------------------------------------------------------------------
# Documents / 文書
# ---------------------------------------------------------------------------
test_missing_body_is_shown_and_the_bell_stays() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local key
  key="$(sent_key "$out")"
  rm "$doc"
  on_machine B
  run "$beta" list
  assert_exit 0
  assert_out_has "文書=$doc (本文がまだ届いていない。届くまで ack しない) 用件=用件"
  assert_out_lacks 'claude_mail.sh ack'
  printf '本文\n' >"$doc"
  run "$beta" list
  assert_out_lacks 'まだ届いていない'
  assert_out_has "claude_mail.sh ack commander-beta $key"
}

# The receiver checks the real path too: a link in its own workbench may point
# anywhere. The bell stays, but neither the path nor the ack is offered.
# 受け取る側も実体のパスを確かめる。自分の作業記憶の中のリンクは、どこでも指せる
# ためである。呼び鈴は残すが、パスも ack の案内も出さない。
test_document_pointing_outside_is_not_offered_to_the_reader() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local key target
  key="$(sent_key "$out")"
  printf 'x\n' >"$case_dir/outside.md"
  printf 'x\n' >"$vault/AgentMemory/alpha/memory.md"
  on_machine B
  for target in "$case_dir/outside.md" "$vault/AgentMemory/alpha/memory.md"; do
    ln -sfn "$target" "$doc"
    run "$beta" list
    assert_exit 0
    assert_no_err
    [ "$(lines "$out")" -eq 1 ] || flunk 'one bell must be one line'
    assert_out_has "呼び鈴 $key 宛先=commander-beta"
    assert_out_has '文書が作業記憶の外を指している。読まない'
    assert_out_lacks '文書='
    assert_out_lacks "$target"
    assert_out_lacks 'claude_mail.sh ack'
    assert_out_lacks 'まだ届いていない'
  done
  # A folder that is a link out of the workbench / 作業記憶の外を指すフォルダ
  mkdir -p "$case_dir/elsewhere"
  printf 'x\n' >"$case_dir/elsewhere/${doc##*/}"
  mv "${doc%/*}" "$case_dir/kept"
  ln -s "$case_dir/elsewhere" "${doc%/*}"
  run "$beta" list
  assert_exit 0
  assert_out_has '文書が作業記憶の外を指している。読まない'
  assert_out_lacks '文書='
  # The bell was kept all along / 呼び鈴は残っている
  rm "${doc%/*}"
  mv "$case_dir/kept" "${doc%/*}"
  ln -sfn ../beta/real.md "$doc"
  printf 'x\n' >"$vault/AgentMemory/workbench/beta/real.md"
  run "$beta" list
  assert_out_has "文書=$doc 用件=用件"
  assert_out_has "claude_mail.sh ack commander-beta $key"
}

test_document_that_is_not_a_regular_md_is_not_offered_to_the_reader() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  printf 'x\n' >"$vault/AgentMemory/workbench/alpha/note.txt"
  ln -sfn note.txt "$doc"
  run "$beta" list
  assert_exit 0
  assert_out_has '文書が通常の md ファイルではない。読まない'
  assert_out_lacks '文書='
  assert_out_lacks 'claude_mail.sh ack'
  rm "$doc"
  mkdir "$doc"
  run "$beta" list
  assert_out_has '文書が通常の md ファイルではない。読まない'
  rmdir "$doc"
  ln -s nowhere.md "$doc"
  run "$beta" list
  assert_out_has '文書が実在しないファイルを指している。読まない'
  assert_out_lacks '文書='
  assert_out_lacks 'まだ届いていない'
}

test_document_refusals() {
  new_case
  printf 'x\n' >"$case_dir/outside.md"
  printf 'x\n' >"$vault/AgentMemory/alpha/memory.md"
  printf 'x\n' >"$vault/AgentMemory/workbench/alpha/note.txt"
  mkdir -p "$vault/AgentMemory/workbench/alpha/dir.md" "$vault/AgentMemory/workbench-evil"
  printf 'x\n' >"$vault/AgentMemory/workbench-evil/x.md"
  ln -s "$case_dir/outside.md" "$vault/AgentMemory/workbench/alpha/link.md"
  local bad
  for bad in "$case_dir/outside.md" "$vault/AgentMemory/alpha/memory.md" \
    "$vault/AgentMemory/workbench/alpha/note.txt" "$vault/AgentMemory/workbench/alpha/dir.md" \
    "$vault/AgentMemory/workbench-evil/x.md" "$vault/AgentMemory/workbench/alpha/link.md" \
    "$vault/AgentMemory/workbench/alpha/../../alpha/memory.md" \
    "$vault/AgentMemory/workbench/alpha/none.md" ''; do
    run "$alpha" send commander-beta "$bad" '用件'
    assert_exit 1
    assert_one_err_line
    assert_err_has '文書を拒否した'
    assert_no_out
    assert_untouched
  done
}

test_document_may_be_relative_and_of_another_project() {
  new_case
  printf 'x\n' >"$vault/AgentMemory/workbench/beta/日本語 の名前.md"
  (cd "$alpha" && ln -s "$vault/AgentMemory/workbench/beta" wb)
  run "$alpha" send commander-beta 'wb/日本語 の名前.md' '用件'
  assert_exit 0
  run "$beta" list
  assert_out_has "文書=$vault/AgentMemory/workbench/beta/日本語 の名前.md 用件"
}

# ---------------------------------------------------------------------------
# Addresses and keys / 宛先とキー
# ---------------------------------------------------------------------------
test_address_refusals() {
  new_case
  local bad
  for bad in '' beta mail-commander-beta commander- commander-.. 'commander-../beta' 'commander-beta x' $'commander-beta\nx' '-n' commander-ベータ; do
    run "$alpha" send "$bad" "$doc" '用件'
    assert_exit 1
    assert_one_err_line
    assert_err_has '宛先を拒否した'
    assert_untouched
    run "$alpha" ack "$bad" 20261124-090015-commander-alpha-00000001
    assert_exit 1
    assert_untouched
  done
}

test_send_refuses_an_address_unknown_to_the_vault() {
  new_case
  local bad
  for bad in commander-gamma commander-Beta; do
    run "$alpha" send "$bad" "$doc" '用件'
    assert_exit 1
    assert_one_err_line
    assert_err_has "vault に AgentMemory/${bad#commander-} が無い"
    assert_err_has '宛先は herdr の名前ではなく、commander-<--where project> で書く'
    assert_untouched
  done
}

test_ack_refuses_bad_and_unknown_keys() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local key bad
  key="$(sent_key "$out")"
  : >"$FAKE_LOCAL/calls"
  for bad in '' '*' "$key*" "${key%?}" "$key $key" '-n' --all 20261124-090015-commander-alpha-ffffffff; do
    run "$beta" ack commander-beta "$bad"
    assert_exit 1
    assert_one_err_line
    assert_err_has 'キーを拒否した'
    assert_untouched
  done
  # The key is in another namespace / キーが別の名前空間にある
  run "$beta" ack commander-alpha "$key"
  assert_exit 1
  assert_untouched
  run "$beta" list
  assert_out_has "$key"
}

test_ack_deletes_only_one_bell() {
  new_case
  run "$alpha" send commander-beta "$doc" '1 通目'
  local key
  key="$(sent_key "$out")"
  run "$alpha" send commander-beta "$doc" '2 通目'
  run "$beta" ack commander-beta "$key"
  assert_exit 0
  run "$beta" list
  assert_out_lacks '1 通目'
  assert_out_has '2 通目'
}

test_overrides_of_the_gate_are_ignored() {
  new_case
  mkdir -p "$case_dir/other/AgentMemory/workbench/alpha" "$case_dir/other/AgentMemory/beta"
  printf 'x\n' >"$case_dir/other/AgentMemory/workbench/alpha/x.md"
  run_in "$alpha" env "WTCLOSE_VAULT=$case_dir/other" bash "$mail" send commander-beta "$case_dir/other/AgentMemory/workbench/alpha/x.md" '用件'
  assert_exit 1
  assert_err_has '文書を拒否した'
  run_in "$alpha" env WTCLOSE_PROJECT=beta WTCLOSE_NOW=broken WTCLOSE_GIT=false bash "$mail" send commander-beta "$doc" '用件'
  assert_exit 0
  [[ "$(sent_key "$out")" == *-commander-alpha-* ]] || flunk 'the sender must not come from WTCLOSE_PROJECT'
}

# ---------------------------------------------------------------------------
# list never stops the hook or the gate / list は hook と検問を止めない
# ---------------------------------------------------------------------------
assert_list_gives_up() { # <reason>
  assert_exit 0
  assert_no_out
  assert_one_err_line
  assert_err_has "$1"
}

test_list_when_sync_fails() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  FAKE_SYNC=fail run "$beta" list
  assert_list_gives_up 'atuin sync が失敗した(終了コード 1: Error: could not connect to the server)'
}

test_list_when_sync_times_out() {
  new_case
  local before=$SECONDS
  CLAUDE_MAIL_SYNC_TIMEOUT=1 FAKE_SYNC=hang run "$beta" list
  assert_list_gives_up 'atuin sync が時間切れになった'
  [ $((SECONDS - before)) -lt 10 ] || flunk 'the timeout did not cut the sync'
}

test_list_when_sync_ends_without_the_completion_line() {
  new_case
  FAKE_SYNC=quiet run "$beta" list
  assert_list_gives_up 'atuin sync が「Sync complete!」を出さずに終わった(Nothing was done)'
}

test_list_without_atuin() {
  new_case
  run_in "$beta" env "PATH=$root/noatuin-bin" bash "$mail" list
  assert_list_gives_up 'atuin が無い'
}

test_list_without_timeout() {
  new_case
  run_in "$beta" env "PATH=$root/notimeout-bin:$root/bin" "$(command -v bash)" "$mail" list
  assert_list_gives_up 'timeout コマンドが無い'
  assert_untouched
}

test_list_when_kv_list_fails() {
  new_case
  FAKE_KV_FAIL='list' run "$beta" list
  assert_list_gives_up 'atuin kv list が失敗した(終了コード 1: Error: kv list is broken)'
}

test_list_when_kv_get_fails_still_shows_the_key() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local key
  key="$(sent_key "$out")"
  FAKE_KV_FAIL='get' run "$beta" list
  assert_exit 0
  [ "$(lines "$out")" -eq 1 ] || flunk 'one bell must be one line'
  assert_out_has "呼び鈴 $key 宛先=commander-beta 値を読めなかった(atuin kv get が失敗した"
}

test_list_total_time_is_bounded() {
  new_case
  local i before
  for i in 1 2 3 4 5 6; do
    raw_set mail-commander-beta "20261124-09001$i-commander-alpha-00000001" $'v1\tcommander-alpha\t2026-11-24T09:00:15+0900\tAgentMemory/workbench/alpha/20261124-handoff-x.md\t用件'
  done
  before=$SECONDS
  CLAUDE_MAIL_TOTAL_TIMEOUT=3 FAKE_KV_HANG='get' run "$beta" list
  assert_exit 0
  [ $((SECONDS - before)) -lt 8 ] || flunk "took $((SECONDS - before)) s"
  [ "$(lines "$out")" -eq 6 ] || flunk 'every bell must be shown'
  assert_out_has '値を読めなかった(atuin kv get が時間切れになった)'
}

test_list_bad_tunable() {
  new_case
  CLAUDE_MAIL_TOTAL_TIMEOUT=abc run "$beta" list
  assert_list_gives_up 'CLAUDE_MAIL_TOTAL_TIMEOUT'
  CLAUDE_MAIL_TOTAL_TIMEOUT=0 run "$alpha" send commander-beta "$doc" '用件'
  assert_exit 2
  assert_untouched
}

test_list_when_the_gate_is_broken() {
  new_case
  mkdir -p "$case_dir/claude/scripts" "$case_dir/claude/skills/wtclose"
  cp "$mail" "$case_dir/claude/scripts/claude_mail.sh"
  printf 'exit 1\n' >"$case_dir/claude/skills/wtclose/close_gate.sh"
  run_in "$beta" bash "$case_dir/claude/scripts/claude_mail.sh" list
  assert_list_gives_up 'close_gate.sh --where が失敗した(終了コード 1)'
  assert_untouched
}

# An unexpected failure must not stop the hook either / 想定外の失敗でも hook を止めない
test_list_unexpected_failure_exits_0() {
  new_case
  mkdir -p "$case_dir/bin"
  printf '#!/usr/bin/env bash\nexit 7\n' >"$case_dir/bin/sort"
  chmod +x "$case_dir/bin/sort"
  run_in "$beta" env "PATH=$case_dir/bin:$PATH" bash "$mail" list
  assert_list_gives_up '想定外の失敗'
}

# ---------------------------------------------------------------------------
# Places where nothing can be read / 宛先を求められない場所
# ---------------------------------------------------------------------------
assert_silent() {
  assert_exit 0
  assert_no_out
  assert_no_err
  assert_untouched
}

test_list_is_silent_outside_a_repository() {
  new_case
  mkdir -p "$case_dir/plain"
  run "$case_dir/plain" list
  assert_silent
  run "$case_dir/plain" list --to commander-beta
  assert_silent
}

test_list_is_silent_without_a_vault() {
  new_case
  rm -rf "$vault"
  run "$beta" list
  assert_silent
}

test_list_is_silent_in_a_linked_worktree() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  git -C "$beta" worktree add -q -b feat/x "$case_dir/beta-wt"
  on_machine B
  run "$case_dir/beta-wt" list
  assert_silent
  run "$case_dir/beta-wt" list --to commander-beta
  assert_exit 0
  assert_out_has '用件=用件'
}

test_send_outside_a_repository_is_an_environment_problem() {
  new_case
  mkdir -p "$case_dir/plain"
  run "$case_dir/plain" send commander-beta "$doc" '用件'
  assert_exit 2
  assert_one_err_line
  assert_untouched
}

# ---------------------------------------------------------------------------
# send and ack report failures / send と ack は失敗を返す
# ---------------------------------------------------------------------------
test_send_and_ack_without_atuin() {
  new_case
  run_in "$alpha" env "PATH=$root/noatuin-bin" bash "$mail" send commander-beta "$doc" '用件'
  assert_exit 2
  assert_one_err_line
  run_in "$alpha" env "PATH=$root/noatuin-bin" bash "$mail" ack commander-beta 20261124-090015-commander-alpha-00000001
  assert_exit 2
  assert_one_err_line
}

test_send_when_kv_set_fails() {
  new_case
  FAKE_KV_FAIL='set' run "$alpha" send commander-beta "$doc" '用件'
  assert_exit 3
  assert_no_out
  assert_one_err_line
  assert_err_has '呼び鈴は置いていない'
  [ "$(lines "$(calls)")" -eq 1 ] || flunk 'sync must not run'
}

test_send_when_kv_set_times_out() {
  new_case
  CLAUDE_MAIL_KV_TIMEOUT=1 FAKE_KV_HANG='set' run "$alpha" send commander-beta "$doc" '用件'
  assert_exit 3
  assert_err_has '置けたかどうかは分からない'
}

test_send_when_sync_fails_keeps_the_bell_for_the_next_sync() {
  new_case
  FAKE_SYNC=fail run "$alpha" send commander-beta "$doc" '用件'
  assert_exit 4
  assert_out_has 'sent commander-beta '
  assert_one_err_line
  assert_err_has '送り直さない'
  atuin sync >/dev/null
  on_machine B
  run "$beta" list
  assert_out_has '用件=用件'
}

test_send_when_sync_times_out() {
  new_case
  CLAUDE_MAIL_SYNC_TIMEOUT=1 FAKE_SYNC=hang run "$alpha" send commander-beta "$doc" '用件'
  assert_exit 4
  assert_err_has 'atuin sync が時間切れになった'
}

test_ack_failures() {
  new_case
  run "$alpha" send commander-beta "$doc" '用件'
  local key
  key="$(sent_key "$out")"
  FAKE_KV_FAIL='list' run "$beta" ack commander-beta "$key"
  assert_exit 3
  FAKE_KV_FAIL='delete' run "$beta" ack commander-beta "$key"
  assert_exit 3
  assert_err_has '呼び鈴は消していない'
  FAKE_SYNC=fail run "$beta" ack commander-beta "$key"
  assert_exit 4
  assert_out_has "acked commander-beta $key"
  assert_one_err_line
}

test_wrong_usage() {
  new_case
  run "$alpha"
  assert_exit 64
  run "$alpha" frobnicate
  assert_exit 64
  run "$alpha" send commander-beta "$doc"
  assert_exit 64
  run "$alpha" ack commander-beta
  assert_exit 64
  run "$alpha" list --to
  assert_exit 64
  run "$alpha" list extra
  assert_exit 64
  run "$alpha" --help
  assert_exit 0
  assert_out_has 'Exit codes / 終了コード'
  assert_untouched
}

# ---------------------------------------------------------------------------
# The hook entry and the gate / hook のエントリと検問
# ---------------------------------------------------------------------------
hook_field() {
  jq -r "[.hooks.SessionStart[] | select(.hooks[].command | test(\"claude_mail\"))] | if length == 1 then .[0]$1 else error(\"want one entry\") end" \
    "$config_dir/settings.json"
}

test_hook_entry_shows_bells_and_reasons_on_stdout() {
  new_case
  local command
  command="$(hook_field '.hooks[0].command')"
  [ "$(hook_field '.matcher')" = '^(startup|resume|clear)$' ] || flunk 'unexpected matcher'
  # Longer than the 15 s that list allows itself, plus the kill grace of 1 s.
  # list が自分に許す 15 秒と、kill までの猶予 1 秒より長い。
  [ "$(hook_field '.hooks[0].timeout')" -gt 16 ] || flunk 'the hook timeout is too short'
  run_in "$beta" sh -c "$command"
  assert_exit 0
  assert_no_out
  run "$alpha" send commander-beta "$doc" '用件'
  run_in "$beta" sh -c "$command"
  assert_exit 0
  assert_out_has '用件=用件'
  FAKE_SYNC=fail run_in "$beta" sh -c "$command"
  assert_exit 0
  assert_out_has 'claude_mail.sh: atuin sync が失敗した'
  assert_no_err
}

# The real gate calls the real claude_mail.sh next to it, with the fake atuin.
# 本物の検問が、隣の本物の claude_mail.sh を、偽の atuin で呼ぶ。
test_gate_shows_the_bell_as_a_note() {
  new_case
  run "$alpha" send commander-beta "$doc" '検問で見る用件'
  local key
  key="$(sent_key "$out")"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$case_dir/fake_gh"
  chmod +x "$case_dir/fake_gh"
  mkdir -p "$vault/Zettelkasten/ResearchNotes"
  printf -- '---\nsession_id: s1\nas_of: 2026-11-24 18:00\n---\n\n## 稼働中の worker\n\nなし\n\n## 残っているもの\n\nなし\n\n## 次の入口\n\n- 次\n' \
    >"$vault/AgentMemory/beta/state_commander-beta.md"
  on_machine B
  run_in "$beta" env 'WTCLOSE_NOW=2026-11-24 18:30' "WTCLOSE_GH=$case_dir/fake_gh" \
    bash "$HOME/.claude/skills/wtclose/close_gate.sh" --check --session s1
  assert_exit 0
  assert_out_has '検問を通過した'
  assert_out_has "呼び鈴 $key 宛先=commander-beta"
  assert_out_has '検問で見る用件'
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
