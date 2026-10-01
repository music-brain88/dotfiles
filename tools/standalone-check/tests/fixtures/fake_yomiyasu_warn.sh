#!/bin/sh
# yomiyasu_lint.py の代役。warn の指摘 1 件を返す。
set -eu
cat <<'JSON'
{"score": 70, "findings": [
  {"line": 3, "severity": "warn", "message": "比喩動詞「効く」の過剰使用", "snippet": "地味に効く。"}
]}
JSON
