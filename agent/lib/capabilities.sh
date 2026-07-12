#!/usr/bin/env bash

pma_bool_for_command() {
  if pma_command_exists "$1"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

pma_collect_capabilities() {
  local tools_json
  tools_json="$(
    jq -n \
      --argjson jq "$(pma_bool_for_command jq)" \
      --argjson pvesh "$(pma_bool_for_command pvesh)" \
      --argjson lsblk "$(pma_bool_for_command lsblk)" \
      --argjson findmnt "$(pma_bool_for_command findmnt)" \
      --argjson ip "$(pma_bool_for_command ip)" \
      --argjson sensors "$(pma_bool_for_command sensors)" \
      --argjson smartctl "$(pma_bool_for_command smartctl)" \
      --argjson nvme "$(pma_bool_for_command nvme)" \
      --argjson zpool "$(pma_bool_for_command zpool)" \
      --argjson zfs "$(pma_bool_for_command zfs)" \
      --argjson qm "$(pma_bool_for_command qm)" \
      --argjson pct "$(pma_bool_for_command pct)" \
      '{
        jq:$jq, pvesh:$pvesh, lsblk:$lsblk, findmnt:$findmnt, ip:$ip,
        sensors:$sensors, smartctl:$smartctl, nvme:$nvme, zpool:$zpool,
        zfs:$zfs, qm:$qm, pct:$pct
      }'
  )"

  jq -n --argjson tools "$tools_json" '{
    tools: $tools,
    features: {
      cluster: $tools.pvesh,
      sensors: $tools.sensors,
      storage: $tools.pvesh,
      disks: $tools.lsblk,
      virtualization: ($tools.pvesh or $tools.qm or $tools.pct)
    },
    missing_tools: ($tools | to_entries | map(select(.value == false) | .key))
  }'
}
