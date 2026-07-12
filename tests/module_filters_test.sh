#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_jq() {
  local json_file="$1"
  local expression="$2"
  local message="$3"
  jq -e "$expression" "$json_file" >/dev/null || fail "$message"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
fake_net="$tmp_dir/sys/class/net"
mkdir -p "$fake_bin"
mkdir -p "$fake_net/lo" "$fake_net/eno1/device" "$fake_net/vmbr0" "$fake_net/tap100i0" "$fake_net/veth101i0"

cat >"$fake_bin/sensors" <<'SCRIPT'
#!/usr/bin/env bash
cat tests/fixtures/sensors-coretemp.json
SCRIPT

cat >"$fake_bin/ip" <<'SCRIPT'
#!/usr/bin/env bash
cat tests/fixtures/ip-link-proxmox.json
SCRIPT

cat >"$fake_bin/findmnt" <<'SCRIPT'
#!/usr/bin/env bash
cat tests/fixtures/findmnt-proxmox.json
SCRIPT

cat >"$fake_bin/pvesh" <<'SCRIPT'
#!/usr/bin/env bash
case "$*" in
  "get /storage --output-format json")
    cat tests/fixtures/storage-config.json
    ;;
  "get /nodes/pve-test/storage --output-format json")
    cat tests/fixtures/storage-node-status.json
    ;;
  *)
    printf '[]\n'
    ;;
esac
SCRIPT

cat >"$fake_bin/hostname" <<'SCRIPT'
#!/usr/bin/env bash
printf 'pve-test\n'
SCRIPT

chmod +x "$fake_bin/sensors" "$fake_bin/ip" "$fake_bin/findmnt" "$fake_bin/pvesh" "$fake_bin/hostname"

export PATH="$fake_bin:$PATH"
export PMA_PHYSICAL_NET_PATH="$fake_net"

sensors_output="$tmp_dir/sensors.json"
network_output="$tmp_dir/network.json"
filesystems_output="$tmp_dir/filesystems.json"
storage_output="$tmp_dir/storage.json"

(
  . agent/lib/util.sh
  . agent/lib/sensors.sh
  pma_collect_sensors
) >"$sensors_output"

assert_jq "$sensors_output" '.temperatures | length == 5' "coretemp fixture must produce five temperature sensors"
assert_jq "$sensors_output" '.temperatures[] | select(.label == "Package id 0" and .raw_label == "temp1_input" and .value == 75)' "package temperature must be parsed"
assert_jq "$sensors_output" '.fans | length == 0' "coretemp fixture must not produce fans"

(
  . agent/lib/util.sh
  . agent/lib/network.sh
  pma_collect_network
) >"$network_output"

assert_jq "$network_output" 'length == 1' "network must include only physical host interfaces"
assert_jq "$network_output" '.[0].name == "eno1"' "network must keep the physical interface"
assert_jq "$network_output" 'all(.[]; (.name | test("^(lo|vmbr|tap|veth|fwbr|fwln|fwpr)") | not))' "network must filter virtual interfaces"

(
  . agent/lib/util.sh
  . agent/lib/filesystems.sh
  pma_collect_filesystems
) >"$filesystems_output"

assert_jq "$filesystems_output" 'length == 2' "filesystems must include only relevant host mounts"
assert_jq "$filesystems_output" 'any(.[]; .mountpoint == "/")' "filesystems must keep root"
assert_jq "$filesystems_output" 'any(.[]; .mountpoint == "/var/lib/vz")' "filesystems must keep Proxmox storage mount"
assert_jq "$filesystems_output" 'all(.[]; (.mountpoint | test("^/(proc|run|sys|dev)(/|$)") | not))' "filesystems must filter pseudo and runtime mounts"

(
  . agent/lib/util.sh
  . agent/lib/storage.sh
  pma_collect_storage
) >"$storage_output"

assert_jq "$storage_output" 'length == 1' "storage must include configured Proxmox storage"
assert_jq "$storage_output" '.[0].id == "ssd240"' "storage id must be preserved"
assert_jq "$storage_output" '.[0].type == "lvmthin"' "storage type must be preserved"
assert_jq "$storage_output" '.[0].active == true' "storage active status must come from node status"
assert_jq "$storage_output" '.[0].shared == false' "storage shared status must come from node status"
assert_jq "$storage_output" '.[0].total_bytes == 239817719808' "storage total must come from node status"
assert_jq "$storage_output" '.[0].used_bytes == 42519681721' "storage used must come from node status"
assert_jq "$storage_output" '.[0].available_bytes == 197298038087' "storage available must come from node status"
assert_jq "$storage_output" '.[0].used_percent == 17.73' "storage used percent must be derived from node status"
assert_jq "$storage_output" '.[0].content == ["rootdir", "images"]' "storage content must come from config order"

printf 'PASS: module filters\n'
