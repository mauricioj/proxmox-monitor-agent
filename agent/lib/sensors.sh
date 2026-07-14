#!/usr/bin/env bash

pma_collect_sensors() {
  pma_debug "sensors: start"
  if ! pma_command_exists sensors; then
    pma_debug "sensors: sensors missing"
    jq -n '{temperatures:[], fans:[], voltages:[], power:[]}'
    return
  fi

  local sensors_json
  pma_debug "sensors: sensors -j"
  sensors_json="$(pma_run sensors -j 2>/dev/null || true)"
  if [[ -z "$sensors_json" ]]; then
    pma_debug "sensors: empty sensors output"
    jq -n '{temperatures:[], fans:[], voltages:[], power:[]}'
    return
  fi
  sensors_json="$(printf '%s\n' "$sensors_json" | sed '/^[[:space:]]*ERROR:/d')"
  if ! jq empty >/dev/null 2>&1 <<<"$sensors_json"; then
    pma_debug "sensors: invalid sensors json"
    jq -n '{temperatures:[], fans:[], voltages:[], power:[]}'
    return
  fi

  pma_debug "sensors: render"
  jq '
    def normalized_id($chip; $sensor_label; $raw):
      ($chip + "-" + $sensor_label + "-" + $raw)
      | gsub("[^A-Za-z0-9]+"; "-")
      | ascii_downcase
      | sub("^-"; "")
      | sub("-$"; "");

    def reading_type($raw):
      if ($raw | test("^temp[0-9]*_input$|^tdie[0-9]*_input$|^tctl[0-9]*_input$"; "i")) then "temperature"
      elif ($raw | test("^fan[0-9]*_input$"; "i")) then "fan"
      elif ($raw | test("^in[0-9]*_input$|^volt[0-9]*_input$"; "i")) then "voltage"
      elif ($raw | test("^power[0-9]*_input$"; "i")) then "power"
      else null
      end;

    def readings:
      to_entries[]? as $chip
      | $chip.value
      | to_entries[]? as $group
      | select($group.value | type == "object")
      | $group.value
      | to_entries[]?
      | select(.value | type == "number")
      | (reading_type(.key)) as $type
      | select($type != null)
      | {
          "id": normalized_id($chip.key; $group.key; .key),
          "type": $type,
          "label": $group.key,
          "source": $chip.key,
          "raw_label": .key,
          "value": .value
        };

    {
      "temperatures": [readings | select(.type == "temperature") | del(.type)],
      "fans": [readings | select(.type == "fan") | del(.type)],
      "voltages": [readings | select(.type == "voltage") | del(.type)],
      "power": [readings | select(.type == "power") | del(.type)]
    }' <<<"$sensors_json" 2>/dev/null || jq -n '{temperatures:[], fans:[], voltages:[], power:[]}'
}
