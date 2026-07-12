#!/usr/bin/env bash
set -euo pipefail

json_file="${1:-tests/fixtures/schema-v1-example.json}"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || fail "jq is required"
}

assert_jq() {
  local expression="$1"
  local message="$2"
  jq -e "$expression" "$json_file" >/dev/null || fail "$message"
}

require_jq
jq empty "$json_file" || fail "invalid JSON: $json_file"

assert_jq '.schema.name == "pma.metrics"' 'schema.name must be pma.metrics'
assert_jq '.schema.version == 1' 'schema.version must be 1'

assert_jq '.collection.status | IN("ok", "partial", "failed")' 'collection.status must be ok, partial, or failed'
assert_jq '.collection.generated_at | type == "string"' 'collection.generated_at must be a string'
assert_jq '.collection.errors | type == "array"' 'collection.errors must be an array'

assert_jq '.capabilities.tools | type == "object"' 'capabilities.tools must be an object'
assert_jq '.capabilities.features | type == "object"' 'capabilities.features must be an object'
assert_jq '.capabilities.missing_tools | type == "array"' 'capabilities.missing_tools must be an array'

for tool in jq pvesh lsblk findmnt ip sensors smartctl nvme zpool zfs qm pct; do
  assert_jq ".capabilities.tools.$tool | type == \"boolean\"" "capabilities.tools.$tool must be boolean"
done

for feature in cluster sensors storage disks virtualization; do
  assert_jq ".capabilities.features.$feature | type == \"boolean\"" "capabilities.features.$feature must be boolean"
done

assert_jq '.host.id | type == "string" and length > 0' 'host.id must be a non-empty string'
assert_jq '.host.id != "uninitialized"' 'generated host.id must be initialized'
assert_jq '.host.hostname | type == "string" and length > 0' 'host.hostname must be a non-empty string'

assert_jq '.cluster.enabled | type == "boolean"' 'cluster.enabled must be boolean'
assert_jq '.cluster.nodes | type == "array"' 'cluster.nodes must be an array'

assert_jq '.cpu.load_average | type == "object"' 'cpu.load_average must be an object'
assert_jq '.cpu.load_average["1m"] == null or (.cpu.load_average["1m"] | type == "number")' 'cpu load 1m must be number or null'
assert_jq '.cpu.per_core | type == "array"' 'cpu.per_core must be an array'

assert_jq '.memory | type == "object"' 'memory must be an object'
assert_jq '.memory.total_bytes == null or (.memory.total_bytes | type == "number")' 'memory.total_bytes must be numeric or null'
assert_jq '.network | type == "array"' 'network must be an array'
assert_jq '.filesystems | type == "array"' 'filesystems must be an array'
assert_jq '.storage | type == "array"' 'storage must be an array'
assert_jq '.disks | type == "array"' 'disks must be an array'

assert_jq '.sensors.temperatures | type == "array"' 'sensors.temperatures must be an array'
assert_jq '.sensors.fans | type == "array"' 'sensors.fans must be an array'
assert_jq '.sensors.voltages | type == "array"' 'sensors.voltages must be an array'
assert_jq '.sensors.power | type == "array"' 'sensors.power must be an array'

assert_jq '.virtualization.vms | type == "array"' 'virtualization.vms must be an array'
assert_jq '.virtualization.containers | type == "array"' 'virtualization.containers must be an array'

assert_jq 'all(.network[]?; (.id | startswith("net-")) and (.name | type == "string"))' 'network items must have net-* ids and names'
assert_jq 'all(.disks[]?; (.id | type == "string") and (.id_persistent | type == "boolean"))' 'disk items must have id and id_persistent'
assert_jq 'all(.virtualization.vms[]?; (.id == ("vm-" + (.vmid | tostring))))' 'VM ids must match vm-<vmid>'
assert_jq 'all(.virtualization.containers[]?; (.id == ("lxc-" + (.ctid | tostring))))' 'LXC ids must match lxc-<ctid>'

printf 'PASS: schema contract valid for %s\n' "$json_file"
