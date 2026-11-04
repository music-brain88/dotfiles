#!/usr/bin/env bash
# PreCompact hook: note the ids in flight before compact (Issue #784, goal 5)
# PreCompact の hook: compact の直前に、進行中の id の盤面を作業記憶に控える
#
# The commander can choose neither the moment of compact nor what the summary
# keeps, so this hook writes the board mechanically to
# <workbench_dir>/_checkpoint-<session_id>.md. compact_readback.sh reads it back,
# because the stdout of PreCompact never reaches the context.
# 司令塔は compact の時機も要約の中身も選べないので、この hook が盤面を機械的に
# <workbench_dir>/_checkpoint-<session_id>.md へ書く。PreCompact の stdout は
# 文脈に足されないので、読み返しは compact_readback.sh が受け持つ。
#
# The checkpoint is a disposable board that every run overwrites. The state
# file written by /wtclose stays the record of decisions. This hook never
# deletes old checkpoints: the /wtclose gate lists them as forget candidates.
# 控えは毎回上書きする使い捨ての盤面で、判断の記録は /wtclose が書く状態ファイルが
# 担う。古い控えは消さない。/wtclose の検問が「忘れる候補」に出す。
#
# The place is always asked from close_gate.sh --where, never built here.
# 置き場は close_gate.sh --where で求め、ここでは組み立てない。
set -euo pipefail

work=''
out_tmp=''

# Compact must never be stopped or reported as a failed hook, whatever happens
# here: exit code 2 would block it, so the EXIT trap forces 0.
# ここで何が起きても compact を止めない。終了コード 2 は compact を止めるので、
# EXIT の trap で 0 に固定する。
# shellcheck disable=SC2329 # invoked by the EXIT trap / EXIT の trap から呼ばれる
on_exit() {
  [ -z "$work" ] || rm -rf "$work"
  [ -z "$out_tmp" ] || rm -f "$out_tmp"
  exit 0
}
trap on_exit EXIT

say() {
  echo "precompact_checkpoint: $1" >&2
}

command -v jq >/dev/null 2>&1 || { say 'jq が無いので控えを書かない'; exit 0; }
input="$(cat)"

# Read a top-level string of the hook input; broken JSON reads as empty.
# hook 入力の最上位の文字列を読む。壊れた JSON は空として読む。
field() {
  jq -r --arg k "$1" '.[$k] // empty | strings' <<<"$input" 2>/dev/null || true
}

# session_id becomes part of a file name, so refuse anything but a plain id.
# session_id はファイル名になるので、素朴な id の形だけを受ける。
session_id="$(field session_id)"
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || { say 'session_id が読めないので控えを書かない'; exit 0; }
transcript="$(field transcript_path)"
cwd="$(field cwd)"
trigger="$(field trigger)"

cd "${cwd:-$PWD}" 2>/dev/null || { say "cwd に移れない: $cwd"; exit 0; }
cwd="$PWD"

gate="$HOME/.claude/skills/wtclose/close_gate.sh"
wb_dir="$(timeout 10 bash "$gate" --where workbench_dir </dev/null 2>/dev/null)" \
  || { say '作業記憶の置き場を求められない'; exit 0; }
[ -n "$wb_dir" ] || { say '作業記憶の置き場が空'; exit 0; }
mkdir -p "$wb_dir"

as_of="$(date '+%Y-%m-%d %H:%M')"
unknown="未確認(${as_of})"
work="$(mktemp -d)"

# ---------------------------------------------------------------------------
# Sections / 節
# Each collector prints the lines of one section and fails when its command
# fails. A failure becomes "unknown" in that section, so one broken command
# never loses the whole checkpoint.
# 節ごとの関数が行を出し、コマンドの失敗はそのまま失敗で返す。失敗はその節の
# 「未確認」になるだけで、控え全体は失わない。
# ---------------------------------------------------------------------------
collect_agents() {
  local raw
  raw="$(timeout 10 herdr agent list)" || return 1
  jq -r '.result.agents[] | "- \(.name // .pane_id): \(.agent_status)、\(.cwd)"' <<<"$raw"
}

collect_prs() {
  local raw
  raw="$(timeout 10 gh pr list --state open --limit 100 --json number,title,headRefName,isDraft)" || return 1
  jq -r '.[] | "- #\(.number) \(.title)(\(.headRefName)、\(if .isDraft then "draft" else "ready" end))"' <<<"$raw"
}

collect_worktrees() {
  local raw
  raw="$(timeout 10 git worktree list --porcelain)" || return 1
  awk '
    function emit() { if (path != "") printf "- %s [%s]\n", path, (branch == "" ? "detached" : branch) }
    /^worktree / { emit(); path = substr($0, 10); branch = ""; next }
    /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    END { emit() }' <<<"$raw"
}

# Without HERDR_PANE_ID there is nobody to ask, which reads as "no name".
# HERDR_PANE_ID が無ければ聞く先が無いので、「なし」として読む。
collect_self() {
  local raw name
  [ -n "${HERDR_PANE_ID:-}" ] || return 0
  raw="$(timeout 10 herdr agent get "$HERDR_PANE_ID")" || return 1
  name="$(jq -r '.result.agent.name // empty' <<<"$raw")" || return 1
  [ -z "$name" ] || printf -- '- %s\n' "$name"
}

# section <file> <line when it fails> <collector>
section() {
  local out="$work/$1" failed="$2"
  if ! "$3" >"$out" 2>/dev/null; then
    printf -- '- %s\n' "$failed" >"$out"
    say "$1 を取れなかった"
  elif [ ! -s "$out" ]; then
    printf -- '- なし\n' >"$out"
  fi
}

# Run in parallel: the hook has 30 seconds, and five commands of up to 10
# seconds in a row could be killed before the checkpoint is written.
# 並列に走らせる。hook の持ち時間は 30 秒で、最大 10 秒のコマンドを 5 本直列に
# すると、控えを書く前に殺されることがある。
section agents "$unknown" collect_agents &
section prs "PR の状態は${unknown}" collect_prs &
section worktrees "$unknown" collect_worktrees &
section self "$unknown" collect_self &
timeout 10 git branch --show-current >"$work/branch" 2>/dev/null &
timeout 10 bash "$gate" --where memory_dir </dev/null >"$work/memory_dir" 2>/dev/null &
wait

# Newest first, unique, 30 at most. Sorting would keep the lowest numbers
# instead of the ones the session was just talking about.
# 新しい順に重複を除き、30 件までにする。並べ替えると、いま話していた番号でなく
# 小さい番号が残ってしまう。
recent() {
  tac | awk 'n < 30 && !seen[$0]++ { print; n++ }' | paste -sd ',' - | sed 's/,/, /g'
}

# Transcripts are an internal format and may lag behind the conversation, so
# read the raw tail with regular expressions and rely on no JSON key. Quotes are
# escaped in that raw text, which is why a backslash may precede an agent name.
# transcript は内部形式で、会話より遅れることもある。JSON の鍵に依存せず、末尾の
# 生テキストを正規表現で拾う。生テキストの引用符はエスケープされているので、
# agent の名前の前には \ が付くことがある。
issues="$unknown"
clickup="$unknown"
named_agents="$unknown"
if [ -n "$transcript" ] && [ -r "$transcript" ] && [ -f "$transcript" ]; then
  tail -n 400 "$transcript" >"$work/tail"
  # Take the whole run of digits: a cut number would point at another issue.
  # Six-digit colour codes such as #111111 come along, which is the lesser harm.
  # 数字の列を全部取る。途中で切った番号は別の Issue を指してしまう。#111111 の
  # ような 6 桁の色コードも拾うが、切れた番号を出すよりよい。
  issues="$({ grep -oE '#[0-9]+\b' "$work/tail" || true; } | recent)"
  clickup="$({ grep -oE 'app\.clickup\.com/t/[A-Za-z0-9]+' "$work/tail" || true; } | sed 's|.*/||' | recent)"
  # A name cut short by a shell variable or a flag ("claude-$slug", "--until")
  # is not a name, so drop what starts or ends with a hyphen.
  # シェルの変数やフラグで切れたもの(claude-$slug、--until)は名前でないので、
  # ハイフンで始まるものと終わるものは捨てる。
  named_agents="$({ grep -oE 'herdr agent (wait|prompt|start) \\*"?[a-z0-9_-]+' "$work/tail" || true; } \
    | sed -E 's/.*[ "\\]//' | { grep -vE '^-|-$' || true; } | recent)"
  issues="${issues:-なし}"
  clickup="${clickup:-なし}"
  named_agents="${named_agents:-なし}"
else
  say "transcript を読めない: $transcript"
fi

agent_name="$(sed 's/^- //' "$work/self")"
memory_dir="$(cat "$work/memory_dir")"
unit="$(cat "$work/branch")"

# Print the as_of of a state file; state files keep it under metadata:.
# 状態ファイルの as_of を出す。状態ファイルでは metadata: の下にある。
state_as_of() {
  awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^[ \t]*as_of:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }' "$1"
}

case "$agent_name" in
  なし | 未確認*) state_line="$agent_name" ;;
  *)
    state_file="$memory_dir/state_${agent_name}.md"
    if [ -z "$memory_dir" ]; then
      state_line="$unknown"
    elif [ -r "$state_file" ]; then
      state_line="$state_file(as_of: $(state_as_of "$state_file"))"
    else
      state_line='なし'
    fi
    ;;
esac

# Write to a hidden file next to the target and rename it, so a reader never
# sees half a checkpoint. The name does not end in .md, so the gate skips it.
# 同じ場所の隠しファイルに書いて mv するので、読み手は書きかけの控えを見ない。
# 名前が .md で終わらないので、検問も数えない。
target="$wb_dir/_checkpoint-${session_id}.md"
out_tmp="$wb_dir/._checkpoint-${session_id}.$$"
{
  cat <<EOF
---
type: agent-workbench
kind: checkpoint
unit: "${unit:-session}"
created: ${as_of%% *}
session_id: ${session_id}
as_of: ${as_of}
trigger: ${trigger:-unknown}
---

# compact 前の控え(${as_of})

hook が機械的に書いた盤面。状態ファイル(state_<司令塔の名前>.md)と突き合わせて続ける。未回答の質問は拾えない。

## セッション

- cwd: ${cwd}
- pane: ${HERDR_PANE_ID:-herdr の外}
- agent の名前: ${agent_name}

## 稼働中の agent(herdr agent list)

EOF
  cat "$work/agents"
  printf '\n## open の PR(gh pr list --state open)\n\n'
  cat "$work/prs"
  printf '\n## worktree(git worktree list)\n\n'
  cat "$work/worktrees"
  cat <<EOF

## 会話に出た番号(transcript の末尾 400 行から機械抽出)

- Issue / PR: ${issues}
- ClickUp: ${clickup}
- herdr の agent: ${named_agents}

## 次に読むもの

- 状態ファイル: ${state_line}
EOF
} >"$out_tmp"
mv -f "$out_tmp" "$target"
out_tmp=''
