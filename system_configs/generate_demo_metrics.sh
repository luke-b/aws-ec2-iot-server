#!/usr/bin/env bash
# Generate demo metrics for VictoriaMetrics or InfluxDB, with optional MQTT messages.
# Usage examples:
#   ./generate_demo_metrics.sh --stack=vm --vm-url=http://localhost:8428 --count=5
#   ./generate_demo_metrics.sh --stack=influx --influx-url=http://localhost:8086 --influx-db=iot
#   ./generate_demo_metrics.sh --stack=vm --send-mqtt --mqtt-host=localhost --mqtt-user=iot --mqtt-pass=iot

set -euo pipefail

STACK_TYPE="vm"
VM_URL="http://localhost:8428"
INFLUX_URL="http://localhost:8086"
INFLUX_DB="iot"
MEASUREMENT="demo_metric"
COUNT=10
INTERVAL=1
SEND_MQTT=false
MQTT_HOST="localhost"
MQTT_PORT="1883"
MQTT_USER="iot"
MQTT_PASS="iot"
MQTT_TOPIC="iot/demo"
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --stack=*) STACK_TYPE="${arg#*=}" ;;
    --vm-url=*) VM_URL="${arg#*=}" ;;
    --influx-url=*) INFLUX_URL="${arg#*=}" ;;
    --influx-db=*) INFLUX_DB="${arg#*=}" ;;
    --measurement=*) MEASUREMENT="${arg#*=}" ;;
    --count=*) COUNT="${arg#*=}" ;;
    --interval=*) INTERVAL="${arg#*=}" ;;
    --send-mqtt) SEND_MQTT=true ;;
    --mqtt-host=*) MQTT_HOST="${arg#*=}" ;;
    --mqtt-port=*) MQTT_PORT="${arg#*=}" ;;
    --mqtt-user=*) MQTT_USER="${arg#*=}" ;;
    --mqtt-pass=*) MQTT_PASS="${arg#*=}" ;;
    --mqtt-topic=*) MQTT_TOPIC="${arg#*=}" ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
 done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

send_metric_vm() {
  local value="$1"
  local payload
  payload="${MEASUREMENT} value=${value}"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: curl -s -X POST --data-binary '$payload' ${VM_URL}/write"
  else
    curl -s -X POST --data-binary "$payload" "${VM_URL}/write" >/dev/null
  fi
}

send_metric_influx() {
  local value="$1"
  local payload
  payload="${MEASUREMENT} value=${value}"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: curl -s -X POST --data-binary '$payload' ${INFLUX_URL}/write?db=${INFLUX_DB}"
  else
    curl -s -X POST --data-binary "$payload" "${INFLUX_URL}/write?db=${INFLUX_DB}" >/dev/null
  fi
}

send_mqtt_message() {
  local value="$1"
  local payload
  payload=$(printf '{"measurement":"%s","value":%s}' "$MEASUREMENT" "$value")
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: docker run --rm --network host eclipse-mosquitto:2 mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t $MQTT_TOPIC -m '$payload'"
  else
    docker run --rm --network host eclipse-mosquitto:2 mosquitto_pub \
      -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
      -t "$MQTT_TOPIC" -m "$payload" >/dev/null
  fi
}

log "Generating ${COUNT} demo metrics for stack=${STACK_TYPE}"
for i in $(seq 1 "$COUNT"); do
  value=$((RANDOM % 100))
  if [ "$STACK_TYPE" = "vm" ]; then
    send_metric_vm "$value"
  elif [ "$STACK_TYPE" = "influx" ]; then
    send_metric_influx "$value"
  else
    echo "Unsupported stack: $STACK_TYPE" >&2
    exit 1
  fi

  if [ "$SEND_MQTT" = true ]; then
    send_mqtt_message "$value"
  fi

  sleep "$INTERVAL"
 done

log "Demo metric generation complete."
