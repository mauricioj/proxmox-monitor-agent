#!/usr/bin/env bash

pma_disk_by_id_path() {
  local dev_name="$1"
  local candidate
  pma_debug "disks: by-id lookup for $dev_name"
  for candidate in /dev/disk/by-id/*; do
    [[ -e "$candidate" ]] || continue
    if [[ "$(readlink -f "$candidate" 2>/dev/null)" == "/dev/$dev_name" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

pma_collect_disks() {
  pma_debug "disks: start"
  if ! pma_command_exists lsblk; then
    pma_debug "disks: lsblk missing"
    jq -n '[]'
    return
  fi

  local lsblk_json
  pma_debug "disks: lsblk"
  lsblk_json="$(pma_run lsblk -J -b -d -o NAME,PATH,MODEL,SERIAL,WWN,TRAN,TYPE,SIZE,ROTA,RM 2>/dev/null || true)"
  if [[ -z "$lsblk_json" ]]; then
    pma_debug "disks: empty lsblk"
    jq -n '[]'
    return
  fi

  pma_debug "disks: render"
  jq -c '.blockdevices[]? | select(.type == "disk")' <<<"$lsblk_json" | while read -r disk; do
    local name by_id id persistent disk_type rota transport
    name="$(jq -r '.name' <<<"$disk")"
    pma_debug "disks: item $name"
    transport="$(jq -r '.tran // empty' <<<"$disk")"
    rota="$(jq -r '.rota // empty' <<<"$disk")"
    by_id="$(pma_disk_by_id_path "$name" || true)"
    if [[ -n "$by_id" ]]; then
      id="disk-by-id-$(basename "$by_id")"
      persistent=true
    else
      id="disk-$name"
      persistent=false
    fi
    if [[ "$transport" == "nvme" ]]; then
      disk_type="nvme"
    elif [[ "$rota" == "0" ]]; then
      disk_type="ssd"
    elif [[ "$rota" == "1" ]]; then
      disk_type="hdd"
    else
      disk_type="unknown"
    fi
    jq -n --argjson disk "$disk" --arg id "$id" --argjson persistent "$persistent" --arg by_id "$by_id" --arg disk_type "$disk_type" '{
      id: $id,
      id_persistent: $persistent,
      name: $disk.name,
      path: ($disk.path // null),
      by_id_path: (if $by_id == "" then null else $by_id end),
      model: ($disk.model // null),
      serial: ($disk.serial // null),
      wwn: ($disk.wwn // null),
      type: $disk_type,
      transport: ($disk.tran // null),
      size_bytes: ($disk.size // null),
      removable: (if $disk.rm == null then null else ($disk.rm == true or $disk.rm == 1) end)
    }'
  done | jq -s '.'
}
