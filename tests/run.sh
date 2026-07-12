#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash tests/schema_contract_test.sh tests/fixtures/schema-v1-example.json

if [[ -x agent/metrics.sh ]]; then
  tmp_json="$(mktemp)"
  PMA_HOST_ID_FILE="${PMA_HOST_ID_FILE:-.pma-test/host_id}" bash agent/metrics.sh > "$tmp_json"
  bash tests/schema_contract_test.sh "$tmp_json"
  rm -f "$tmp_json"
fi

bash tests/install_test.sh
bash tests/http_server_test.sh
bash tests/module_filters_test.sh
bash tests/cpu_usage_test.sh
