#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

. agent/lib/cpu.sh

usage="$(pma_cpu_usage_from_samples \
  'cpu  100 0 100 800 0 0 0 0 0 0' \
  'cpu  150 0 150 900 0 0 0 0 0 0')"

[[ "$usage" == "50" ]] || fail "expected 50 percent CPU usage, got $usage"

invalid_usage="$(pma_cpu_usage_from_samples \
  'cpu  100 0 100 800 0 0 0 0 0 0' \
  'cpu  100 0 100 800 0 0 0 0 0 0')"

[[ "$invalid_usage" == "null" ]] || fail "expected null for unchanged samples, got $invalid_usage"

large_usage="$(pma_cpu_usage_from_samples \
  'cpu  700000000 0 300000000 8000000000 0 0 0 0 0 0' \
  'cpu  700000050 0 300000050 8000000100 0 0 0 0 0 0')"

[[ "$large_usage" == "50" ]] || fail "expected 50 percent CPU usage for large samples, got $large_usage"

printf 'PASS: cpu usage calculation\n'
