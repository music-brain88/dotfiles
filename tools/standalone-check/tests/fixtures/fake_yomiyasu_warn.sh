#!/bin/sh
# yomiyasu_lint.py の代役。warn の指摘 1 件を返す。
# Stand-in for yomiyasu_lint.py: one warn finding.
set -eu
cat <<'JSON'
{"format_version": 2, "findings": [
  {"rule": "metaphor_verb", "line": 3, "severity": "warn", "message": "比喩動詞「効く」の過剰使用が検出されました。", "snippet": "地味に効く。"}
]}
JSON
