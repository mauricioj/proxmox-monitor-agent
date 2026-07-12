#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if [[ "${PMA_TRACE:-0}" == "1" ]]; then
  set -x
fi

pma_boot_debug() {
  if [[ "${PMA_DEBUG:-0}" == "1" ]]; then
    printf 'PMA BOOT: %s\n' "$*" >&2
  fi
}

pma_boot_debug "start metrics.sh"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib_dir="$script_dir/lib"
pma_boot_debug "script_dir=$script_dir"
pma_boot_debug "lib_dir=$lib_dir"

# shellcheck source=agent/lib/util.sh
pma_boot_debug "source util.sh"
. "$lib_dir/util.sh"
# shellcheck source=agent/lib/schema.sh
pma_debug "source schema.sh"
. "$lib_dir/schema.sh"
# shellcheck source=agent/lib/capabilities.sh
pma_debug "source capabilities.sh"
. "$lib_dir/capabilities.sh"
# shellcheck source=agent/lib/host.sh
pma_debug "source host.sh"
. "$lib_dir/host.sh"
# shellcheck source=agent/lib/cluster.sh
pma_debug "source cluster.sh"
. "$lib_dir/cluster.sh"
# shellcheck source=agent/lib/cpu.sh
pma_debug "source cpu.sh"
. "$lib_dir/cpu.sh"
# shellcheck source=agent/lib/memory.sh
pma_debug "source memory.sh"
. "$lib_dir/memory.sh"
# shellcheck source=agent/lib/network.sh
pma_debug "source network.sh"
. "$lib_dir/network.sh"
# shellcheck source=agent/lib/filesystems.sh
pma_debug "source filesystems.sh"
. "$lib_dir/filesystems.sh"
# shellcheck source=agent/lib/storage.sh
pma_debug "source storage.sh"
. "$lib_dir/storage.sh"
# shellcheck source=agent/lib/disks.sh
pma_debug "source disks.sh"
. "$lib_dir/disks.sh"
# shellcheck source=agent/lib/sensors.sh
pma_debug "source sensors.sh"
. "$lib_dir/sensors.sh"
# shellcheck source=agent/lib/virtualization.sh
pma_debug "source virtualization.sh"
. "$lib_dir/virtualization.sh"
pma_debug "sources loaded"

module_errors_file="$(mktemp)"

cleanup() {
  rm -f "$module_errors_file"
}

trap cleanup EXIT

pma_record_module_error() {
  local module="$1"
  local code="$2"
  local message="$3"
  pma_error_json "$module" "$code" "$message" >> "$module_errors_file"
}

pma_collect_or_fallback() {
  local module="$1"
  local fallback_json="$2"
  local collector="$3"
  local timeout_seconds="${PMA_MODULE_TIMEOUT_SECONDS:-15}"
  local tmp_json tmp_err status

  tmp_json="$(mktemp)"
  tmp_err="$(mktemp)"
  status=0

  pma_debug "collect $module"
  if pma_command_exists timeout; then
    if [[ "${PMA_DEBUG:-0}" == "1" ]]; then
      timeout --kill-after=1s "$timeout_seconds" bash -c '
        set -euo pipefail
        lib_dir="$1"
        collector="$2"
        . "$lib_dir/util.sh"
        . "$lib_dir/schema.sh"
        . "$lib_dir/capabilities.sh"
        . "$lib_dir/host.sh"
        . "$lib_dir/cluster.sh"
        . "$lib_dir/cpu.sh"
        . "$lib_dir/memory.sh"
        . "$lib_dir/network.sh"
        . "$lib_dir/filesystems.sh"
        . "$lib_dir/storage.sh"
        . "$lib_dir/disks.sh"
        . "$lib_dir/sensors.sh"
        . "$lib_dir/virtualization.sh"
        "$collector"
      ' _ "$lib_dir" "$collector" > "$tmp_json" 2> >(tee "$tmp_err" >&2) || status=$?
    else
      timeout --kill-after=1s "$timeout_seconds" bash -c '
        set -euo pipefail
        lib_dir="$1"
        collector="$2"
        . "$lib_dir/util.sh"
        . "$lib_dir/schema.sh"
        . "$lib_dir/capabilities.sh"
        . "$lib_dir/host.sh"
        . "$lib_dir/cluster.sh"
        . "$lib_dir/cpu.sh"
        . "$lib_dir/memory.sh"
        . "$lib_dir/network.sh"
        . "$lib_dir/filesystems.sh"
        . "$lib_dir/storage.sh"
        . "$lib_dir/disks.sh"
        . "$lib_dir/sensors.sh"
        . "$lib_dir/virtualization.sh"
        "$collector"
      ' _ "$lib_dir" "$collector" > "$tmp_json" 2> "$tmp_err" || status=$?
    fi
  else
    if [[ "${PMA_DEBUG:-0}" == "1" ]]; then
      "$collector" > "$tmp_json" 2> >(tee "$tmp_err" >&2) || status=$?
    else
      "$collector" > "$tmp_json" 2> "$tmp_err" || status=$?
    fi
  fi

  if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
    pma_record_module_error "$module" "module_timeout" "$module collection timed out after ${timeout_seconds}s"
    printf 'PMA WARNING: %s collection timed out after %ss\n' "$module" "$timeout_seconds" >&2
    if [[ -s "$tmp_err" && "${PMA_DEBUG:-0}" != "1" ]]; then
      printf 'PMA WARNING: %s stderr before timeout:\n' "$module" >&2
      sed 's/^/  /' "$tmp_err" >&2
    fi
    rm -f "$tmp_json" "$tmp_err"
    printf '%s\n' "$fallback_json"
    return
  fi

  if [[ "$status" -ne 0 ]]; then
    pma_record_module_error "$module" "module_failed" "$module collection failed with exit code $status"
    printf 'PMA WARNING: %s collection failed with exit code %s\n' "$module" "$status" >&2
    if [[ -s "$tmp_err" && "${PMA_DEBUG:-0}" != "1" ]]; then
      printf 'PMA WARNING: %s stderr:\n' "$module" >&2
      sed 's/^/  /' "$tmp_err" >&2
    fi
    rm -f "$tmp_json" "$tmp_err"
    printf '%s\n' "$fallback_json"
    return
  fi

  if ! jq empty "$tmp_json" >/dev/null 2>&1; then
    pma_record_module_error "$module" "invalid_json" "$module collection did not produce valid JSON"
    printf 'PMA WARNING: %s collection did not produce valid JSON\n' "$module" >&2
    rm -f "$tmp_json" "$tmp_err"
    printf '%s\n' "$fallback_json"
    return
  fi

  cat "$tmp_json"
  rm -f "$tmp_json" "$tmp_err"
}

start_ms="$(date +%s%3N 2>/dev/null || printf '0')"
generated_at="$(pma_now_utc)"

schema_json="$(pma_collect_schema)"
capabilities_json="$(pma_collect_or_fallback capabilities '{"tools":{"jq":true,"pvesh":false,"lsblk":false,"findmnt":false,"ip":false,"sensors":false,"smartctl":false,"nvme":false,"zpool":false,"zfs":false,"qm":false,"pct":false},"features":{"cluster":false,"sensors":false,"storage":false,"disks":false,"virtualization":false},"missing_tools":["pvesh","lsblk","findmnt","ip","sensors","smartctl","nvme","zpool","zfs","qm","pct"]}' pma_collect_capabilities)"
missing_tool_errors_json="$(
  jq -n --argjson capabilities "$capabilities_json" '
    [
      $capabilities.missing_tools[]?
      | {
          module: .,
          code: "tool_missing",
          message: (. + " command not found")
        }
    ]'
)"

host_json="$(pma_collect_or_fallback host '{"id":"uninitialized","hostname":"unknown","node_name":null,"proxmox_version":null,"kernel_version":null,"uptime_seconds":null,"architecture":null,"boot_mode":null,"timezone":null,"manufacturer":null,"model":null,"serial":null}' pma_collect_host)"
cluster_json="$(pma_collect_or_fallback cluster '{"enabled":false,"name":null,"node_count":null,"quorate":null,"nodes":[]}' pma_collect_cluster)"
cpu_json="$(pma_collect_or_fallback cpu '{"usage_percent":null,"load_average":{"1m":null,"5m":null,"15m":null},"frequency_mhz":null,"sockets":null,"cores":null,"threads":null,"model":null,"governor":null,"virtualization_enabled":null,"per_core":[]}' pma_collect_cpu)"
memory_json="$(pma_collect_or_fallback memory '{"total_bytes":null,"used_bytes":null,"available_bytes":null,"cache_bytes":null,"buffers_bytes":null,"used_percent":null,"swap_total_bytes":null,"swap_used_bytes":null,"swap_used_percent":null}' pma_collect_memory)"
network_json="$(pma_collect_or_fallback network '[]' pma_collect_network)"
filesystems_json="$(pma_collect_or_fallback filesystems '[]' pma_collect_filesystems)"
storage_json="$(pma_collect_or_fallback storage '[]' pma_collect_storage)"
disks_json="$(pma_collect_or_fallback disks '[]' pma_collect_disks)"
sensors_json="$(pma_collect_or_fallback sensors '{"temperatures":[],"fans":[],"voltages":[],"power":[]}' pma_collect_sensors)"
virtualization_json="$(pma_collect_or_fallback virtualization '{"vms":[],"containers":[]}' pma_collect_virtualization)"
pma_debug "render json"

module_errors_json="$(jq -s '.' "$module_errors_file")"
collection_errors_json="$(
  jq -n \
    --argjson missing "$missing_tool_errors_json" \
    --argjson modules "$module_errors_json" \
    '$missing + $modules'
)"
collection_status="$(
  jq -n -r --argjson errors "$collection_errors_json" 'if ($errors | length) == 0 then "ok" else "partial" end'
)"

end_ms="$(date +%s%3N 2>/dev/null || printf '0')"
duration_ms=null
if [[ "$start_ms" != "0" && "$end_ms" != "0" && "$end_ms" -ge "$start_ms" ]]; then
  duration_ms=$((end_ms - start_ms))
fi

jq -n \
  --argjson schema "$schema_json" \
  --argjson capabilities "$capabilities_json" \
  --arg collection_status "$collection_status" \
  --argjson collection_errors "$collection_errors_json" \
  --argjson host "$host_json" \
  --argjson cluster "$cluster_json" \
  --argjson cpu "$cpu_json" \
  --argjson memory "$memory_json" \
  --argjson network "$network_json" \
  --argjson filesystems "$filesystems_json" \
  --argjson storage "$storage_json" \
  --argjson disks "$disks_json" \
  --argjson sensors "$sensors_json" \
  --argjson virtualization "$virtualization_json" \
  --arg generated_at "$generated_at" \
  --argjson duration_ms "$duration_ms" \
  '{
    schema: $schema,
    collection: {
      status: $collection_status,
      generated_at: $generated_at,
      duration_ms: $duration_ms,
      errors: $collection_errors
    },
    capabilities: $capabilities,
    host: $host,
    cluster: $cluster,
    cpu: $cpu,
    memory: $memory,
    network: $network,
    filesystems: $filesystems,
    storage: $storage,
    disks: $disks,
    sensors: $sensors,
    virtualization: $virtualization
  }'
