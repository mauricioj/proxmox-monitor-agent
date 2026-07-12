# Proxmox Monitor Agent

PMA is a lightweight Bash collector for Proxmox VE. It emits a single Schema v1 JSON snapshot with host, cluster, CPU, memory, network, filesystem, storage, disk, sensor, VM, and LXC data.

The agent does not store history or emit alerts. Consumers such as Home Assistant, Grafana, Prometheus, MQTT bridges, or Node-RED are responsible for history, dashboards, alerts, and actions.

PMA can be used in two modes:

- one-shot command output with `pma-metrics`;
- optional HTTP snapshot serving through systemd socket activation.

The HTTP server serves the latest JSON snapshot only. It does not run a collection on each HTTP request.

The root `network[]` array reports physical host interfaces only. Proxmox virtual links such as `vmbr*`, `tap*`, `veth*`, and firewall helper interfaces are filtered out. The root `filesystems[]` array reports relevant host mounts and filters pseudo/runtime mounts such as `/proc`, `/sys`, `/dev`, and `/run`.

## Requirements

- Bash
- jq
- systemd, only when installing the optional timer or HTTP socket
- Proxmox/Linux tools when available: `pvesh`, `lsblk`, `findmnt`, `ip`, `sensors`, `smartctl`, `nvme`, `zpool`, `zfs`, `qm`, `pct`

Missing optional tools are reported in `capabilities.missing_tools` and `collection.errors`.

## Usage

Print metrics to stdout:

```bash
bash agent/metrics.sh
```

Validate output:

```bash
bash agent/metrics.sh | jq .
```

Use a test host-id path:

```bash
PMA_HOST_ID_FILE=.pma-test/host_id bash agent/metrics.sh
```

## Installation

Run the interactive installer directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/mauricioj/proxmox-monitor-agent/main/install.sh | sudo bash
```

The installer downloads the agent package, asks where to install it, and asks before installing optional dependencies, a systemd timer, or the HTTP snapshot server.

If you already cloned the repository, you can run the same installer locally:

```bash
bash install.sh
```

By default, the installer:

- copies the agent to `/opt/proxmox-monitor-agent`;
- creates the `pma-metrics` command at `/usr/local/bin/pma-metrics`;
- does not install a systemd timer;
- does not install the HTTP snapshot server;
- does not install packages without explicit confirmation.

Interactive prompts:

```text
Install directory [/opt/proxmox-monitor-agent]:
Check missing dependencies? [Y/n]:
Install missing dependencies with apt? [y/N]:
Create command symlink /usr/local/bin/pma-metrics? [Y/n]:
Install systemd timer? [y/N]:
Collection interval [60s]:
Install HTTP snapshot server? [y/N]:
HTTP listen address [0.0.0.0]:
HTTP port [9782]:
HTTP server requires a metrics snapshot. Install collection timer? [Y/n]:
Run test collection now? [Y/n]:
```

Some prompts only appear when relevant.

## Snapshot Timer

If the systemd timer is enabled, PMA writes the latest snapshot to:

```text
/run/pma/metrics.json
```

The timer uses the configured collection interval, defaulting to `60s`.

Useful commands:

```bash
systemctl status pma-metrics.timer --no-pager
systemctl start pma-metrics.service
jq '.collection.status, .collection.errors' /run/pma/metrics.json
```

The optional test collection validates that the command can produce JSON. It does not save `/run/pma/metrics.json` unless you install the systemd timer. To save a manual snapshot:

```bash
pma-metrics | jq . > /tmp/pma-metrics.json
```

## HTTP Snapshot Server

The optional HTTP snapshot server uses systemd socket activation and does not add a new runtime dependency. The default listen address is `0.0.0.0` and the default port is `9782`, both of which can be changed during installation.

When enabled, the server exposes:

```text
GET /metrics.json
GET /health
```

The HTTP server serves the latest `/run/pma/metrics.json` snapshot. It does not run a collection on each request.

Example health response:

```json
{
  "status": "ok",
  "snapshot_exists": true,
  "snapshot_path": "/run/pma/metrics.json",
  "collection_interval_seconds": 60
}
```

Test locally on the Proxmox host:

```bash
curl -fsS http://127.0.0.1:9782/health | jq .
curl -fsS http://127.0.0.1:9782/metrics.json | jq '.schema, .host.hostname, .collection.status'
```

Test from another machine on the LAN:

```bash
curl -fsS http://<proxmox-ip>:9782/health | jq .
curl -fsS http://<proxmox-ip>:9782/metrics.json | jq '.host.hostname, .collection.status'
```

Useful service checks:

```bash
systemctl status pma-http.socket --no-pager
journalctl -u 'pma-http@*' -n 50 --no-pager
```

## Runtime Configuration

Collector environment variables:

| Variable | Default | Purpose |
|---|---:|---|
| `PMA_HOST_ID_FILE` | `/var/lib/pma/host_id` | Stable host id file path. |
| `PMA_MODULE_TIMEOUT_SECONDS` | `15` | Timeout for each collector module. |
| `PMA_COMMAND_TIMEOUT_SECONDS` | `5` | Timeout for external commands used by modules. |
| `PMA_CPU_SAMPLE_INTERVAL_SECONDS` | `0.2` | Delay between `/proc/stat` samples for CPU usage. |
| `PMA_DEBUG` | `0` | Prints module progress logs when set to `1`. |
| `PMA_TRACE` | `0` | Enables shell tracing when set to `1`. |

Installer override variables:

| Variable | Default | Purpose |
|---|---:|---|
| `PMA_INSTALL_ROOT` | `/opt/proxmox-monitor-agent` | Install directory. |
| `PMA_SYMLINK_PATH` | `/usr/local/bin/pma-metrics` | Command wrapper path. |
| `PMA_SYSTEMD_DIR` | `/etc/systemd/system` | systemd unit output directory. |
| `PMA_HTTP_LISTEN_ADDRESS` | `0.0.0.0` | Default HTTP bind address shown by installer. |
| `PMA_HTTP_PORT` | `9782` | Default HTTP port shown by installer. |
| `PMA_TEST_TIMEOUT_SECONDS` | `60` | Post-install test collection timeout. |
| `PMA_REPO_URL` | GitHub repo URL | Source repo for bootstrap installs. |
| `PMA_REPO_REF` | `main` | Git ref for bootstrap archive installs. |
| `PMA_ARCHIVE_URL` | derived | Full source archive URL for bootstrap installs. |

HTTP handler environment variables:

| Variable | Default | Purpose |
|---|---:|---|
| `PMA_METRICS_FILE` | `/run/pma/metrics.json` | Snapshot file served by `/metrics.json`. |
| `PMA_COLLECTION_INTERVAL_SECONDS` | `60` | Interval reported by `/health`. |

If collection is slow or appears stuck, enable module progress logs:

```bash
PMA_DEBUG=1 pma-metrics > /tmp/pma-metrics.json
```

For shell-level tracing from the first line of the collector:

```bash
PMA_TRACE=1 PMA_DEBUG=1 pma-metrics > /tmp/pma-metrics.json
```

Each collector module is bounded by a 15 second timeout by default, and external commands used inside collectors are bounded by a 5 second timeout by default. Override them when needed:

```bash
PMA_MODULE_TIMEOUT_SECONDS=30 PMA_COMMAND_TIMEOUT_SECONDS=15 pma-metrics | jq . > /tmp/pma-metrics.json
```

## Consumer Integration

PMA is intentionally consumer-neutral. Home Assistant, Grafana, Prometheus bridges, Node-RED flows, or custom scripts should consume the JSON snapshot and own their own history, dashboards, alerts, and actions.

Home Assistant integration notes are documented in:

```text
docs/integrations/home-assistant.md
```

## Tests

```bash
bash tests/run.sh
```

The schema contract is documented in:

```text
docs/schema-v1.md
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
