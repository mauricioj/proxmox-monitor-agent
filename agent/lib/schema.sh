#!/usr/bin/env bash

pma_collect_schema() {
  jq -n '{name:"pma.metrics", version:1}'
}
