# PMA Metrics Schema v1

PMA emits a single JSON snapshot with host, cluster, CPU, memory, network, filesystem, storage, disk, sensor, VM, and LXC data.

The agent is a snapshot collector. It does not keep history, compute trends, expose alerts, or perform automation actions. Consumers such as Home Assistant, Grafana, Prometheus bridges, MQTT bridges, Node-RED flows, or custom scripts are responsible for historical storage, dashboards, alerting, and actions.

## Root Object

| Field | Type | Required | Description |
|---|---|---:|---|
| `schema` | object | yes | Schema identity and version. |
| `collection` | object | yes | Diagnostic information about the current collection. |
| `capabilities` | object | yes | Tool and feature availability. |
| `host` | object | yes | Host and hardware identity. |
| `cluster` | object | yes | Proxmox cluster status. |
| `cpu` | object | yes | Host CPU information and current usage. |
| `memory` | object | yes | Host memory and swap information. |
| `network` | array | yes | Physical host network interfaces. |
| `filesystems` | array | yes | Relevant host mounts. |
| `storage` | array | yes | Proxmox storage definitions and local status. |
| `disks` | array | yes | Block devices with identity and capacity. |
| `sensors` | object | yes | Normalized hardware sensors. |
| `virtualization` | object | yes | VM and LXC inventory and current state. |

## Global Rules

- Fields defined by Schema v1 should be predictable.
- If a scalar value cannot be collected, it should be `null`.
- If a list cannot be collected, it should be an empty array.
- Collection problems should be reported in `collection.errors`, `capabilities`, or `capabilities.missing_tools`.
- Sizes and counters are bytes unless explicitly documented otherwise.
- CPU and utilization values are percentages from `0` to `100`.
- Temperatures are Celsius.
- Durations are seconds except `collection.duration_ms`.
- Timestamps are ISO-8601 UTC.

## `schema`

```json
{
  "name": "pma.metrics",
  "version": 1
}
```

## `collection`

| Field | Type | Description |
|---|---|---|
| `status` | string | `ok`, `partial`, or `failed`. |
| `generated_at` | string | ISO-8601 UTC timestamp. |
| `duration_ms` | number or null | Total collection duration in milliseconds. |
| `errors` | array | Structured collection errors. |

`partial` means the snapshot is usable, but at least one module, tool, or data source was unavailable.

## `capabilities`

Tracks command and feature availability.

Initial command keys:

```text
jq, pvesh, lsblk, findmnt, ip, sensors, smartctl, nvme, zpool, zfs, qm, pct
```

Initial feature keys:

```text
cluster, sensors, storage, disks, virtualization
```

## Host Metrics

The `host`, `cpu`, and `memory` objects describe the Proxmox host itself.

CPU usage is calculated from two `/proc/stat` samples. The sample interval defaults to `0.2` seconds and can be changed with `PMA_CPU_SAMPLE_INTERVAL_SECONDS`.

## Network

`network[]` contains physical host network interfaces only.

Proxmox virtual interfaces such as `vmbr*`, `tap*`, `veth*`, `fwbr*`, `fwln*`, and `fwpr*` are excluded from this root array to avoid noisy consumer entity discovery.

Network counters are raw cumulative counters. Rates are left to consumers because rates require multiple samples or a measurement window.

## Filesystems

`filesystems[]` contains relevant host mounts.

Pseudo and runtime mounts such as `/proc`, `/sys`, `/dev`, `/run`, `/etc/pve`, `tmpfs`, `proc`, `sysfs`, `fuse`, and similar infrastructure mounts are excluded.

## Storage

`storage[]` represents Proxmox storage definitions and local node status.

The collector combines:

```text
pvesh get /storage --output-format json
pvesh get /nodes/<node>/storage --output-format json
```

This allows logical storages such as LVM-thin to report `total_bytes`, `used_bytes`, `available_bytes`, and `used_percent`.

## Sensors

`sensors` normalizes `sensors -j` output into:

- `temperatures[]`;
- `fans[]`;
- `voltages[]`;
- `power[]`.

Common item fields:

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable best-effort sensor ID. |
| `label` | string | Display label, such as `Core 0`. |
| `source` | string | Source chip/device. |
| `raw_label` | string | Original key, such as `temp2_input`. |
| `value` | number or null | Current sensor value. |

## Virtualization

`virtualization.vms[]` and `virtualization.containers[]` provide current VM/LXC inventory and state.

VM IDs use:

```text
vm-<vmid>
```

LXC IDs use:

```text
lxc-<ctid>
```

Guest-agent data, guest filesystems, guest network interfaces, and advanced per-guest metrics are future extensions and are not required by Schema v1.

## Example

See:

```text
tests/fixtures/schema-v1-example.json
```
