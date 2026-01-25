#!/usr/bin/env bash
# Lightweight VictoriaMetrics + Grafana stack (metrics store + UI only).
# Uses bootstrap_iot_stack.sh with explicit parameters for easy auditing.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

STACK_TYPE="vm"
DATA_DIR="/opt/iotstack-lightweight-vm"
RETENTION="7d"
INFLUX_DB="iot"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin"
INFLUX_ADMIN_USER="admin"
INFLUX_ADMIN_PASS="admin"
DRY_RUN=${DRY_RUN:-false}

args=(
  --stack="$STACK_TYPE"
  --data-dir="$DATA_DIR"
  --vm-retention="$RETENTION"
  --influx-db="$INFLUX_DB"
  --grafana-user="$GRAFANA_ADMIN_USER"
  --grafana-pass="$GRAFANA_ADMIN_PASS"
  --influx-user="$INFLUX_ADMIN_USER"
  --influx-pass="$INFLUX_ADMIN_PASS"
)

if [ "$DRY_RUN" = true ]; then
  args+=(--dry-run)
fi

sudo bash "$ROOT_DIR/bootstrap_iot_stack.sh" "${args[@]}"
