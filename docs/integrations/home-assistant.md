# Home Assistant Integration Notes

PMA is intentionally separate from Home Assistant. The agent exposes a generic HTTP/JSON contract, and a Home Assistant custom integration can consume that contract without requiring the Proxmox host to know about MQTT or Home Assistant internals.

## HTTP Endpoints

Default base URL:

```text
http://<proxmox-host>:9782
```

The port can be changed during PMA installation.

### `GET /health`

Returns lightweight server health and collection interval metadata:

```json
{
  "status": "ok",
  "snapshot_exists": true,
  "snapshot_path": "/run/pma/metrics.json",
  "collection_interval_seconds": 60
}
```

Home Assistant integrations should use `collection_interval_seconds` as a default polling hint when present.

### `GET /metrics.json`

Returns the latest PMA Schema v1 snapshot. The integration should validate:

- `schema.name == "pma.metrics"`;
- `schema.version == 1`.

If `/metrics.json` returns `503`, no snapshot exists yet. The integration should retry later and keep existing entities registered.

## Recommended Home Assistant Model

Use one config entry per Proxmox host and one `DataUpdateCoordinator` per config entry.

Recommended config flow fields:

- host;
- port, default `9782`;
- path, default `/metrics.json`;
- scan interval, default from `/health.collection_interval_seconds` or 60 seconds.

First-version authentication is not part of the PMA HTTP server contract.

## Devices

Create one main device for the Proxmox host.

Host device identifier:

```text
("proxmox_monitor_agent", host.id)
```

Create separate devices for VMs and LXCs.

VM device identifier:

```text
("proxmox_monitor_agent", host.id, "vm", vm.vmid)
```

LXC device identifier:

```text
("proxmox_monitor_agent", host.id, "lxc", container.ctid)
```

## Entity Identity

Use deterministic unique IDs rooted at `host.id`.

Suggested patterns:

```text
pma_<host.id>_<metric>
pma_<host.id>_<item.id>_<metric>
pma_<host.id>_vm_<vmid>_<metric>
pma_<host.id>_lxc_<ctid>_<metric>
```

Use PMA item `id` fields for dynamic arrays. Do not use display names when stable IDs exist.

## Dynamic Entities

When a new item appears in the snapshot, create the related entities.

When an item disappears, keep its entities registered and mark them unavailable. Do not delete automatically in the first version.

This avoids entity churn when disks, sensors, VMs, containers, or network interfaces are temporarily unavailable.

## Collection Status

The integration should treat `collection.status == "partial"` as usable data with diagnostics. It should not fail the whole coordinator update just because one collector module reported an error.

Recommended diagnostic entities:

- collection status;
- collection duration;
- generated timestamp;
- collection error count.

Detailed `collection.errors[]` can be exposed as diagnostics or attributes.
