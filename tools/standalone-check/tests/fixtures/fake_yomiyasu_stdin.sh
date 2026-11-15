#!/bin/sh
# yomiyasu_lint.py の代役。引数が「- --json」ちょうどでなければ、v3 の lint がパスの引数を断るときと
# 同じく終了コード 2 で止まる。受け取った標準入力のバイト数を info の指摘の message に入れて返す。
# Stand-in for yomiyasu_lint.py: exits 2 (like the v3 lint refusing a path argument) unless the
# arguments are exactly "- --json", and reports the byte count it read on stdin in an info finding.
set -eu
if [ "$#" -ne 2 ] || [ "$1" != "-" ] || [ "$2" != "--json" ]; then
  echo "expected arguments '- --json', got: $*" >&2
  exit 2
fi
bytes=$(wc -c | tr -d ' ')
printf '{"format_version": 2, "findings": [{"rule": "stdin_probe", "line": 1, "severity": "info", "message": "stdin_bytes=%s", "snippet": ""}]}\n' "$bytes"
