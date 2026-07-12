#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

request() {
  local method="$1"
  local path="$2"
  printf '%s %s HTTP/1.1\r\nHost: test\r\n\r\n' "$method" "$path" | \
    PMA_METRICS_FILE="$metrics_file" \
    PMA_COLLECTION_INTERVAL_SECONDS=45 \
    bash agent/http.sh
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

metrics_file="$tmp_dir/metrics.json"
printf '{"schema":{"name":"pma.metrics","version":1},"collection":{"status":"ok"}}\n' > "$metrics_file"

health_response="$(request GET /health)"
assert_contains "$health_response" "HTTP/1.1 200 OK" "health must return 200"
assert_contains "$health_response" '"snapshot_exists":true' "health must report snapshot exists"
assert_contains "$health_response" '"collection_interval_seconds":45' "health must report configured interval"

metrics_response="$(request GET /metrics.json)"
assert_contains "$metrics_response" "HTTP/1.1 200 OK" "metrics must return 200"
assert_contains "$metrics_response" "Content-Type: application/json" "metrics must be JSON"
assert_contains "$metrics_response" '"name":"pma.metrics"' "metrics must include snapshot body"

rm -f "$metrics_file"
missing_response="$(request GET /metrics.json)"
assert_contains "$missing_response" "HTTP/1.1 503 Service Unavailable" "missing metrics must return 503"

not_found_response="$(request GET /unknown)"
assert_contains "$not_found_response" "HTTP/1.1 404 Not Found" "unknown route must return 404"

method_response="$(request POST /metrics.json)"
assert_contains "$method_response" "HTTP/1.1 405 Method Not Allowed" "non-GET must return 405"

printf 'PASS: http server request handler\n'
