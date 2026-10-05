#!/usr/bin/env bash
# Tests for gpg_cache_check.sh / GPG キャッシュ確認スクリプト gpg_cache_check.sh のテスト
#
# Every case puts fake git, gpg and gpg-connect-agent first on PATH, so the
# real keyring and the real gpg-agent are never touched.
# 各ケースは偽の git・gpg・gpg-connect-agent を PATH の先頭に置くので、
# 実物の鍵束と gpg-agent には触らない。
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
# FAKE_LISTING    : file printed by gpg --list-secret-keys
# FAKE_KEYINFO    : file printed by gpg-connect-agent (unset = it exits 1)
# ---------------------------------------------------------------------------
mkdir -p "$root/bin"
cat >"$root/bin/git" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_SIGNINGKEY:-}" ] || exit 1
echo "$FAKE_SIGNINGKEY"
EOF
cat >"$root/bin/gpg" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_LISTING:-}" ] || { echo "gpg: error reading key: No secret key" >&2; exit 2; }
cat "$FAKE_LISTING"
EOF
cat >"$root/bin/gpg-connect-agent" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_KEYINFO:-}" ] || { echo "gpg-connect-agent: no gpg-agent running" >&2; exit 1; }
cat "$FAKE_KEYINFO"
EOF
chmod +x "$root/bin/"*
export PATH="$root/bin:$PATH"

# The key layout seen on the real machine: primary [SC], ssb [E], ssb [S].
# 実機の鍵構成: primary [SC]・ssb [E]・ssb [S]。[E] が [S] より先に並ぶ。
grip_primary=AAAA0000AAAA0000AAAA0000AAAA0000AAAA0000
grip_enc=EEEE1111EEEE1111EEEE1111EEEE1111EEEE1111
grip_sign=SSSS2222SSSS2222SSSS2222SSSS2222SSSS2222

cat >"$root/listing_e_then_s" <<EOF
sec   ed25519 2024-01-01 [SC]
      0123456789ABCDEF0123456789ABCDEF01234567
      Keygrip = $grip_primary
uid           [ultimate] test <test@example.invalid>
ssb   cv25519 2024-01-01 [E]
      Keygrip = $grip_enc
ssb   ed25519 2024-01-01 [S]
      Keygrip = $grip_sign
EOF

cat >"$root/listing_no_s" <<EOF
sec   ed25519 2024-01-01 [SC]
      0123456789ABCDEF0123456789ABCDEF01234567
      Keygrip = $grip_primary
uid           [ultimate] test <test@example.invalid>
ssb   cv25519 2024-01-01 [E]
      Keygrip = $grip_enc
EOF

# An [S] record without a Keygrip line, followed by another record
# Keygrip 行の無い [S] のレコードの後に、別のレコードが続く
cat >"$root/listing_s_without_grip" <<EOF
sec   ed25519 2024-01-01 [SC]
      0123456789ABCDEF0123456789ABCDEF01234567
      Keygrip = $grip_primary
uid           [ultimate] test <test@example.invalid>
ssb   ed25519 2024-01-01 [S]
ssb   cv25519 2024-01-01 [E]
      Keygrip = $grip_enc
EOF

# keyinfo_<flags>: the cached flag of primary, [E] and [S] in that order
# keyinfo_<フラグ>: primary・[E]・[S] の cached フラグをこの順に並べる
write_keyinfo() {
  local name="$1" p="$2" e="$3" s="$4"
  {
    echo "S KEYINFO $grip_primary D - - $p P - - -"
    echo "S KEYINFO $grip_enc D - - $e P - - -"
    echo "S KEYINFO $grip_sign D - - $s P - - -"
    echo "OK"
  } >"$root/$name"
}
write_keyinfo keyinfo_sign_warm - - 1
write_keyinfo keyinfo_sign_cold 1 1 -
{
  echo "S KEYINFO $grip_primary D - - 1 P - - -"
  echo "S KEYINFO $grip_enc D - - 1 P - - -"
  echo "OK"
} >"$root/keyinfo_no_sign"

# ---------------------------------------------------------------------------
# Runner / 実行と照合
# ---------------------------------------------------------------------------
pass=0
failed=0

# run_case <name> <expected exit> <expected stdout> <expected stderr substring>
run_case() {
  local name="$1" want_code="$2" want_out="$3" want_err="$4"
  local out err code=0
  out="$(bash "$check" 2>"$root/stderr")" || code=$?
  err="$(cat "$root/stderr")"
  # An empty want_err means stderr must be empty / want_err が空なら stderr も空であること
  local err_ok=0
  if [ -z "$want_err" ]; then
    [ -z "$err" ] && err_ok=1
  else
    [[ "$err" == *"$want_err"* ]] && err_ok=1
  fi
  if [ "$code" = "$want_code" ] && [ "$out" = "$want_out" ] && [ "$err_ok" = 1 ]; then
    pass=$((pass + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
    echo "     exit:   got $code, want $want_code"
    echo "     stdout: got '$out', want '$want_out'"
    echo "     stderr: got '$err', want '*$want_err*'"
  fi
}

reset_env() {
  unset FAKE_SIGNINGKEY FAKE_LISTING FAKE_KEYINFO
  export FAKE_SIGNINGKEY=0123456789ABCDEF
  export FAKE_LISTING="$root/listing_e_then_s"
}

reset_env
export FAKE_KEYINFO="$root/keyinfo_sign_warm"
run_case "cached: [S] warm, [E] listed first" 0 "cached=1" ""

reset_env
export FAKE_KEYINFO="$root/keyinfo_sign_cold"
# Regression of #583: [E] and primary are warm, [S] is cold.
# #583 の回帰: [E] と primary は温かく、[S] だけ冷えている。
run_case "not cached: only [S] cold" 1 "cached=0" ""

reset_env
unset FAKE_SIGNINGKEY
export FAKE_KEYINFO="$root/keyinfo_sign_warm"
run_case "no user.signingkey" 2 "" "user.signingkey is not set"

reset_env
export FAKE_LISTING="$root/listing_no_s"
export FAKE_KEYINFO="$root/keyinfo_sign_warm"
# Review of PR #625: an empty keygrip must not reach the agent query.
# PR #625 のレビュー指摘: 空の keygrip で agent に問い合わせない。
run_case "no [S] subkey" 2 "" "no [S] subkey keygrip found"

reset_env
export FAKE_LISTING="$root/listing_s_without_grip"
export FAKE_KEYINFO="$root/keyinfo_sign_warm"
# Review of PR #680: the [S] record must not borrow the next record's keygrip.
# PR #680 のレビュー指摘: [S] のレコードが次のレコードの keygrip を借りない。
run_case "[S] subkey without Keygrip line" 2 "" "no [S] subkey keygrip found"

reset_env
unset FAKE_LISTING
export FAKE_KEYINFO="$root/keyinfo_sign_warm"
run_case "gpg knows no secret key" 2 "" "no [S] subkey keygrip found"

reset_env
run_case "gpg-connect-agent fails" 2 "" "gpg-connect-agent failed"

reset_env
export FAKE_KEYINFO="$root/keyinfo_no_sign"
run_case "agent does not list the [S] keygrip" 2 "" "does not list keygrip"

echo "passed: $pass, failed: $failed"
[ "$failed" -eq 0 ]
