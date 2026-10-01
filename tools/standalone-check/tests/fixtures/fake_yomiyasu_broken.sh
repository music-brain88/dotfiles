#!/bin/sh
# yomiyasu_lint.py の代役。JSON でない出力を返して失敗する。
echo "not json"
echo "boom" >&2
exit 2
