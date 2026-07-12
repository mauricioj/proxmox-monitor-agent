#!/usr/bin/env bash

pma_collect_virtualization() {
  local resources vms containers

  pma_debug "virtualization: start"
  if ! pma_command_exists pvesh; then
    pma_debug "virtualization: pvesh missing"
    jq -n '{vms:[], containers:[]}'
    return
  fi

  pma_debug "virtualization: pvesh /cluster/resources"
  resources="$(pma_run pvesh get /cluster/resources --type vm --output-format json 2>/dev/null || true)"
  if [[ -z "$resources" || "$resources" == "null" ]]; then
    pma_debug "virtualization: empty resources"
    jq -n '{vms:[], containers:[]}'
    return
  fi

  pma_debug "virtualization: render vms"
  vms="$(jq '[
    .[]?
    | select(.vmid != null and (.type == "qemu" or .type == "vm"))
    | {
        id: ("vm-" + (.vmid | tostring)),
        vmid: .vmid,
        name: (.name // null),
        status: (.status // null),
        node: (.node // null),
        cpu_usage_percent: (if .cpu == null then null else (((.cpu * 100) * 100) | round) / 100 end),
        memory_used_bytes: (.mem // null),
        memory_total_bytes: (.maxmem // null),
        uptime_seconds: (.uptime // null),
        tags: ((.tags // "") | split(";") | map(select(length > 0)))
      }
  ]' <<<"$resources")"

  pma_debug "virtualization: render containers"
  containers="$(jq '[
    .[]?
    | select(.vmid != null and .type == "lxc")
    | {
        id: ("lxc-" + (.vmid | tostring)),
        ctid: .vmid,
        name: (.name // null),
        status: (.status // null),
        node: (.node // null),
        cpu_usage_percent: (if .cpu == null then null else (((.cpu * 100) * 100) | round) / 100 end),
        memory_used_bytes: (.mem // null),
        memory_total_bytes: (.maxmem // null),
        uptime_seconds: (.uptime // null),
        tags: ((.tags // "") | split(";") | map(select(length > 0)))
      }
  ]' <<<"$resources")"

  pma_debug "virtualization: render"
  jq -n --argjson vms "$vms" --argjson containers "$containers" '{vms:$vms, containers:$containers}'
}
