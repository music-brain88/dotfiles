#!/usr/bin/env bash
# SessionStart (compact) hook: read the checkpoint back (Issue #784, goal 5)
# SessionStart(compact)の hook: compact の前に控えた盤面を文脈に読み返す
#
# PreCompact cannot add to the context, but the plain stdout of a SessionStart
# hook whose source is compact lands in the compacted context. This hook prints
# what precompact_checkpoint.sh wrote. It assumes that session_id stays the same
# across compact. The place is asked from close_gate.sh --where.
# PreCompact は文脈に足せないが、source が compact の SessionStart の hook の平文の
# stdout は圧縮後の文脈に入る。この hook は precompact_checkpoint.sh が書いた控えを
# 出す。session_id が compact の前後で同じことを前提にする。置き場は
# close_gate.sh --where で求める。
set -euo pipefail

# A failed read-back must not get in the way of the session.
# 読み返しの失敗でセッションの邪魔をしない。
trap 'exit 0' EXIT

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"

# Read a top-level string of the hook input; broken JSON reads as empty.
# hook 入力の最上位の文字列を読む。壊れた JSON は空として読む。
field() {
  jq -r --arg k "$1" '.[$k] // empty | strings' <<<"$input" 2>/dev/null || true
}

# settings.json narrows this by matcher too; guard twice.
# settings.json の matcher でも絞るが、二重に守る。
[ "$(field source)" = 'compact' ] || exit 0

# session_id is part of a file name, so accept a plain id only.
# session_id はファイル名の一部なので、素朴な id の形だけを受ける。
session_id="$(field session_id)"
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

cwd="$(field cwd)"
cd "${cwd:-$PWD}" 2>/dev/null || exit 0

# Shorter than the 10 seconds of the hook entry in settings.json.
# settings.json の hook の持ち時間 10 秒より短くする。
wb_dir="$(timeout 8 bash "$HOME/.claude/skills/wtclose/close_gate.sh" --where workbench_dir </dev/null 2>/dev/null)" || exit 0

checkpoint="$wb_dir/_checkpoint-${session_id}.md"
[ -r "$checkpoint" ] || exit 0

echo 'compact の前に hook が控えた盤面を読み返す。状態ファイルと突き合わせ、取り直しが要る値(PR の状態・agent の状態)は取り直してから続ける。'
awk 'NR == 1 && $0 == "---" { fm = 1; next } fm { if ($0 == "---") fm = 0; next } { print }' "$checkpoint"
