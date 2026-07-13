#!/usr/bin/env bash

pma_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

pma_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

pma_command_timeout_seconds() {
  printf '%s\n' "${PMA_COMMAND_TIMEOUT_SECONDS:-5}"
}

pma_run() {
  local timeout_seconds
  local status
  timeout_seconds="$(pma_command_timeout_seconds)"

  pma_debug "run timeout=${timeout_seconds}s command=$*"
  if pma_command_exists timeout; then
    timeout "$timeout_seconds" "$@" || status=$?
  else
    "$@" || status=$?
  fi

  status="${status:-0}"
  pma_debug "done status=$status command=$*"
  return "$status"
}

pma_debug() {
  if [[ "${PMA_DEBUG:-0}" == "1" ]]; then
    printf 'PMA: %s\n' "$*" >&2
  fi
}

pma_json_string() {
  jq -Rn --arg value "${1:-}" '$value'
}

pma_percent() {
  local used="${1:-}"
  local total="${2:-}"
  if [[ -z "$used" || -z "$total" || "$total" == "0" ]]; then
    printf 'null\n'
    return
  fi
  jq -n --argjson used "$used" --argjson total "$total" '((($used / $total) * 10000) | round) / 100'
}

pma_null_if_empty() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    printf 'null\n'
  else
    jq -Rn --arg value "$value" '$value'
  fi
}

pma_empty_object() {
  printf '{}\n'
}

pma_empty_array() {
  printf '[]\n'
}

pma_error_json() {
  local module="$1"
  local code="$2"
  local message="$3"
  jq -n --arg module "$module" --arg code "$code" --arg message "$message" '{
    "module": $module,
    "code": $code,
    "message": $message
  }'
}
