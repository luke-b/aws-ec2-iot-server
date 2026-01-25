#!/usr/bin/env bash
# Full stack: VictoriaMetrics + Grafana (via Nginx) + MQTT + Node-RED, with DB API exposed through Nginx.
# Uses bootstrap_iot_stack_extended.sh with explicit parameters for easy auditing.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

STACK_TYPE="vm"
DATA_DIR="/opt/iotstack-full"
RETENTION="30d"
INFLUX_DB="iot"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin"
INFLUX_ADMIN_USER="admin"
INFLUX_ADMIN_PASS="admin"
NGINX_DOMAIN="iot.example.com"
NGINX_EMAIL="ops@example.com"
MQTT_USER="iot"
MQTT_PASS="iot"
MQTT_PORT="1883"
MQTT_WS_PORT="9001"
NODE_RED_PORT="1880"
NODE_RED_USER="admin"
NODE_RED_PASS="admin"
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
  --enable-nginx
  --enable-mqtt
  --enable-node-red
  --expose-db-via-nginx
  --no-expose-grafana
  --nginx-domain="$NGINX_DOMAIN"
  --nginx-email="$NGINX_EMAIL"
  --mqtt-user="$MQTT_USER"
  --mqtt-pass="$MQTT_PASS"
  --mqtt-port="$MQTT_PORT"
  --mqtt-ws-port="$MQTT_WS_PORT"
  --node-red-port="$NODE_RED_PORT"
  --node-red-user="$NODE_RED_USER"
  --node-red-pass="$NODE_RED_PASS"
)

if [ "$DRY_RUN" = true ]; then
  args+=(--dry-run)
fi

sudo bash "$ROOT_DIR/bootstrap_iot_stack_extended.sh" "${args[@]}"
