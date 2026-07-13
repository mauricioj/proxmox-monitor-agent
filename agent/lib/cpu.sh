#!/usr/bin/env bash

pma_cpu_totals_from_line() {
  awk '
    $1 == "cpu" {
      idle = $5 + $6
      total = 0
      for (i = 2; i <= NF; i++) {
        total += $i
      }
      printf "%.0f %.0f\n", idle, total
      exit
    }
  '
}

pma_cpu_usage_from_samples() {
  local first="$1"
  local second="$2"
  local idle1 total1 idle2 total2 idle_delta total_delta

  read -r idle1 total1 < <(printf '%s\n' "$first" | pma_cpu_totals_from_line)
  read -r idle2 total2 < <(printf '%s\n' "$second" | pma_cpu_totals_from_line)

  if [[ -z "${idle1:-}" || -z "${total1:-}" || -z "${idle2:-}" || -z "${total2:-}" ]]; then
    printf 'null\n'
    return
  fi

  idle_delta=$((idle2 - idle1))
  total_delta=$((total2 - total1))
  if [[ "$total_delta" -le 0 ]]; then
    printf 'null\n'
    return
  fi

  jq -n \
    --argjson idle_delta "$idle_delta" \
    --argjson total_delta "$total_delta" \
    '((((1 - ($idle_delta / $total_delta)) * 100) * 100) | round) / 100'
}

pma_collect_cpu_usage_percent() {
  local sample_interval="${PMA_CPU_SAMPLE_INTERVAL_SECONDS:-0.2}"
  local first second

  first="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  [[ -n "$first" ]] || {
    printf 'null\n'
    return
  }

  sleep "$sample_interval" 2>/dev/null || sleep 1
  second="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  pma_cpu_usage_from_samples "$first" "$second"
}

pma_collect_cpu() {
  local load1 load5 load15 model threads cores sockets frequency governor virtualization usage_percent

  pma_debug "cpu: start"
  read -r load1 load5 load15 _ < /proc/loadavg || true
  pma_debug "cpu: cpuinfo"
  model="$(awk -F: '/model name/ {gsub(/^ /,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  threads="$(nproc 2>/dev/null || true)"
  cores="$(awk -F: '/cpu cores/ {gsub(/^ /,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  sockets="$(awk -F: '/physical id/ {gsub(/^ /,"",$2); ids[$2]=1} END {count=0; for (id in ids) count++; if (count>0) print count}' /proc/cpuinfo 2>/dev/null || true)"
  frequency="$(awk -F: '/cpu MHz/ {gsub(/^ /,"",$2); printf "%.0f\n", $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  governor="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)"

  if grep -Eq 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
    virtualization=true
  else
    virtualization=false
  fi
  usage_percent="$(pma_collect_cpu_usage_percent)"

  pma_debug "cpu: render"
  jq -n \
    --arg load1 "${load1:-}" \
    --arg load5 "${load5:-}" \
    --arg load15 "${load15:-}" \
    --arg model "$model" \
    --arg threads "$threads" \
    --arg cores "$cores" \
    --arg sockets "$sockets" \
    --arg frequency "$frequency" \
    --arg governor "$governor" \
    --argjson usage_percent "$usage_percent" \
    --argjson virtualization "$virtualization" \
    '{
      usage_percent: $usage_percent,
      load_average: {
        "1m": (if $load1 == "" then null else ($load1 | tonumber) end),
        "5m": (if $load5 == "" then null else ($load5 | tonumber) end),
        "15m": (if $load15 == "" then null else ($load15 | tonumber) end)
      },
      frequency_mhz: (if $frequency == "" then null else ($frequency | tonumber) end),
      sockets: (if $sockets == "" then null else ($sockets | tonumber) end),
      cores: (if $cores == "" then null else ($cores | tonumber) end),
      threads: (if $threads == "" then null else ($threads | tonumber) end),
      model: (if $model == "" then null else $model end),
      governor: (if $governor == "" then null else $governor end),
      virtualization_enabled: $virtualization,
      per_core: []
    }'
}
