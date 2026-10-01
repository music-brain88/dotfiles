#!/bin/sh
# yomiyasu_lint.py の代役。終了コード 0 でも JSON でない出力を返す。
echo "not json"
echo "boom" >&2
exit 0
