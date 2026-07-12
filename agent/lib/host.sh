#!/usr/bin/env bash

pma_host_id_file() {
  printf '%s\n' "${PMA_HOST_ID_FILE:-/var/lib/pma/host_id}"
}

pma_get_or_create_host_id() {
  local id_file id_dir generated
  pma_debug "host: resolve host id"
  id_file="$(pma_host_id_file)"
  id_dir="$(dirname "$id_file")"

  if [[ -s "$id_file" ]]; then
    tr -d '\r\n' < "$id_file"
    return
  fi

  generated="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || true)"
  if [[ -z "$generated" ]]; then
    generated="host-$(date -u +%s)"
  fi

  mkdir -p "$id_dir"
  printf '%s\n' "$generated" > "$id_file"
  printf '%s\n' "$generated"
}

pma_collect_host() {
  local host_id hostname node_name proxmox_version kernel_version uptime_seconds architecture boot_mode timezone manufacturer model serial

  pma_debug "host: start"
  host_id="$(pma_get_or_create_host_id)"
  pma_debug "host: hostname"
  hostname="$(hostname 2>/dev/null || printf unknown)"
  node_name="$hostname"
  pma_debug "host: pveversion"
  proxmox_version="$(pveversion 2>/dev/null | awk '{print $1}' || true)"
  pma_debug "host: kernel"
  kernel_version="$(uname -r 2>/dev/null || true)"
  uptime_seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || true)"
  architecture="$(uname -m 2>/dev/null || true)"
  pma_debug "host: timezone"
  timezone="$(pma_run timedatectl show -p Timezone --value 2>/dev/null || true)"

  if [[ -d /sys/firmware/efi ]]; then
    boot_mode="efi"
  else
    boot_mode="bios"
  fi

  manufacturer="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  model="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  serial="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"

  pma_debug "host: render"
  jq -n \
    --arg id "$host_id" \
    --arg hostname "$hostname" \
    --arg node_name "$node_name" \
    --arg proxmox_version "$proxmox_version" \
    --arg kernel_version "$kernel_version" \
    --arg uptime_seconds "$uptime_seconds" \
    --arg architecture "$architecture" \
    --arg boot_mode "$boot_mode" \
    --arg timezone "$timezone" \
    --arg manufacturer "$manufacturer" \
    --arg model "$model" \
    --arg serial "$serial" \
    '{
      id: $id,
      hostname: $hostname,
      node_name: (if $node_name == "" then null else $node_name end),
      proxmox_version: (if $proxmox_version == "" then null else $proxmox_version end),
      kernel_version: (if $kernel_version == "" then null else $kernel_version end),
      uptime_seconds: (if $uptime_seconds == "" then null else ($uptime_seconds | tonumber) end),
      architecture: (if $architecture == "" then null else $architecture end),
      boot_mode: (if $boot_mode == "" then null else $boot_mode end),
      timezone: (if $timezone == "" then null else $timezone end),
      manufacturer: (if $manufacturer == "" then null else $manufacturer end),
      model: (if $model == "" then null else $model end),
      serial: (if $serial == "" then null else $serial end)
    }'
}
