#!/usr/bin/env bash

pma_is_physical_network_interface() {
  local ifname="$1"
  local sysfs_root="${PMA_PHYSICAL_NET_PATH:-/sys/class/net}"

  case "$ifname" in
    lo | vmbr* | tap* | veth* | fwbr* | fwln* | fwpr* )
      return 1
      ;;
  esac

  [[ -e "$sysfs_root/$ifname/device" ]]
}

pma_collect_physical_network_names() {
  local sysfs_root="${PMA_PHYSICAL_NET_PATH:-/sys/class/net}"
  local iface

  if [[ ! -d "$sysfs_root" ]]; then
    return
  fi

  for iface in "$sysfs_root"/*; do
    [[ -e "$iface" ]] || continue
    iface="$(basename "$iface")"
    if pma_is_physical_network_interface "$iface"; then
      printf '%s\n' "$iface"
    fi
  done
}

pma_collect_network() {
  pma_debug "network: start"
  if ! pma_command_exists ip; then
    pma_debug "network: ip missing"
    jq -n '[]'
    return
  fi

  local ip_json
  pma_debug "network: ip link"
  ip_json="$(pma_run ip -j -s link 2>/dev/null || true)"
  if [[ -z "$ip_json" ]]; then
    pma_debug "network: empty ip output"
    jq -n '[]'
    return
  fi

  local physical_names_json
  physical_names_json="$(pma_collect_physical_network_names | jq -R . | jq -s .)"

  pma_debug "network: render"
  jq --argjson physical_names "$physical_names_json" '[
    .[]?
    | select(.ifname as $ifname | $physical_names | index($ifname))
    | {
        id: ("net-" + .ifname),
        name: .ifname,
        mac: (.address // null),
        mtu: (.mtu // null),
        state: (.operstate // null),
        speed_mbps: null,
        duplex: null,
        bridge: null,
        vlan: null,
        rx_bytes: (.stats64.rx.bytes // .stats.rx.bytes // null),
        tx_bytes: (.stats64.tx.bytes // .stats.tx.bytes // null),
        rx_packets: (.stats64.rx.packets // .stats.rx.packets // null),
        tx_packets: (.stats64.tx.packets // .stats.tx.packets // null),
        rx_errors: (.stats64.rx.errors // .stats.rx.errors // null),
        tx_errors: (.stats64.tx.errors // .stats.tx.errors // null)
      }
  ]' <<<"$ip_json"
}
