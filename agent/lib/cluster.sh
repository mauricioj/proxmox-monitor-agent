#!/usr/bin/env bash

pma_collect_cluster() {
  pma_debug "cluster: start"
  if ! pma_command_exists pvesh; then
    pma_debug "cluster: pvesh missing"
    jq -n '{enabled:false, name:null, node_count:null, quorate:null, nodes:[]}'
    return
  fi

  local status
  pma_debug "cluster: pvesh /cluster/status"
  status="$(pma_run pvesh get /cluster/status --output-format json 2>/dev/null || true)"
  if [[ -z "$status" || "$status" == "null" ]]; then
    pma_debug "cluster: empty status"
    jq -n '{enabled:false, name:null, node_count:null, quorate:null, nodes:[]}'
    return
  fi

  pma_debug "cluster: render"
  jq -n --argjson status "$status" '
    {
      enabled: (($status | length) > 0),
      name: (($status[]? | select(.type == "cluster") | .name) // null),
      node_count: ([$status[]? | select(.type == "node")] | length),
      quorate: (($status[]? | select(.type == "cluster") | .quorate) // null),
      nodes: [
        $status[]?
        | select(.type == "node")
        | {
            id: .name,
            name: .name,
            online: (.online // null),
            local: (.local // null)
          }
      ]
    }'
}
