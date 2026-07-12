#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_command_wrapper() {
  local command_path="$1"
  local expected_target="$2"
  assert_file "$command_path"
  [[ -x "$command_path" ]] || fail "expected executable command wrapper: $command_path"
  grep -F "exec \"$expected_target\" \"\$@\"" "$command_path" >/dev/null ||
    fail "expected wrapper $command_path to exec $expected_target"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_default_install() {
  local install_root="$1"
  local symlink_path="$2"
  local systemd_dir="$3"
  local apt_log="$4"
  shift 4

  mkdir -p "$(dirname "$symlink_path")" "$systemd_dir"

  printf '\n\n\n\n' | env \
    PMA_INSTALL_ROOT="$install_root" \
    PMA_SYMLINK_PATH="$symlink_path" \
    PMA_SYSTEMD_DIR="$systemd_dir" \
    PMA_SKIP_SYSTEMD_RELOAD=1 \
    PMA_SKIP_POST_INSTALL_TEST=1 \
    PMA_NO_TTY=1 \
    PMA_APT_LOG="$apt_log" \
    "$@" \
    bash install.sh >/tmp/pma-install-test.log

  assert_dir "$install_root/agent"
  assert_file "$install_root/agent/metrics.sh"
  [[ -x "$install_root/agent/metrics.sh" ]] || fail "installed metrics.sh must be executable"
  assert_command_wrapper "$symlink_path" "$install_root/agent/metrics.sh"

  [[ ! -f "$systemd_dir/pma-metrics.service" ]] || fail "timer service must not be created by default"
  [[ ! -f "$systemd_dir/pma-metrics.timer" ]] || fail "timer unit must not be created by default"
  [[ ! -f "$systemd_dir/pma-http.socket" ]] || fail "http socket must not be created by default"
  [[ ! -f "$systemd_dir/pma-http@.service" ]] || fail "http service must not be created by default"
  [[ ! -f "$apt_log" ]] || fail "apt must not run without explicit consent"
}

run_no_missing_dependencies_install() {
  local install_root="$1"
  local symlink_path="$2"
  local systemd_dir="$3"
  local apt_log="$4"
  local output_log="$5"

  mkdir -p "$(dirname "$symlink_path")" "$systemd_dir"

  printf '\n\n\n\n' | env \
    PMA_INSTALL_ROOT="$install_root" \
    PMA_SYMLINK_PATH="$symlink_path" \
    PMA_SYSTEMD_DIR="$systemd_dir" \
    PMA_SKIP_SYSTEMD_RELOAD=1 \
    PMA_SKIP_POST_INSTALL_TEST=1 \
    PMA_NO_TTY=1 \
    PMA_ASSUME_COMMANDS_PRESENT=1 \
    PMA_APT_LOG="$apt_log" \
    bash install.sh >"$output_log"

  assert_dir "$install_root/agent"
  assert_file "$install_root/agent/metrics.sh"
  assert_command_wrapper "$symlink_path" "$install_root/agent/metrics.sh"

  grep -F 'Packages proposed for apt install:' "$output_log" >/dev/null &&
    fail "apt prompt must not be shown when no dependencies are missing"
  [[ ! -f "$apt_log" ]] || fail "apt must not run when no dependencies are missing"
}

run_empty_dependency_lines_install() {
  local install_root="$1"
  local symlink_path="$2"
  local systemd_dir="$3"
  local apt_log="$4"
  local output_log="$5"

  mkdir -p "$(dirname "$symlink_path")" "$systemd_dir"

  printf '\n\n\n\n' | env \
    PMA_INSTALL_ROOT="$install_root" \
    PMA_SYMLINK_PATH="$symlink_path" \
    PMA_SYSTEMD_DIR="$systemd_dir" \
    PMA_SKIP_SYSTEMD_RELOAD=1 \
    PMA_SKIP_POST_INSTALL_TEST=1 \
    PMA_NO_TTY=1 \
    PMA_SIMULATE_EMPTY_DEP_LINES=1 \
    PMA_APT_LOG="$apt_log" \
    bash install.sh >"$output_log"

  assert_dir "$install_root/agent"
  assert_file "$install_root/agent/metrics.sh"
  assert_command_wrapper "$symlink_path" "$install_root/agent/metrics.sh"

  grep -F 'Missing required commands:' "$output_log" >/dev/null &&
    fail "empty required dependency lines must not be reported"
  grep -F 'Optional installable packages:' "$output_log" >/dev/null &&
    fail "empty optional dependency lines must not be reported"
  grep -F 'Packages proposed for apt install:' "$output_log" >/dev/null &&
    fail "empty dependency lines must not trigger apt prompt"
  [[ ! -f "$apt_log" ]] || fail "apt must not run for empty dependency lines"
}

run_stdin_bootstrap_install() {
  local install_root="$1"
  local symlink_path="$2"
  local systemd_dir="$3"
  local apt_log="$4"
  local archive_url="$5"

  mkdir -p "$(dirname "$symlink_path")" "$systemd_dir"

  env \
    PMA_INSTALL_ROOT="$install_root" \
    PMA_SYMLINK_PATH="$symlink_path" \
    PMA_SYSTEMD_DIR="$systemd_dir" \
    PMA_SKIP_SYSTEMD_RELOAD=1 \
    PMA_SKIP_POST_INSTALL_TEST=1 \
    PMA_NO_TTY=1 \
    PMA_ARCHIVE_URL="$archive_url" \
    PMA_APT_LOG="$apt_log" \
    bash <install.sh >/tmp/pma-install-stdin-test.log

  assert_dir "$install_root/agent"
  assert_file "$install_root/agent/metrics.sh"
  [[ -x "$install_root/agent/metrics.sh" ]] || fail "stdin bootstrap metrics.sh must be executable"
  assert_command_wrapper "$symlink_path" "$install_root/agent/metrics.sh"

  [[ ! -f "$systemd_dir/pma-metrics.service" ]] || fail "stdin bootstrap timer service must not be created by default"
  [[ ! -f "$systemd_dir/pma-metrics.timer" ]] || fail "stdin bootstrap timer unit must not be created by default"
  [[ ! -f "$systemd_dir/pma-http.socket" ]] || fail "stdin bootstrap http socket must not be created by default"
  [[ ! -f "$systemd_dir/pma-http@.service" ]] || fail "stdin bootstrap http service must not be created by default"
  [[ ! -f "$apt_log" ]] || fail "stdin bootstrap apt must not run without explicit consent"
}

run_http_install() {
  local install_root="$1"
  local symlink_path="$2"
  local systemd_dir="$3"
  local apt_log="$4"

  mkdir -p "$(dirname "$symlink_path")" "$systemd_dir"

  printf '\nn\n\n\ny\n127.0.0.1\n9876\n\n45s\nn\n' | env \
    PMA_INSTALL_ROOT="$install_root" \
    PMA_SYMLINK_PATH="$symlink_path" \
    PMA_SYSTEMD_DIR="$systemd_dir" \
    PMA_SKIP_SYSTEMD_RELOAD=1 \
    PMA_NO_TTY=1 \
    PMA_APT_LOG="$apt_log" \
    bash install.sh >/tmp/pma-install-http-test.log

  assert_dir "$install_root/agent"
  assert_file "$install_root/agent/http.sh"
  [[ -x "$install_root/agent/http.sh" ]] || fail "installed http.sh must be executable"
  assert_file "$systemd_dir/pma-http.socket"
  assert_file "$systemd_dir/pma-http@.service"
  assert_file "$systemd_dir/pma-metrics.service"
  assert_file "$systemd_dir/pma-metrics.timer"

  grep -F 'ListenStream=127.0.0.1:9876' "$systemd_dir/pma-http.socket" >/dev/null ||
    fail "http socket must use configured listen address and port"
  grep -F 'Environment=PMA_COLLECTION_INTERVAL_SECONDS=45' "$systemd_dir/pma-http@.service" >/dev/null ||
    fail "http service must expose configured collection interval"
  grep -F 'ExecStart='"$install_root"'/agent/http.sh' "$systemd_dir/pma-http@.service" >/dev/null ||
    fail "http service must execute installed handler"
  grep -F 'mktemp /run/pma/metrics.json.XXXXXX' "$systemd_dir/pma-metrics.service" >/dev/null ||
    fail "timer service must write to a temp file"
  grep -F 'mv "$tmp" /run/pma/metrics.json' "$systemd_dir/pma-metrics.service" >/dev/null ||
    fail "timer service must publish metrics atomically"
}

install_root="$tmp_dir/local/opt/proxmox-monitor-agent"
symlink_path="$tmp_dir/local/usr/local/bin/pma-metrics"
systemd_dir="$tmp_dir/local/etc/systemd/system"
apt_log="$tmp_dir/local/apt.log"

run_default_install "$install_root" "$symlink_path" "$systemd_dir" "$apt_log" env

run_no_missing_dependencies_install \
  "$tmp_dir/no-missing/opt/proxmox-monitor-agent" \
  "$tmp_dir/no-missing/usr/local/bin/pma-metrics" \
  "$tmp_dir/no-missing/etc/systemd/system" \
  "$tmp_dir/no-missing/apt.log" \
  "$tmp_dir/no-missing/output.log"

run_empty_dependency_lines_install \
  "$tmp_dir/empty-lines/opt/proxmox-monitor-agent" \
  "$tmp_dir/empty-lines/usr/local/bin/pma-metrics" \
  "$tmp_dir/empty-lines/etc/systemd/system" \
  "$tmp_dir/empty-lines/apt.log" \
  "$tmp_dir/empty-lines/output.log"

run_http_install \
  "$tmp_dir/http/opt/proxmox-monitor-agent" \
  "$tmp_dir/http/usr/local/bin/pma-metrics" \
  "$tmp_dir/http/etc/systemd/system" \
  "$tmp_dir/http/apt.log"

archive_root="$tmp_dir/archive/proxmox-monitor-agent-main"
mkdir -p "$archive_root"
cp -R agent "$archive_root/agent"
archive_path="$tmp_dir/proxmox-monitor-agent-main.tar.gz"
tar -C "$tmp_dir/archive" -czf "$archive_path" proxmox-monitor-agent-main

bootstrap_dir="$tmp_dir/bootstrap"
mkdir -p "$bootstrap_dir"
cp install.sh "$bootstrap_dir/install.sh"

(
  cd "$bootstrap_dir"
  run_default_install \
    "$tmp_dir/bootstrap-install/opt/proxmox-monitor-agent" \
    "$tmp_dir/bootstrap-install/usr/local/bin/pma-metrics" \
    "$tmp_dir/bootstrap-install/etc/systemd/system" \
    "$tmp_dir/bootstrap-install/apt.log" \
    env PMA_ARCHIVE_URL="file://$archive_path"

  run_stdin_bootstrap_install \
    "$tmp_dir/stdin-bootstrap-install/opt/proxmox-monitor-agent" \
    "$tmp_dir/stdin-bootstrap-install/usr/local/bin/pma-metrics" \
    "$tmp_dir/stdin-bootstrap-install/etc/systemd/system" \
    "$tmp_dir/stdin-bootstrap-install/apt.log" \
    "file://$archive_path"
)

printf 'PASS: install defaults are manual-only\n'
