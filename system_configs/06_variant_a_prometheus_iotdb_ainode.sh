#!/usr/bin/env bash
# Variant A: VictoriaMetrics + Grafana + Prometheus + MQTT + Node-RED with parallel IoTDB + AINode.
# Uses bootstrap_iot_stack_extended.sh with explicit parameters for easy auditing.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

STACK_TYPE="vm"
DATA_DIR="/opt/iotstack-variant-a"
RETENTION="30d"
INFLUX_DB="iot"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin"
INFLUX_ADMIN_USER="admin"
INFLUX_ADMIN_PASS="admin"
MQTT_USER="iot"
MQTT_PASS="iot"
MQTT_PORT="1883"
MQTT_WS_PORT="9001"
NODE_RED_PORT="1880"
NODE_RED_USER="admin"
NODE_RED_PASS="admin"
PROMETHEUS_PORT="9090"
PROMETHEUS_RETENTION="7d"
IOTDB_PORT="6667"
IOTDB_HTTP_PORT="18080"
# Set this to the IoTDB ingest endpoint exposed by your IoTDB configuration.
IOTDB_HTTP_ENDPOINT="http://localhost:18080/<iotdb-ingest-endpoint>"
AINODE_PORT="8081"
# Set this to a valid AINode container image that can connect to IoTDB.
AINODE_IMAGE="<ainode-image>"
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
  --enable-mqtt
  --enable-node-red
  --enable-prometheus
  --enable-iotdb
  --enable-ainode
  --mqtt-user="$MQTT_USER"
  --mqtt-pass="$MQTT_PASS"
  --mqtt-port="$MQTT_PORT"
  --mqtt-ws-port="$MQTT_WS_PORT"
  --node-red-port="$NODE_RED_PORT"
  --node-red-user="$NODE_RED_USER"
  --node-red-pass="$NODE_RED_PASS"
  --prometheus-port="$PROMETHEUS_PORT"
  --prometheus-retention="$PROMETHEUS_RETENTION"
  --iotdb-port="$IOTDB_PORT"
  --iotdb-http-port="$IOTDB_HTTP_PORT"
  --iotdb-http-endpoint="$IOTDB_HTTP_ENDPOINT"
  --ainode-port="$AINODE_PORT"
  --ainode-image="$AINODE_IMAGE"
)

if [ "$DRY_RUN" = true ]; then
  args+=(--dry-run)
fi

sudo bash "$ROOT_DIR/bootstrap_iot_stack_extended.sh" "${args[@]}"
