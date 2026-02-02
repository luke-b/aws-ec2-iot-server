#!/usr/bin/env bash
# Variant A bootstrap script: Prometheus + VictoriaMetrics + IoTDB + AINode + MQTT + Node-RED.
# This script focuses on "minimal changes" by keeping VictoriaMetrics as the Prometheus-compatible
# long-term store while adding Prometheus, IoTDB, and a simple AINode service for AI outputs.

set -euo pipefail

STACK_TYPE=vm
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR" && pwd)
DATA_DIR=${DATA_DIR:-/opt/iotstack}
RETENTION=${VM_RETENTION:-30d}
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASS=${GRAFANA_ADMIN_PASS:-admin}
MQTT_USER=${MQTT_USER:-iot}
MQTT_PASS=${MQTT_PASS:-iot}
MQTT_PORT=${MQTT_PORT:-1883}
MQTT_WS_PORT=${MQTT_WS_PORT:-9001}
NODE_RED_PORT=${NODE_RED_PORT:-1880}
NODE_RED_USER=${NODE_RED_USER:-admin}
NODE_RED_PASS=${NODE_RED_PASS:-admin}
IOTDB_USER=${IOTDB_USER:-root}
IOTDB_PASS=${IOTDB_PASS:-root}
IOTDB_REST_PORT=${IOTDB_REST_PORT:-18080}
IOTDB_SESSION_PORT=${IOTDB_SESSION_PORT:-6667}
AINODE_PORT=${AINODE_PORT:-8090}
IOTDB_ADAPTER_PORT=${IOTDB_ADAPTER_PORT:-8089}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-9090}
EXPOSE_GRAFANA=true
ENABLE_NGINX=false
NGINX_DOMAIN=""
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --data-dir=*) DATA_DIR="${arg#*=}" ;;
    --vm-retention=*) RETENTION="${arg#*=}" ;;
    --grafana-user=*) GRAFANA_ADMIN_USER="${arg#*=}" ;;
    --grafana-pass=*) GRAFANA_ADMIN_PASS="${arg#*=}" ;;
    --mqtt-user=*) MQTT_USER="${arg#*=}" ;;
    --mqtt-pass=*) MQTT_PASS="${arg#*=}" ;;
    --mqtt-port=*) MQTT_PORT="${arg#*=}" ;;
    --mqtt-ws-port=*) MQTT_WS_PORT="${arg#*=}" ;;
    --node-red-port=*) NODE_RED_PORT="${arg#*=}" ;;
    --node-red-user=*) NODE_RED_USER="${arg#*=}" ;;
    --node-red-pass=*) NODE_RED_PASS="${arg#*=}" ;;
    --iotdb-user=*) IOTDB_USER="${arg#*=}" ;;
    --iotdb-pass=*) IOTDB_PASS="${arg#*=}" ;;
    --iotdb-rest-port=*) IOTDB_REST_PORT="${arg#*=}" ;;
    --iotdb-session-port=*) IOTDB_SESSION_PORT="${arg#*=}" ;;
    --ainode-port=*) AINODE_PORT="${arg#*=}" ;;
    --iotdb-adapter-port=*) IOTDB_ADAPTER_PORT="${arg#*=}" ;;
    --prometheus-port=*) PROMETHEUS_PORT="${arg#*=}" ;;
    --enable-nginx) ENABLE_NGINX=true ;;
    --nginx-domain=*) NGINX_DOMAIN="${arg#*=}" ;;
    --no-expose-grafana) EXPOSE_GRAFANA=false ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

write_file() {
  local path="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: write $path"
    cat
  else
    cat > "$path"
  fi
}

append_file() {
  local path="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: append $path"
    cat
  else
    cat >> "$path"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  log "This script expects a Debian/Ubuntu system with apt-get."
fi

log "Starting Variant A bootstrap (Prometheus + VM + IoTDB + AINode)."

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y ca-certificates curl gnupg"
  run_cmd "install -m 0755 -d /etc/apt/keyrings"
  run_cmd "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run_cmd "chmod a+r /etc/apt/keyrings/docker.gpg"
  run_cmd "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list"
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
else
  log "Docker already installed"
fi

if ! systemctl is-active docker >/dev/null; then
  log "Starting Docker service"
  run_cmd "systemctl enable --now docker"
fi

log "Creating data directories under $DATA_DIR"
run_cmd "mkdir -p $DATA_DIR/volumes/{grafana,vmdata,iotdb,mqtt/data,mqtt/log,node-red}"
run_cmd "mkdir -p $DATA_DIR/compose"
run_cmd "mkdir -p $DATA_DIR/provisioning/datasources"
run_cmd "mkdir -p $DATA_DIR/provisioning/dashboards"
run_cmd "mkdir -p $DATA_DIR/prometheus"
run_cmd "mkdir -p $DATA_DIR/nginx/conf.d"
run_cmd "mkdir -p $DATA_DIR/mqtt"
run_cmd "chown -R 472:472 $DATA_DIR/volumes/grafana"
run_cmd "chown -R 1000:1000 $DATA_DIR/volumes/node-red"

COMPOSE_FILE="$DATA_DIR/compose/docker-compose.yml"
log "Generating docker-compose.yml"

GRAFANA_PORTS=""
if [ "$EXPOSE_GRAFANA" = true ]; then
  GRAFANA_PORTS="    ports:\n      - \"3000:3000\""
fi

write_file "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  victoriametrics:
    image: victoriametrics/victoria-metrics:latest
    restart: unless-stopped
    command:
      - --storageDataPath=/var/lib/victoria-metrics
      - --retentionPeriod=$RETENTION
    ports:
      - "8428:8428"
    volumes:
      - $DATA_DIR/volumes/vmdata:/var/lib/victoria-metrics
  grafana:
    image: grafana/grafana-oss:latest
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=$GRAFANA_ADMIN_USER
      - GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASS
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
$GRAFANA_PORTS
    volumes:
      - $DATA_DIR/volumes/grafana:/var/lib/grafana
      - $DATA_DIR/provisioning:/etc/grafana/provisioning
  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    ports:
      - "$PROMETHEUS_PORT:9090"
    volumes:
      - $DATA_DIR/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    depends_on:
      - victoriametrics
  node-exporter:
    image: prom/node-exporter:latest
    restart: unless-stopped
    ports:
      - "9100:9100"
  mosquitto:
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - "$MQTT_PORT:1883"
      - "$MQTT_WS_PORT:9001"
    volumes:
      - $DATA_DIR/mqtt/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
      - $DATA_DIR/mqtt/passwd:/mosquitto/config/passwd:ro
      - $DATA_DIR/volumes/mqtt/data:/mosquitto/data
      - $DATA_DIR/volumes/mqtt/log:/mosquitto/log
  iotdb:
    image: apache/iotdb:1.3.2-standalone
    restart: unless-stopped
    ports:
      - "$IOTDB_SESSION_PORT:6667"
      - "$IOTDB_REST_PORT:18080"
    volumes:
      - $DATA_DIR/volumes/iotdb:/iotdb/data
  iotdb-adapter:
    build:
      context: ${REPO_ROOT}/services/iotdb-adapter
    restart: unless-stopped
    environment:
      - IOTDB_REST_URL=http://iotdb:18080
      - IOTDB_USER=$IOTDB_USER
      - IOTDB_PASS=$IOTDB_PASS
      - IOTDB_ADAPTER_PORT=8089
    ports:
      - "$IOTDB_ADAPTER_PORT:8089"
    depends_on:
      - iotdb
  ainode:
    build:
      context: ${REPO_ROOT}/services/ainode
    restart: unless-stopped
    environment:
      - IOTDB_ADAPTER_URL=http://iotdb-adapter:8089/ingest
      - AINODE_PORT=8090
    ports:
      - "$AINODE_PORT:8090"
    depends_on:
      - iotdb-adapter
  nodered:
    image: nodered/node-red:latest
    restart: unless-stopped
    ports:
      - "$NODE_RED_PORT:1880"
    volumes:
      - $DATA_DIR/volumes/node-red:/data
    depends_on:
      - mosquitto
      - victoriametrics
      - iotdb-adapter
      - ainode
EOF

if [ "$ENABLE_NGINX" = true ]; then
  log "Configuring Nginx reverse proxy"
  SERVER_NAME="_"
  if [ -n "$NGINX_DOMAIN" ]; then
    SERVER_NAME="$NGINX_DOMAIN"
  fi

  write_file "$DATA_DIR/nginx/conf.d/default.conf" <<EOF
server {
  listen 80;
  server_name ${SERVER_NAME};

  location / {
    proxy_pass http://grafana:3000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

  append_file "$COMPOSE_FILE" <<EOF
  nginx:
    image: nginx:stable
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - $DATA_DIR/nginx/conf.d:/etc/nginx/conf.d:ro
    depends_on:
      - grafana
EOF
fi

log "Generating Prometheus configuration"
write_file "$DATA_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

remote_write:
  - url: http://victoriametrics:8428/api/v1/write

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]
EOF

log "Configuring Mosquitto MQTT broker"
write_file "$DATA_DIR/mqtt/mosquitto.conf" <<EOF
persistence true
persistence_location /mosquitto/data/
log_dest stdout
allow_anonymous false
password_file /mosquitto/config/passwd

listener 1883
listener 9001
protocol websockets
EOF

if [ "$DRY_RUN" = true ]; then
  echo "DRY-RUN: docker run --rm -v $DATA_DIR/mqtt:/mosquitto/config eclipse-mosquitto:2 mosquitto_passwd -b /mosquitto/config/passwd $MQTT_USER $MQTT_PASS"
else
  docker run --rm -v "$DATA_DIR/mqtt:/mosquitto/config" eclipse-mosquitto:2 mosquitto_passwd -b /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASS"
fi

log "Generating Grafana datasource configuration"
DSPROV="$DATA_DIR/provisioning/datasources/datasource.yml"
write_file "$DSPROV" <<EOF
apiVersion: 1
datasources:
  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://victoriametrics:8428
    isDefault: true
EOF

log "Generating Grafana dashboard provisioning"
DASHPROV="$DATA_DIR/provisioning/dashboards/dashboard.yml"
DASH_JSON="$DATA_DIR/provisioning/dashboards/iot_dashboard.json"
write_file "$DASHPROV" <<EOF
apiVersion: 1
providers:
  - name: "default"
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

write_file "$DASH_JSON" <<'EOF'
{
  "id": null,
  "title": "IoT Example Dashboard",
  "schemaVersion": 30,
  "version": 1,
  "panels": [
    {
      "type": "graph",
      "title": "Sample Metric",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
      "targets": [
        {
          "expr": "test_metric",
          "refId": "A"
        }
      ],
      "datasource": null
    }
  ]
}
EOF

log "Generating Node-RED settings and flows"
NODE_RED_PASS_HASH=""
if [ -n "$NODE_RED_PASS" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: docker run --rm nodered/node-red:latest node-red-admin hash-pw \"$NODE_RED_PASS\""
    NODE_RED_PASS_HASH="__HASH__"
  else
    NODE_RED_PASS_HASH=$(docker run --rm nodered/node-red:latest node-red-admin hash-pw "$NODE_RED_PASS")
  fi
fi

write_file "$DATA_DIR/volumes/node-red/settings.js" <<EOF
module.exports = {
  adminAuth: {
    type: "credentials",
    users: [
      {
        username: "${NODE_RED_USER}",
        password: "${NODE_RED_PASS_HASH}",
        permissions: "*"
      }
    ]
  },
  flowFile: "flows.json"
};
EOF

write_file "$DATA_DIR/volumes/node-red/flows.json" <<'EOF'
[
  {
    "id": "flow1",
    "type": "tab",
    "label": "MQTT to VM + IoTDB",
    "disabled": false,
    "info": ""
  },
  {
    "id": "mqtt-in-1",
    "type": "mqtt in",
    "z": "flow1",
    "name": "MQTT ingest",
    "topic": "iot/#",
    "qos": "0",
    "datatype": "auto",
    "broker": "mqtt-broker-1",
    "nl": false,
    "rap": true,
    "rh": 0,
    "x": 140,
    "y": 120,
    "wires": [["normalize-1"]]
  },
  {
    "id": "normalize-1",
    "type": "function",
    "z": "flow1",
    "name": "Normalize payload",
    "func": "const original = msg.payload;\nlet data = msg.payload;\nif (typeof data === \"string\") {\n  try { data = JSON.parse(data); } catch (e) {}\n}\nconst now = Date.now();\nmsg.payload = {\n  device_id: data.device_id || data.deviceId || \"device-1\",\n  measurement: data.measurement || \"iot_metric\",\n  fields: data.fields || { value: data.value ?? 1 },\n  tags: data.tags || {},\n  timestamp: data.timestamp || now\n};\nmsg.original = original;\nreturn msg;",
    "outputs": 1,
    "noerr": 0,
    "initialize": "",
    "finalize": "",
    "libs": [],
    "x": 360,
    "y": 120,
    "wires": [["vm-line-1", "ainode-req-1"]]
  },
  {
    "id": "vm-line-1",
    "type": "function",
    "z": "flow1",
    "name": "To line protocol",
    "func": "const data = msg.payload;\nconst measurement = data.measurement;\nconst fields = data.fields || { value: 1 };\nconst tags = data.tags || {};\nconst escapeTag = (value) => String(value).replace(/[,= ]/g, '\\$&');\nconst escapeFieldKey = (value) => String(value).replace(/[,= ]/g, '\\$&');\nconst formatValue = (value) => {\n  if (typeof value === \"number\") return value;\n  if (typeof value === \"boolean\") return value ? \"true\" : \"false\";\n  return '\"' + String(value).replace(/\\\\\"/g, '\\\\\\\"') + '\"';\n};\nconst tagStr = Object.keys(tags).map((key) => escapeTag(key) + \"=\" + escapeTag(tags[key])).join(\",\");\nconst fieldStr = Object.keys(fields).map((key) => escapeFieldKey(key) + \"=\" + formatValue(fields[key])).join(\",\");\nmsg.payload = measurement + (tagStr ? \",\" + tagStr : \"\" ) + \" \" + fieldStr;\nmsg.headers = { \"Content-Type\": \"text/plain\" };\nreturn msg;",
    "outputs": 1,
    "noerr": 0,
    "initialize": "",
    "finalize": "",
    "libs": [],
    "x": 610,
    "y": 80,
    "wires": [["vm-http-1"]]
  },
  {
    "id": "vm-http-1",
    "type": "http request",
    "z": "flow1",
    "name": "Write to VM",
    "method": "POST",
    "ret": "obj",
    "paytoqs": "ignore",
    "url": "http://victoriametrics:8428/write",
    "tls": "",
    "persist": false,
    "proxy": "",
    "authType": "",
    "senderr": false,
    "headers": [],
    "x": 820,
    "y": 80,
    "wires": [["vm-debug-1"]]
  },
  {
    "id": "vm-debug-1",
    "type": "debug",
    "z": "flow1",
    "name": "VM response",
    "active": false,
    "tosidebar": true,
    "console": false,
    "tostatus": false,
    "complete": "payload",
    "targetType": "msg",
    "x": 1010,
    "y": 80,
    "wires": []
  },
  {
    "id": "ainode-req-1",
    "type": "http request",
    "z": "flow1",
    "name": "AINode infer",
    "method": "POST",
    "ret": "obj",
    "paytoqs": "ignore",
    "url": "http://ainode:8090/infer",
    "tls": "",
    "persist": false,
    "proxy": "",
    "authType": "",
    "senderr": false,
    "headers": [],
    "x": 600,
    "y": 160,
    "wires": [["iotdb-format-1"]]
  },
  {
    "id": "iotdb-format-1",
    "type": "function",
    "z": "flow1",
    "name": "Format IoTDB record",
    "func": "const original = msg.original || {};\nconst device = original.device_id || 'device-1';\nconst timestamp = original.timestamp || Date.now();\nconst score = msg.payload && msg.payload.score !== undefined ? msg.payload.score : 0;\nmsg.payload = {\n  device_id: `root.${device}`,\n  timestamp: timestamp,\n  measurements: [\"anomaly_score\"],\n  values: [score],\n  data_types: [\"DOUBLE\"]\n};\nreturn msg;",
    "outputs": 1,
    "noerr": 0,
    "initialize": "",
    "finalize": "",
    "libs": [],
    "x": 820,
    "y": 160,
    "wires": [["iotdb-http-1"]]
  },
  {
    "id": "iotdb-http-1",
    "type": "http request",
    "z": "flow1",
    "name": "Write to IoTDB",
    "method": "POST",
    "ret": "obj",
    "paytoqs": "ignore",
    "url": "http://iotdb-adapter:8089/ingest",
    "tls": "",
    "persist": false,
    "proxy": "",
    "authType": "",
    "senderr": false,
    "headers": [],
    "x": 1010,
    "y": 160,
    "wires": [["iotdb-debug-1"]]
  },
  {
    "id": "iotdb-debug-1",
    "type": "debug",
    "z": "flow1",
    "name": "IoTDB response",
    "active": false,
    "tosidebar": true,
    "console": false,
    "tostatus": false,
    "complete": "payload",
    "targetType": "msg",
    "x": 1210,
    "y": 160,
    "wires": []
  },
  {
    "id": "mqtt-broker-1",
    "type": "mqtt-broker",
    "name": "Mosquitto",
    "broker": "mosquitto",
    "port": "1883",
    "clientid": "",
    "autoConnect": true,
    "usetls": false,
    "protocolVersion": "4",
    "keepalive": "60",
    "cleansession": true,
    "birthTopic": "",
    "birthQos": "0",
    "birthPayload": "",
    "closeTopic": "",
    "closePayload": "",
    "willTopic": "",
    "willQos": "0",
    "willPayload": "",
    "user": "__MQTT_USER__",
    "password": "__MQTT_PASS__"
  }
]
EOF

run_cmd "sed -i \"s|__MQTT_USER__|$MQTT_USER|g\" $DATA_DIR/volumes/node-red/flows.json"
run_cmd "sed -i \"s|__MQTT_PASS__|$MQTT_PASS|g\" $DATA_DIR/volumes/node-red/flows.json"

log "Launching services with Docker Compose"
if [ "$DRY_RUN" = true ]; then
  echo "DRY-RUN: docker compose -f $COMPOSE_FILE pull"
  echo "DRY-RUN: docker compose -f $COMPOSE_FILE up -d"
else
  docker compose -f "$COMPOSE_FILE" pull
  docker compose -f "$COMPOSE_FILE" up -d
fi

if [ "$DRY_RUN" = true ]; then
  log "Dry-run mode enabled; skipping readiness checks."
  log "Bootstrap complete."
  exit 0
fi

wait_for_port() {
  local host="$1"; local port="$2"; local retries=30;
  for _ in $(seq 1 $retries); do
    if nc -z "$host" "$port"; then return 0; fi
    sleep 2
  done
  return 1
}

if [ "$EXPOSE_GRAFANA" = true ]; then
  log "Waiting for Grafana to become available..."
  wait_for_port localhost 3000 || { log "Grafana did not become ready"; exit 1; }
fi

log "Waiting for VictoriaMetrics on port 8428..."
wait_for_port localhost 8428 || { log "VictoriaMetrics did not become ready"; exit 1; }

log "Waiting for Prometheus on port ${PROMETHEUS_PORT}..."
wait_for_port localhost "$PROMETHEUS_PORT" || { log "Prometheus did not become ready"; exit 1; }

log "Waiting for IoTDB REST on port ${IOTDB_REST_PORT}..."
wait_for_port localhost "$IOTDB_REST_PORT" || { log "IoTDB REST did not become ready"; exit 1; }

log "Waiting for AINode on port ${AINODE_PORT}..."
wait_for_port localhost "$AINODE_PORT" || { log "AINode did not become ready"; exit 1; }

log "Waiting for Node-RED on port ${NODE_RED_PORT}..."
wait_for_port localhost "$NODE_RED_PORT" || { log "Node-RED did not become ready"; exit 1; }

log "Bootstrap complete. Grafana is available on port 3000 (admin credentials: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})."
