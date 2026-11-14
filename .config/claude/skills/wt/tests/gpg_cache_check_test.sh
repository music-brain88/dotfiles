#!/usr/bin/env bash
# Tests for gpg_cache_check.sh / GPG キャッシュ確認スクリプト gpg_cache_check.sh のテスト
#
# Every case puts fake git and gpg first on PATH, so the real keyring and the
# real gpg-agent are never touched.
# 各ケースは偽の git と gpg を PATH の先頭に置くので、実物の鍵束と
# gpg-agent には触らない。
#
# Usage / 使い方: bash .config/claude/skills/wt/tests/gpg_cache_check_test.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/../gpg_cache_check.sh"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# ---------------------------------------------------------------------------
# Fakes / 偽のコマンド
# FAKE_SIGNINGKEY : value of user.signingkey (unset = git config exits 1)
# FAKE_SIGN       : how the fake gpg answers the trial signature
#                   ok   = exit 0
#                   fail = exit 2 with "No pinentry", as real gpg does when a
#                          passphrase is needed / パスフレーズが要るときの実物の gpg と同じ
#                   hang = never answer / 応答しない
# FAKE_GPG_ARGS   : file where the fake gpg writes its arguments, one per line
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/git" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_SIGNINGKEY:-}" ] || exit 1
echo "$FAKE_SIGNINGKEY"
EOF
cat >"$root/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_GPG_ARGS"
cat >/dev/null
case "${FAKE_SIGN:-}" in
  ok)
    exit 0
    ;;
  fail)
    echo "gpg: signing failed: No pinentry" >&2
    echo "gpg: [stdin]: clear-sign failed: No pinentry" >&2
    exit 2
    ;;
  hang)
    # exec, so that timeout kills the process that holds the pipes
    # timeout がパイプを握っているプロセスそのものを止められるように exec する
    exec sleep 30
    ;;
esac
echo "gpg: unexpected FAKE_SIGN" >&2
exit 2
EOF
chmod +x "$root/bin/"*

# A PATH with git, timeout and bash (for the fake git's shebang) but without gpg
# git・timeout・bash(偽の git の shebang 用)はあるが gpg が無い PATH
mkdir -p "$root/nogpg"
cp "$root/bin/git" "$root/nogpg/git"
ln -s "$(command -v timeout)" "$root/nogpg/timeout"
ln -s "$BASH" "$root/nogpg/bash"

export PATH="$root/bin:$PATH"
export FAKE_GPG_ARGS="$root/gpg_args"

# A fake key ID unrelated to any real key / 実物の鍵と無関係な偽の鍵 ID
fake_key=FAKEKEY000000000

# ---------------------------------------------------------------------------
# Runner / 実行と照合
# ---------------------------------------------------------------------------
pass=0
failed=0

report() {
  local name="$1" ok="$2"
  shift 2
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
    printf '     %s\n' "$@"
  fi
}

# run_case <name> <expected exit> <expected stdout> <expected stderr substring>
run_case() {
  local name="$1" want_code="$2" want_out="$3" want_err="$4"
  local out err code=0
  # CHECK_PATH replaces PATH for the script only, not for this runner.
  # bash is called by its absolute path, so that a PATH without gpg still
  # finds the shell.
  # CHECK_PATH はスクリプトの PATH だけを差し替え、このテスト自身の PATH は
  # 変えない。gpg の無い PATH でもシェルを見つけられるように、bash は絶対
  # パスで呼ぶ。
  out="$(PATH="${CHECK_PATH:-$PATH}" "$BASH" "$check" 2>"$root/stderr")" || code=$?
  err="$(cat "$root/stderr")"
  # An empty want_err means stderr must be empty / want_err が空なら stderr も空であること
  local err_ok=0
  if [ -z "$want_err" ]; then
    [ -z "$err" ] && err_ok=1
  else
    [[ "$err" == *"$want_err"* ]] && err_ok=1
  fi
  local ok=0
  [ "$code" = "$want_code" ] && [ "$out" = "$want_out" ] && [ "$err_ok" = 1 ] && ok=1
  report "$name" "$ok" \
    "exit:   got $code, want $want_code" \
    "stdout: got '$out', want '$want_out'" \
    "stderr: got '$err', want '*$want_err*'"
}

reset_env() {
  unset FAKE_SIGNINGKEY FAKE_SIGN GPG_CACHE_CHECK_TIMEOUT CHECK_PATH
  export FAKE_SIGNINGKEY="$fake_key"
  rm -f "$FAKE_GPG_ARGS"
}

reset_env
export FAKE_SIGN=ok
run_case "trial signature succeeds" 0 "cached=1" ""

# The trial signature must disable pinentry and sign with user.signingkey
# 試しの署名は pinentry を出さない設定で、user.signingkey の鍵で行う
args="$(cat "$FAKE_GPG_ARGS" 2>/dev/null)" || args=''
args_ok=1
for want in --batch $'--pinentry-mode\nerror' --clearsign $'-u\n'"$fake_key" $'-o\n/dev/null'; do
  [[ $'\n'"$args"$'\n' == *$'\n'"$want"$'\n'* ]] || args_ok=0
done
report "trial signature disables pinentry" "$args_ok" "gpg args: $(tr '\n' ' ' <<<"$args")"

reset_env
export FAKE_SIGN=fail
# Regression of #814: the verdict follows the signature, not KEYINFO.
# #814 の回帰: 判定は KEYINFO ではなく署名の成否に従う。
run_case "trial signature fails" 1 "cached=0" "No pinentry"

reset_env
unset FAKE_SIGNINGKEY
export FAKE_SIGN=ok
run_case "no user.signingkey" 2 "" "user.signingkey is not set"
report "no user.signingkey does not run gpg" "$([ ! -e "$FAKE_GPG_ARGS" ] && echo 1 || echo 0)" \
  "gpg was run without user.signingkey"

reset_env
export FAKE_SIGN=hang GPG_CACHE_CHECK_TIMEOUT=1
run_case "trial signature times out" 2 "" "did not finish within 1s"

reset_env
CHECK_PATH="$root/nogpg"
run_case "gpg is not on PATH" 2 "" "gpg is not found on PATH"

echo "passed: $pass, failed: $failed"
[ "$failed" -eq 0 ]
