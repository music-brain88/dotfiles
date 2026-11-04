#!/bin/sh
# yomiyasu_lint.py の代役。info の指摘 1 件と、読まない指摘(rule が excess_bold)1 件を返す。
# Stand-in for yomiyasu_lint.py: one info finding and one finding we do not read (excess_bold).
set -eu
cat <<'JSON'
{"format_version": 2, "findings": [
  {"rule": "negative_parallelism", "line": 3, "severity": "info", "message": "「AではなくB」構文が検出されました。", "snippet": "一時領域ではなく共有領域に保存する。"},
  {"rule": "excess_bold", "line": 1, "severity": "warn", "message": "太字の頻度（1,000字あたり 8.0個）が設定した目安を超えています（推奨: 2.0以下）。", "snippet": "**太字**"}
]}
JSON
