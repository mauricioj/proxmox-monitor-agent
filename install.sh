#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

script_source="${BASH_SOURCE[0]-}"
if [[ -n "$script_source" && "$script_source" != "bash" && "$script_source" != "-" ]]; then
  repo_root="$(cd "$(dirname "$script_source")" && pwd)"
else
  repo_root="$(pwd)"
fi

repo_url="${PMA_REPO_URL:-https://github.com/mauricioj/proxmox-monitor-agent}"
repo_ref="${PMA_REPO_REF:-main}"
archive_url="${PMA_ARCHIVE_URL:-$repo_url/archive/refs/heads/$repo_ref.tar.gz}"
default_install_root="${PMA_INSTALL_ROOT:-/opt/proxmox-monitor-agent}"
default_symlink_path="${PMA_SYMLINK_PATH:-/usr/local/bin/pma-metrics}"
systemd_dir="${PMA_SYSTEMD_DIR:-/etc/systemd/system}"
test_timeout_seconds="${PMA_TEST_TIMEOUT_SECONDS:-60}"
default_http_listen_address="${PMA_HTTP_LISTEN_ADDRESS:-0.0.0.0}"
default_http_port="${PMA_HTTP_PORT:-9782}"
install_timer=0
install_http=0
bootstrap_tmp=""

cleanup() {
  if [[ -n "$bootstrap_tmp" && -d "$bootstrap_tmp" ]]; then
    rm -rf "$bootstrap_tmp"
  fi
}

trap cleanup EXIT

prompt() {
  local message="$1"
  local default_value="$2"
  local response
  response="$(read_prompt "$message")"
  printf '%s\n' "${response:-$default_value}"
}

prompt_yes_no() {
  local message="$1"
  local default_value="$2"
  local response
  response="$(read_prompt "$message")"
  response="${response:-$default_value}"

  case "$response" in
    y | Y | yes | YES) return 0 ;;
    n | N | no | NO) return 1 ;;
    *) return 1 ;;
  esac
}

read_prompt() {
  local message="$1"
  local response=""

  if [[ "${PMA_NO_TTY:-0}" != 1 && -r /dev/tty && -w /dev/tty ]]; then
    printf '%s' "$message" >/dev/tty
    IFS= read -r response </dev/tty || response=""
  else
    read -r -p "$message" response || response=""
  fi

  printf '%s\n' "$response"
}

require_source_tree() {
  if [[ -f "$repo_root/agent/metrics.sh" ]]; then
    return 0
  fi

  bootstrap_source_tree

  if [[ ! -f "$repo_root/agent/metrics.sh" ]]; then
    printf 'ERROR: agent/metrics.sh not found after source resolution\n' >&2
    exit 1
  fi
}

download_archive() {
  local url="$1"
  local output_path="$2"

  if [[ "$url" == file://* ]]; then
    cp "${url#file://}" "$output_path"
  elif command_exists curl; then
    curl -fsSL "$url" -o "$output_path"
  elif command_exists wget; then
    wget -qO "$output_path" "$url"
  else
    printf 'ERROR: curl or wget is required to download %s\n' "$url" >&2
    exit 1
  fi
}

bootstrap_source_tree() {
  command_exists tar || {
    printf 'ERROR: tar is required to extract %s\n' "$archive_url" >&2
    exit 1
  }

  bootstrap_tmp="$(mktemp -d)"
  local archive_path="$bootstrap_tmp/source.tar.gz"

  printf 'Local agent source not found. Downloading PMA from %s\n' "$archive_url"
  download_archive "$archive_url" "$archive_path"
  tar -xzf "$archive_path" -C "$bootstrap_tmp"

  local metrics_path
  metrics_path="$(find "$bootstrap_tmp" -path '*/agent/metrics.sh' -type f | head -n 1)"
  if [[ -z "$metrics_path" ]]; then
    printf 'ERROR: downloaded archive does not contain agent/metrics.sh\n' >&2
    exit 1
  fi

  repo_root="$(cd "$(dirname "$metrics_path")/.." && pwd)"
}

require_root_for_system_paths() {
  local install_root="$1"
  local symlink_path="$2"
  local needs_root=0

  [[ "$install_root" == /opt/* ]] && needs_root=1
  [[ "$symlink_path" == /usr/local/bin/* ]] && needs_root=1
  [[ "$install_timer" == 1 && "$systemd_dir" == /etc/systemd/system ]] && needs_root=1
  [[ "$install_http" == 1 && "$systemd_dir" == /etc/systemd/system ]] && needs_root=1

  if [[ "$needs_root" == 1 && "${EUID:-$(id -u)}" -ne 0 ]]; then
    printf 'ERROR: root is required for selected system paths\n' >&2
    exit 1
  fi
}

command_exists() {
  if [[ "${PMA_ASSUME_COMMANDS_PRESENT:-0}" == 1 ]]; then
    return 0
  fi
  command -v "$1" >/dev/null 2>&1
}

detect_missing_required() {
  if [[ "${PMA_SIMULATE_EMPTY_DEP_LINES:-0}" == 1 ]]; then
    printf '\n'
    return 0
  fi

  local missing=()
  command_exists bash || missing+=("bash")
  command_exists jq || missing+=("jq")
  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf '%s\n' "${missing[@]}"
  fi
}

detect_missing_optional_installable() {
  if [[ "${PMA_SIMULATE_EMPTY_DEP_LINES:-0}" == 1 ]]; then
    printf '\n'
    return 0
  fi

  local missing=()
  command_exists sensors || missing+=("lm-sensors")
  command_exists smartctl || missing+=("smartmontools")
  command_exists nvme || missing+=("nvme-cli")
  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf '%s\n' "${missing[@]}"
  fi
}

filter_nonempty_array() {
  local item
  for item in "$@"; do
    if [[ -n "$item" ]]; then
      printf '%s\n' "$item"
    fi
  done
}

install_packages() {
  local packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0

  if [[ "${PMA_SKIP_APT:-0}" == 1 ]]; then
    printf 'Skipping apt install because PMA_SKIP_APT=1\n'
    return 0
  fi

  if [[ -n "${PMA_APT_LOG:-}" ]]; then
    printf 'apt update\n' >>"$PMA_APT_LOG"
    printf 'apt install -y %s\n' "${packages[*]}" >>"$PMA_APT_LOG"
    return 0
  fi

  apt update
  apt install -y "${packages[@]}"
}

copy_agent() {
  local install_root="$1"
  printf 'Installing PMA agent to %s\n' "$install_root"
  mkdir -p "$install_root"
  rm -rf "$install_root/agent"
  cp -R "$repo_root/agent" "$install_root/agent"
  chmod +x "$install_root/agent/metrics.sh"
  if [[ -f "$install_root/agent/http.sh" ]]; then
    chmod +x "$install_root/agent/http.sh"
  fi
  printf 'Agent files installed\n'
}

create_command_wrapper() {
  local install_root="$1"
  local command_path="$2"
  printf 'Creating command wrapper at %s\n' "$command_path"
  mkdir -p "$(dirname "$command_path")"
  rm -f "$command_path"
  cat >"$command_path" <<WRAPPER
#!/usr/bin/env bash
exec "$install_root/agent/metrics.sh" "\$@"
WRAPPER
  chmod +x "$command_path"
  printf 'Command wrapper installed\n'
}

install_timer_units() {
  local install_root="$1"
  local interval="$2"
  mkdir -p "$systemd_dir"

  cat >"$systemd_dir/pma-metrics.service" <<SERVICE
[Unit]
Description=Proxmox Monitor Agent metrics collection

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /run/pma && tmp="\$(mktemp /run/pma/metrics.json.XXXXXX)" && "$install_root/agent/metrics.sh" | jq . > "\$tmp" && mv "\$tmp" /run/pma/metrics.json'
SERVICE

  cat >"$systemd_dir/pma-metrics.timer" <<TIMER
[Unit]
Description=Run Proxmox Monitor Agent metrics collection

[Timer]
OnBootSec=$interval
OnUnitActiveSec=$interval
Unit=pma-metrics.service

[Install]
WantedBy=timers.target
TIMER

  if [[ "${PMA_SKIP_SYSTEMD_RELOAD:-0}" != 1 ]]; then
    systemctl daemon-reload
    systemctl enable --now pma-metrics.timer
  fi
}

interval_to_seconds() {
  local interval="$1"
  if [[ "$interval" =~ ^([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$interval" =~ ^([0-9]+)s$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$interval" =~ ^([0-9]+)m$ ]]; then
    printf '%s' "$(( ${BASH_REMATCH[1]} * 60 ))"
  elif [[ "$interval" =~ ^([0-9]+)h$ ]]; then
    printf '%s' "$(( ${BASH_REMATCH[1]} * 3600 ))"
  else
    printf '60'
  fi
}

install_http_units() {
  local install_root="$1"
  local listen_address="$2"
  local port="$3"
  local collection_interval_seconds="$4"
  mkdir -p "$systemd_dir"

  cat >"$systemd_dir/pma-http.socket" <<SOCKET
[Unit]
Description=Proxmox Monitor Agent HTTP socket

[Socket]
ListenStream=$listen_address:$port
Accept=yes

[Install]
WantedBy=sockets.target
SOCKET

  cat >"$systemd_dir/pma-http@.service" <<SERVICE
[Unit]
Description=Proxmox Monitor Agent HTTP request handler

[Service]
Type=simple
Environment=PMA_METRICS_FILE=/run/pma/metrics.json
Environment=PMA_COLLECTION_INTERVAL_SECONDS=$collection_interval_seconds
ExecStart=$install_root/agent/http.sh
StandardInput=socket
StandardOutput=socket
SERVICE

  if [[ "${PMA_SKIP_SYSTEMD_RELOAD:-0}" != 1 ]]; then
    systemctl daemon-reload
    systemctl enable --now pma-http.socket
  fi
}

run_post_install_test() {
  local command_path="$1"
  local tmp_json
  local tmp_err
  local collect_status=0

  tmp_json="$(mktemp)"
  tmp_err="$(mktemp)"
  printf 'Running test collection with %ss timeout...\n' "$test_timeout_seconds"

  if command_exists timeout; then
    timeout "$test_timeout_seconds" "$command_path" >"$tmp_json" 2>"$tmp_err" || collect_status=$?
  else
    "$command_path" >"$tmp_json" 2>"$tmp_err" || collect_status=$?
  fi

  if [[ "$collect_status" -ne 0 ]]; then
    if [[ "$collect_status" -eq 124 ]]; then
      printf 'WARNING: test collection timed out after %ss\n' "$test_timeout_seconds" >&2
    else
      printf 'WARNING: test collection failed with exit code %s\n' "$collect_status" >&2
    fi
    if [[ -s "$tmp_err" ]]; then
      printf 'Collector stderr:\n' >&2
      sed 's/^/  /' "$tmp_err" >&2
    fi
    rm -f "$tmp_json" "$tmp_err"
    return 0
  fi

  if ! jq empty "$tmp_json"; then
    printf 'WARNING: test collection did not produce valid JSON\n' >&2
    rm -f "$tmp_json" "$tmp_err"
    return 0
  fi

  printf 'Test collection produced valid JSON\n'
  printf 'To save a metrics snapshot, run: pma-metrics | jq . > /tmp/pma-metrics.json\n'
  rm -f "$tmp_json" "$tmp_err"
}

main() {
  require_source_tree

  local install_root
  install_root="$(prompt "Install directory [$default_install_root]: " "$default_install_root")"

  local check_dependencies=0
  if prompt_yes_no "Check missing dependencies? [Y/n]: " "Y"; then
    check_dependencies=1
  fi

  if [[ "$check_dependencies" == 1 ]]; then
    local required_missing=()
    local optional_packages=()
    local packages_to_install=()

    mapfile -t required_missing < <(detect_missing_required)
    mapfile -t optional_packages < <(detect_missing_optional_installable)
    mapfile -t required_missing < <(filter_nonempty_array "${required_missing[@]}")
    mapfile -t optional_packages < <(filter_nonempty_array "${optional_packages[@]}")

    if [[ "${#required_missing[@]}" -gt 0 ]]; then
      printf 'Missing required commands: %s\n' "${required_missing[*]}"
    fi
    if [[ "${#optional_packages[@]}" -gt 0 ]]; then
      printf 'Optional installable packages: %s\n' "${optional_packages[*]}"
    fi

    packages_to_install=("${required_missing[@]}" "${optional_packages[@]}")
    if [[ "${#packages_to_install[@]}" -gt 0 ]]; then
      printf 'Packages proposed for apt install: %s\n' "${packages_to_install[*]}"
      if prompt_yes_no "Install missing dependencies with apt? [y/N]: " "N"; then
        install_packages "${packages_to_install[@]}"
      elif [[ "${#required_missing[@]}" -gt 0 ]]; then
        printf 'ERROR: required dependencies are missing\n' >&2
        exit 1
      fi
    fi
  fi

  local create_command=0
  if prompt_yes_no "Create command symlink $default_symlink_path? [Y/n]: " "Y"; then
    create_command=1
  fi

  local interval="60s"
  if prompt_yes_no "Install systemd timer? [y/N]: " "N"; then
    install_timer=1
    interval="$(prompt "Collection interval [60s]: " "60s")"
  fi

  local http_listen_address="$default_http_listen_address"
  local http_port="$default_http_port"
  local collection_interval_seconds="null"
  if prompt_yes_no "Install HTTP snapshot server? [y/N]: " "N"; then
    install_http=1
    http_listen_address="$(prompt "HTTP listen address [$default_http_listen_address]: " "$default_http_listen_address")"
    http_port="$(prompt "HTTP port [$default_http_port]: " "$default_http_port")"

    if [[ "$install_timer" != 1 ]]; then
      if prompt_yes_no "HTTP server requires a metrics snapshot. Install collection timer? [Y/n]: " "Y"; then
        install_timer=1
        interval="$(prompt "Collection interval [60s]: " "60s")"
      fi
    fi

    if [[ "$install_timer" == 1 ]]; then
      collection_interval_seconds="$(interval_to_seconds "$interval")"
    fi
  fi

  local run_test=0
  if prompt_yes_no "Run test collection now? [Y/n]: " "Y"; then
    run_test=1
  fi
  [[ "${PMA_SKIP_POST_INSTALL_TEST:-0}" == 1 ]] && run_test=0

  require_root_for_system_paths "$install_root" "$default_symlink_path"

  if [[ -e "$install_root/agent" ]]; then
    printf 'Existing installation found at %s/agent\n' "$install_root"
    if ! prompt_yes_no "Overwrite existing installation? [y/N]: " "N"; then
      printf 'Install cancelled\n'
      exit 0
    fi
  fi

  copy_agent "$install_root"
  if [[ "$create_command" == 1 ]]; then
    create_command_wrapper "$install_root" "$default_symlink_path"
  fi
  if [[ "$install_timer" == 1 ]]; then
    install_timer_units "$install_root" "$interval"
  fi
  if [[ "$install_http" == 1 ]]; then
    install_http_units "$install_root" "$http_listen_address" "$http_port" "$collection_interval_seconds"
  fi
  if [[ "$run_test" == 1 ]]; then
    run_post_install_test "$install_root/agent/metrics.sh"
  fi

  printf 'PMA installed at %s\n' "$install_root"
}

main "$@"
