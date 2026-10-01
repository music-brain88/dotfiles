#!/bin/sh
# yomiyasu_lint.py の代役。info の指摘 1 件と、読まない指摘(半角空白)1 件を返す。
set -eu
cat <<'JSON'
{"score": 90, "findings": [
  {"line": 3, "severity": "info", "message": "「AではなくB」構文が検出されました。", "snippet": "一時領域ではなく共有領域に保存する。"},
  {"line": 3, "severity": "warn", "message": "英単語の前後に不要な半角空白が空けられています。", "snippet": "run 1 の"}
]}
JSON
