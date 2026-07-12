#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

metrics_file="${PMA_METRICS_FILE:-/run/pma/metrics.json}"
collection_interval_seconds="${PMA_COLLECTION_INTERVAL_SECONDS:-60}"

status_text() {
  case "$1" in
    200) printf 'OK' ;;
    400) printf 'Bad Request' ;;
    404) printf 'Not Found' ;;
    405) printf 'Method Not Allowed' ;;
    503) printf 'Service Unavailable' ;;
    *) printf 'Internal Server Error' ;;
  esac
}

send_response() {
  local status="$1"
  local content_type="$2"
  local body="$3"
  local reason
  reason="$(status_text "$status")"

  printf 'HTTP/1.1 %s %s\r\n' "$status" "$reason"
  printf 'Content-Type: %s\r\n' "$content_type"
  printf 'Connection: close\r\n'
  printf '\r\n'
  printf '%s' "$body"
}

send_json_response() {
  local status="$1"
  local body="$2"
  send_response "$status" "application/json" "$body"
}

drain_headers() {
  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && break
  done
}

read_request() {
  local request_line
  if ! IFS= read -r request_line; then
    return 1
  fi
  request_line="${request_line%$'\r'}"
  printf '%s\n' "$request_line"
}

health_body() {
  local snapshot_exists=false
  local interval_json=null
  [[ -s "$metrics_file" ]] && snapshot_exists=true
  if [[ "$collection_interval_seconds" =~ ^[0-9]+$ ]]; then
    interval_json="$collection_interval_seconds"
  fi

  jq -c -n \
    --arg status "ok" \
    --arg snapshot_path "$metrics_file" \
    --argjson snapshot_exists "$snapshot_exists" \
    --argjson collection_interval_seconds "$interval_json" \
    '{
      status: $status,
      snapshot_exists: $snapshot_exists,
      snapshot_path: $snapshot_path,
      collection_interval_seconds: $collection_interval_seconds
    }'
}

request_line="$(read_request || true)"
if [[ -z "${request_line:-}" ]]; then
  send_json_response 400 '{"error":"bad_request"}'
  exit 0
fi

drain_headers

method="${request_line%% *}"
rest="${request_line#* }"
path="${rest%% *}"
path="${path%%\?*}"

if [[ "$method" != "GET" ]]; then
  send_json_response 405 '{"error":"method_not_allowed"}'
  exit 0
fi

case "$path" in
  /health)
    send_json_response 200 "$(health_body)"
    ;;
  /metrics.json)
    if [[ ! -s "$metrics_file" ]]; then
      send_json_response 503 '{"error":"metrics_snapshot_unavailable"}'
      exit 0
    fi
    send_response 200 "application/json" "$(cat "$metrics_file")"
    ;;
  *)
    send_json_response 404 '{"error":"not_found"}'
    ;;
esac
