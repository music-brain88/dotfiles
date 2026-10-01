#!/bin/sh
# テスト指定の JSON と終了コードを返す / Emit a test-supplied report and exit status.
set -eu
printf '%s\n' "${STANDALONE_CHECK_TEST_REPORT:?}"
exit_code=${STANDALONE_CHECK_TEST_EXIT_CODE:-0}
if [ "$exit_code" -ne 0 ]; then
  echo "fake lint failed" >&2
fi
exit "$exit_code"
