#!/usr/bin/env bash

pma_collect_storage() {
  pma_debug "storage: start"
  if ! pma_command_exists pvesh; then
    pma_debug "storage: pvesh missing"
    jq -n '[]'
    return
  fi

  local storage node_name node_storage
  pma_debug "storage: pvesh /storage"
  storage="$(pma_run pvesh get /storage --output-format json 2>/dev/null || true)"
  if [[ -z "$storage" || "$storage" == "null" ]]; then
    pma_debug "storage: empty"
    jq -n '[]'
    return
  fi

  node_name="$(hostname 2>/dev/null || true)"
  node_storage="[]"
  if [[ -n "$node_name" ]]; then
    pma_debug "storage: pvesh /nodes/$node_name/storage"
    node_storage="$(pma_run pvesh get "/nodes/$node_name/storage" --output-format json 2>/dev/null || true)"
    if [[ -z "$node_storage" || "$node_storage" == "null" ]]; then
      node_storage="[]"
    elif ! jq empty >/dev/null 2>&1 <<<"$node_storage"; then
      node_storage="[]"
    fi
  fi

  pma_debug "storage: render"
  jq -n --argjson storage "$storage" --argjson node_storage "$node_storage" '
    def bool_from_number:
      if . == null then null
      elif . == 1 or . == true then true
      elif . == 0 or . == false then false
      else null
      end;

    def content_list($item):
      (($item.content // "") | split(",") | map(select(length > 0)));

    def status_for($name):
      $node_storage[]? | select(.storage == $name) | .;

  [
    $storage[]?
    | . as $config
    | (status_for($config.storage) // {}) as $status
    | ($status.total // $config.total // null) as $total
    | ($status.used // $config.used // null) as $used
    | {
        id: $config.storage,
        name: $config.storage,
        type: ($status.type // $config.type // null),
        enabled: (if $config.disable == 1 then false else (($status.enabled | bool_from_number) // true) end),
        active: ($status.active | bool_from_number),
        shared: (($status.shared // $config.shared) | bool_from_number),
        total_bytes: $total,
        used_bytes: $used,
        available_bytes: ($status.avail // $config.avail // null),
        used_percent: (if ($total // 0) == 0 or $used == null then null else ((($used / $total) * 10000) | round) / 100 end),
        content: content_list($config)
      }
  ]'
}
