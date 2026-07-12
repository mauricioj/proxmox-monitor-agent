#!/usr/bin/env bash

pma_collect_filesystems() {
  pma_debug "filesystems: start"
  if ! pma_command_exists findmnt; then
    pma_debug "filesystems: findmnt missing"
    jq -n '[]'
    return
  fi

  local findmnt_json
  pma_debug "filesystems: findmnt"
  findmnt_json="$(pma_run findmnt -J -b -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL 2>/dev/null || true)"
  if [[ -z "$findmnt_json" ]]; then
    pma_debug "filesystems: empty findmnt"
    jq -n '[]'
    return
  fi

  pma_debug "filesystems: render"
  jq '
    def relevant_mount:
      (.target // "") as $target
      | (.fstype // "") as $fstype
      | (
          [
              "proc",
              "sysfs",
              "tmpfs",
              "devtmpfs",
              "devpts",
              "cgroup",
              "cgroup2",
              "securityfs",
              "debugfs",
              "tracefs",
              "overlay",
              "squashfs",
              "rpc_pipefs",
              "autofs",
              "mqueue",
              "hugetlbfs",
              "fusectl",
              "fuse",
              "lxcfs"
            ]
          | index($fstype)
          | not
        )
      and (
        $target
        | test("^/(proc|sys|dev|run)(/|$)|^/var/lib/lxcfs(/|$)|^/etc/pve$")
        | not
      );

    def flatten_mounts:
      .[]? as $item
      | $item,
        (($item.children // []) | flatten_mounts);

    [
      .filesystems
      | flatten_mounts
      | select(relevant_mount)
      | {
          id: ("fs-" + (if .target == "/" then "root" else (.target | gsub("[^A-Za-z0-9]+"; "-") | sub("^-"; "") | sub("-$"; "")) end)),
          mountpoint: .target,
          source: (.source // null),
          type: (.fstype // null),
          total_bytes: (.size // null),
          used_bytes: (.used // null),
          available_bytes: (.avail // null),
          used_percent: (if (.size // 0) == 0 or .used == null then null else (((.used / .size) * 10000) | round) / 100 end)
        }
    ]' <<<"$findmnt_json"
}
