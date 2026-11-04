#!/usr/bin/env bash
# statusline-command.sh が書く sidecar を確かめる (Issue #784)。herdr-ctx はこの sidecar を読む。
# 固定の入力 JSON を stdin に流し、HERDR_PANE_ID と HOME を一時ディレクトリに向けて実行する。
# Checks the sidecar statusline-command.sh writes (Issue #784), which herdr-ctx reads. Feeds fixed
# JSON on stdin with HERDR_PANE_ID and HOME pointed at a temp directory.
#
# usage: statusline_sidecar_test.sh
#   STATUSLINE=<path> で検査対象を差し替えられる。わざと壊した写しで落ちることを確かめるときに使う
#   STATUSLINE=<path> swaps the script under test, e.g. a deliberately broken copy
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
statusline=${STATUSLINE:-$script_dir/../../statusline-command.sh}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pane_id="w3C:p1W"
failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# expect <label> <actual> <expected>
expect() {
  if [ "$2" != "$3" ]; then
    fail "$1: got '$2', want '$3'"
  fi
}

# 新しい HOME を用意して、テストごとに状態を分ける / a fresh HOME keeps the cases independent
new_home() {
  local home
  home=$(mktemp -d "$tmp/home.XXXXXX")
  echo "$home"
}

# input_json <context_window の JSON> / builds the fixed input around a context_window object
input_json() {
  jq -cn --arg cwd "$tmp" --argjson window "$1" '{
    session_id: "session-1",
    transcript_path: "/tmp/session-1.jsonl",
    model: {id: "claude-fable-5-1", display_name: "Fable 5.1"},
    workspace: {current_dir: $cwd, project_dir: $cwd},
    context_window: $window
  }'
}

# run_in_pane <HOME> <入力> : pane の中の statusline を実行し、描画を返す
# run_in_pane <HOME> <input>: runs the statusline inside a pane and prints what it renders
run_in_pane() {
  HOME=$1 HERDR_PANE_ID=$pane_id bash "$statusline" <<<"$2"
}

sidecar_of() {
  echo "$1/.herdr/ctx/panes/w3C_p1W.json"
}

usage='{"input_tokens": 1000, "cache_creation_input_tokens": 54000, "cache_read_input_tokens": 100000, "output_tokens": 500}'

# 1. 入力の used_percentage をそのまま書き、3 つの合計を total_input_tokens にする
#    Copies used_percentage verbatim and sums the three counters into total_input_tokens
home=$(new_home)
rendered=$(run_in_pane "$home" "$(input_json "{\"used_percentage\": 16, \"context_window_size\": 1000000, \"current_usage\": $usage}")")
file=$(sidecar_of "$home")
if [ -f "$file" ]; then
  expect "pane_id" "$(jq -r '.pane_id' "$file")" "$pane_id"
  expect "session_id" "$(jq -r '.session_id' "$file")" "session-1"
  expect "transcript_path" "$(jq -r '.transcript_path' "$file")" "/tmp/session-1.jsonl"
  expect "cwd" "$(jq -r '.cwd' "$file")" "$tmp"
  expect "model_id" "$(jq -r '.model_id' "$file")" "claude-fable-5-1"
  expect "model_name" "$(jq -r '.model_name' "$file")" "Fable 5.1"
  expect "used_percentage" "$(jq -r '.used_percentage' "$file")" "16"
  expect "context_window_size" "$(jq -r '.context_window_size' "$file")" "1000000"
  expect "total_input_tokens" "$(jq -r '.total_input_tokens' "$file")" "155000"
  if ! jq -e '.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$file" >/dev/null; then
    fail "updated_at is not UTC ISO 8601 in seconds: $(jq -r '.updated_at' "$file")"
  fi
else
  fail "sidecar was not written: $file"
fi
# 手計算なら切り捨てで 15 になる値で、💭 が入力の 16 を使うことを見る
# The manual value would truncate to 15, so this shows the gauge uses the input's 16
if ! grep -q '16%' <<<"$rendered"; then
  fail "gauge does not show used_percentage: $rendered"
fi
leftovers=$(find "$home/.herdr/ctx/panes" -type f ! -name 'w3C_p1W.json' | wc -l)
expect "temp files left behind" "$leftovers" "0"

# 2. used_percentage が無ければ手計算の値を書く / falls back to the manual value
home=$(new_home)
run_in_pane "$home" "$(input_json "{\"context_window_size\": 1000000, \"current_usage\": $usage}")" >/dev/null
expect "fallback used_percentage" "$(jq -r '.used_percentage' "$(sidecar_of "$home")")" "15"

# 3. どちらも無ければ null を書く (/compact の直後の形) / null when neither exists (just after /compact)
home=$(new_home)
run_in_pane "$home" "$(input_json '{"used_percentage": null, "context_window_size": 1000000, "current_usage": null}')" >/dev/null
expect "null used_percentage" "$(jq -r '.used_percentage' "$(sidecar_of "$home")")" "null"
expect "null total_input_tokens" "$(jq -r '.total_input_tokens' "$(sidecar_of "$home")")" "null"

# 4. 小数が来ても sidecar には入力のまま書き、ゲージは整数で描く
#    A float stays verbatim in the sidecar while the gauge stays an integer
home=$(new_home)
rendered=$(run_in_pane "$home" "$(input_json '{"used_percentage": 15.7, "context_window_size": 1000000, "current_usage": null}')")
expect "float used_percentage" "$(jq -r '.used_percentage' "$(sidecar_of "$home")")" "15.7"
if ! grep -q '15%' <<<"$rendered"; then
  fail "gauge does not truncate a float: $rendered"
fi

# 5. HERDR_PANE_ID が無ければ何も書かない / writes nothing without HERDR_PANE_ID
home=$(new_home)
env -u HERDR_PANE_ID HOME="$home" bash "$statusline" <<<"$(input_json "{\"used_percentage\": 16, \"context_window_size\": 1000000, \"current_usage\": $usage}")" >/dev/null
if [ -e "$home/.herdr" ]; then
  fail "wrote under .herdr without HERDR_PANE_ID"
fi

# 6. 書けなくても statusline は描画を続ける / keeps rendering when the sidecar cannot be written
home=$(new_home)
touch "$home/.herdr"
if ! rendered=$(run_in_pane "$home" "$(input_json "{\"used_percentage\": 16, \"context_window_size\": 1000000, \"current_usage\": $usage}")" 2>&1); then
  fail "statusline failed when the sidecar was not writable"
fi
if ! grep -q '16%' <<<"$rendered"; then
  fail "statusline stopped rendering when the sidecar was not writable: $rendered"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "ok: statusline sidecar"
