#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

. agent/lib/util.sh

error_json="$(pma_error_json cpu module_failed test)"

printf '%s\n' "$error_json" | jq -e '
  .module == "cpu"
  and .code == "module_failed"
  and .message == "test"
' >/dev/null || fail "pma_error_json must render a valid structured error"

printf 'PASS: util helpers\n'
