#!/usr/bin/env bash

pma_mem_kib() {
  local key="$1"
  awk -v key="$key" '$1 == key ":" {printf "%.0f\n", $2 * 1024}' /proc/meminfo 2>/dev/null
}

pma_collect_memory() {
  local total available buffers cached sreclaimable shmem swap_total swap_free used cache swap_used used_percent swap_used_percent

  pma_debug "memory: start"
  total="$(pma_mem_kib MemTotal)"
  available="$(pma_mem_kib MemAvailable)"
  buffers="$(pma_mem_kib Buffers)"
  cached="$(pma_mem_kib Cached)"
  sreclaimable="$(pma_mem_kib SReclaimable)"
  shmem="$(pma_mem_kib Shmem)"
  swap_total="$(pma_mem_kib SwapTotal)"
  swap_free="$(pma_mem_kib SwapFree)"

  used=""
  cache=""
  swap_used=""
  if [[ -n "$total" && -n "$available" ]]; then used=$((total - available)); fi
  if [[ -n "$cached" && -n "$sreclaimable" && -n "$shmem" ]]; then cache=$((cached + sreclaimable - shmem)); fi
  if [[ -n "$swap_total" && -n "$swap_free" ]]; then swap_used=$((swap_total - swap_free)); fi

  used_percent="$(pma_percent "${used:-}" "${total:-}")"
  swap_used_percent="$(pma_percent "${swap_used:-}" "${swap_total:-}")"

  pma_debug "memory: render"
  jq -n \
    --arg total "$total" \
    --arg used "$used" \
    --arg available "$available" \
    --arg cache "$cache" \
    --arg buffers "$buffers" \
    --argjson used_percent "$used_percent" \
    --arg swap_total "$swap_total" \
    --arg swap_used "$swap_used" \
    --argjson swap_used_percent "$swap_used_percent" \
    '{
      total_bytes: (if $total == "" then null else ($total | tonumber) end),
      used_bytes: (if $used == "" then null else ($used | tonumber) end),
      available_bytes: (if $available == "" then null else ($available | tonumber) end),
      cache_bytes: (if $cache == "" then null else ($cache | tonumber) end),
      buffers_bytes: (if $buffers == "" then null else ($buffers | tonumber) end),
      used_percent: $used_percent,
      swap_total_bytes: (if $swap_total == "" then null else ($swap_total | tonumber) end),
      swap_used_bytes: (if $swap_used == "" then null else ($swap_used | tonumber) end),
      swap_used_percent: $swap_used_percent
    }'
}
