#!/usr/bin/env bash
# Extended bootstrap script for deploying a lightweight IoT monitoring stack on a free‑tier EC2 instance.
#
# This script builds on bootstrap_iot_stack.sh by optionally adding:
# - Nginx reverse proxy (for a single entry point to Grafana and optional DB APIs)
# - MQTT broker (Eclipse Mosquitto)
# - Node-RED for MQTT processing and forwarding to the metrics store

set -euo pipefail

# Default configuration variables. These may be overridden via environment variables or command line arguments.
STACK_TYPE=${STACK_TYPE:-vm}               # "vm" for VictoriaMetrics, "influx" for InfluxDB 1.8
DATA_DIR=${DATA_DIR:-/opt/iotstack}        # Base directory for persistent data and config
RETENTION=${VM_RETENTION:-30d}             # Data retention for VictoriaMetrics
INFLUX_DB=${INFLUX_DB:-iot}               # Default InfluxDB database name
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASS=${GRAFANA_ADMIN_PASS:-admin}
INFLUX_ADMIN_USER=${INFLUX_ADMIN_USER:-admin}
INFLUX_ADMIN_PASS=${INFLUX_ADMIN_PASS:-admin}

ENABLE_NGINX=false
ENABLE_MQTT=false
ENABLE_NODE_RED=false
EXPOSE_DB_VIA_NGINX=false
EXPOSE_GRAFANA=true
NGINX_DOMAIN=""
NGINX_EMAIL=""
MQTT_USER=${MQTT_USER:-iot}
MQTT_PASS=${MQTT_PASS:-iot}
MQTT_PORT=${MQTT_PORT:-1883}
MQTT_WS_PORT=${MQTT_WS_PORT:-9001}
NODE_RED_PORT=${NODE_RED_PORT:-1880}
NODE_RED_USER=${NODE_RED_USER:-admin}
NODE_RED_PASS=${NODE_RED_PASS:-admin}
DRY_RUN=false

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    --stack=*) STACK_TYPE="${arg#*=}" ;;
    --data-dir=*) DATA_DIR="${arg#*=}" ;;
    --vm-retention=*) RETENTION="${arg#*=}" ;;
    --influx-db=*) INFLUX_DB="${arg#*=}" ;;
    --grafana-user=*) GRAFANA_ADMIN_USER="${arg#*=}" ;;
    --grafana-pass=*) GRAFANA_ADMIN_PASS="${arg#*=}" ;;
    --influx-user=*) INFLUX_ADMIN_USER="${arg#*=}" ;;
    --influx-pass=*) INFLUX_ADMIN_PASS="${arg#*=}" ;;
    --enable-nginx) ENABLE_NGINX=true ;;
    --enable-mqtt) ENABLE_MQTT=true ;;
    --enable-node-red) ENABLE_NODE_RED=true ;;
    --expose-db-via-nginx) EXPOSE_DB_VIA_NGINX=true ;;
    --expose-grafana) EXPOSE_GRAFANA=true ;;
    --no-expose-grafana) EXPOSE_GRAFANA=false ;;
    --nginx-domain=*) NGINX_DOMAIN="${arg#*=}" ;;
    --nginx-email=*) NGINX_EMAIL="${arg#*=}" ;;
    --mqtt-user=*) MQTT_USER="${arg#*=}" ;;
    --mqtt-pass=*) MQTT_PASS="${arg#*=}" ;;
    --mqtt-port=*) MQTT_PORT="${arg#*=}" ;;
    --mqtt-ws-port=*) MQTT_WS_PORT="${arg#*=}" ;;
    --node-red-port=*) NODE_RED_PORT="${arg#*=}" ;;
    --node-red-user=*) NODE_RED_USER="${arg#*=}" ;;
    --node-red-pass=*) NODE_RED_PASS="${arg#*=}" ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "DRY‑RUN: $*"
  else
    eval "$@"
  fi
}

write_file() {
  local path="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY‑RUN: write $path"
    cat
  else
    cat > "$path"
  fi
}

append_file() {
  local path="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY‑RUN: append $path"
    cat
  else
    cat >> "$path"
  fi
}

# Pre‑flight checks: ensure script is run as root and OS is Debian/Ubuntu
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  log "This script expects a Debian/Ubuntu system with apt-get."
fi

log "Starting extended bootstrap for stack type: $STACK_TYPE"

# Install Docker if missing
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

# Enable and start the Docker service
if ! systemctl is-active docker >/dev/null; then
  log "Starting Docker service"
  run_cmd "systemctl enable --now docker"
fi

# Create directories for volumes and configs
log "Creating data directories under $DATA_DIR"
run_cmd "mkdir -p $DATA_DIR/volumes/{grafana,vmdata,influxdb,mqtt/data,mqtt/log,node-red}"
run_cmd "mkdir -p $DATA_DIR/compose"
run_cmd "mkdir -p $DATA_DIR/provisioning/datasources"
run_cmd "mkdir -p $DATA_DIR/provisioning/dashboards"
run_cmd "mkdir -p $DATA_DIR/nginx/conf.d"
run_cmd "mkdir -p $DATA_DIR/mqtt"
run_cmd "chown -R 472:472 $DATA_DIR/volumes/grafana"
run_cmd "chown -R 1000:1000 $DATA_DIR/volumes/node-red"

# Build docker-compose.yml depending on the chosen stack type
COMPOSE_FILE="$DATA_DIR/compose/docker-compose.yml"
log "Generating docker-compose.yml for stack type $STACK_TYPE"

GRAFANA_PORTS=""
if [ "$EXPOSE_GRAFANA" = true ]; then
  GRAFANA_PORTS="    ports:\n      - \"3000:3000\""
fi

if [ "$STACK_TYPE" = "vm" ]; then
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
EOF
else
  # InfluxDB stack
  write_file "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  influxdb:
    image: influxdb:1.8
    restart: unless-stopped
    ports:
      - "8086:8086"
    environment:
      - INFLUXDB_DB=$INFLUX_DB
      - INFLUXDB_HTTP_AUTH_ENABLED=true
      - INFLUXDB_ADMIN_USER=$INFLUX_ADMIN_USER
      - INFLUXDB_ADMIN_PASSWORD=$INFLUX_ADMIN_PASS
    volumes:
      - $DATA_DIR/volumes/influxdb:/var/lib/influxdb
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
EOF
fi

if [ "$ENABLE_NGINX" = true ]; then
  log "Configuring Nginx reverse proxy"
  SERVER_NAME="_"
  if [ -n "$NGINX_DOMAIN" ]; then
    SERVER_NAME="$NGINX_DOMAIN"
  fi

  NGINX_DB_LOCATIONS=""
  if [ "$EXPOSE_DB_VIA_NGINX" = true ] && [ "$STACK_TYPE" = "vm" ]; then
    NGINX_DB_LOCATIONS=$'  location /api/vm/ {\n    proxy_pass http://victoriametrics:8428/;\n    proxy_set_header Host $host;\n  }\n'
  fi
  if [ "$EXPOSE_DB_VIA_NGINX" = true ] && [ "$STACK_TYPE" = "influx" ]; then
    NGINX_DB_LOCATIONS=$'  location /api/influx/ {\n    proxy_pass http://influxdb:8086/;\n    proxy_set_header Host $host;\n  }\n'
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
${NGINX_DB_LOCATIONS}}
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

if [ "$ENABLE_MQTT" = true ]; then
  log "Configuring Mosquitto MQTT broker"
  MQTT_WS_CONFIG=""
  if [ -n "$MQTT_WS_PORT" ]; then
    MQTT_WS_CONFIG=$'listener 9001\nprotocol websockets\n'
  fi
  write_file "$DATA_DIR/mqtt/mosquitto.conf" <<EOF
persistence true
persistence_location /mosquitto/data/
log_dest stdout
allow_anonymous false
password_file /mosquitto/config/passwd

listener 1883
${MQTT_WS_CONFIG}
EOF

  if [ "$DRY_RUN" = true ]; then
    echo "DRY‑RUN: docker run --rm -v $DATA_DIR/mqtt:/mosquitto/config eclipse-mosquitto:2 mosquitto_passwd -b /mosquitto/config/passwd $MQTT_USER $MQTT_PASS"
  else
    docker run --rm -v "$DATA_DIR/mqtt:/mosquitto/config" eclipse-mosquitto:2 mosquitto_passwd -b /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASS"
  fi

  MOSQUITTO_WS_PORTS=""
  if [ -n "$MQTT_WS_PORT" ]; then
    MOSQUITTO_WS_PORTS=$'      - "'"$MQTT_WS_PORT"':9001"\n'
  fi

  append_file "$COMPOSE_FILE" <<EOF
  mosquitto:
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - "$MQTT_PORT:1883"
${MOSQUITTO_WS_PORTS}    volumes:
      - $DATA_DIR/mqtt/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
      - $DATA_DIR/mqtt/passwd:/mosquitto/config/passwd:ro
      - $DATA_DIR/volumes/mqtt/data:/mosquitto/data
      - $DATA_DIR/volumes/mqtt/log:/mosquitto/log
EOF
fi

if [ "$ENABLE_NODE_RED" = true ]; then
  log "Configuring Node-RED for MQTT ingestion"
  if [ "$ENABLE_MQTT" = false ]; then
    log "Warning: Node-RED is enabled without MQTT broker. Flows will expect a broker at mosquitto:1883."
  fi

  NODE_RED_PASS_HASH=""
  if [ -n "$NODE_RED_PASS" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "DRY‑RUN: docker run --rm nodered/node-red:latest node-red-admin hash-pw \"$NODE_RED_PASS\""
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

  NODE_RED_DB_URL=""
  if [ "$STACK_TYPE" = "vm" ]; then
    NODE_RED_DB_URL="http://victoriametrics:8428/write"
  else
    NODE_RED_DB_URL="http://influxdb:8086/write?db=${INFLUX_DB}"
  fi

  write_file "$DATA_DIR/volumes/node-red/flows.json" <<'EOF'
[
  {
    "id": "flow1",
    "type": "tab",
    "label": "MQTT to Metrics",
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
    "wires": [["json-1"]]
  },
  {
    "id": "json-1",
    "type": "json",
    "z": "flow1",
    "name": "Parse JSON",
    "property": "payload",
    "action": "",
    "pretty": false,
    "x": 330,
    "y": 120,
    "wires": [["function-1"]]
  },
  {
    "id": "function-1",
    "type": "function",
    "z": "flow1",
    "name": "To line protocol",
    "func": "let data = msg.payload;\\nif (typeof data === \\"string\\") {\\n  try { data = JSON.parse(data); } catch (e) {}\\n}\\nconst measurement = data.measurement || \\"iot_metric\\";\\nconst fields = data.fields || { value: data.value };\\nconst tags = data.tags || {};\\nconst escapeTag = (value) => String(value).replace(/[,= ]/g, '\\\\$&');\\nconst escapeFieldKey = (value) => String(value).replace(/[,= ]/g, '\\\\$&');\\nconst formatValue = (value) => {\\n  if (typeof value === \\"number\\") return value;\\n  if (typeof value === \\"boolean\\") return value ? \\"true\\" : \\"false\\";\\n  return '\\"' + String(value).replace(/\\\\\\"/g, '\\\\\\\\"') + '\\"';\\n};\\nconst tagStr = Object.keys(tags).map((key) => escapeTag(key) + \\"=\\" + escapeTag(tags[key])).join(\",\");\\nconst fieldStr = Object.keys(fields).map((key) => escapeFieldKey(key) + \\"=\\" + formatValue(fields[key])).join(\",\");\\nmsg.payload = measurement + (tagStr ? \\",\\" + tagStr : \\"\\" ) + \\" \\" + fieldStr;\\nreturn msg;",
    "outputs": 1,
    "noerr": 0,
    "initialize": "",
    "finalize": "",
    "libs": [],
    "x": 540,
    "y": 120,
    "wires": [["http-headers-1"]]
  },
  {
    "id": "http-headers-1",
    "type": "change",
    "z": "flow1",
    "name": "Set headers",
    "rules": [
      {
        "t": "set",
        "p": "headers",
        "pt": "msg",
        "to": "{\\"Content-Type\\":\\"text/plain\\"}",
        "tot": "json"
      }
    ],
    "x": 740,
    "y": 120,
    "wires": [["http-request-1"]]
  },
  {
    "id": "http-request-1",
    "type": "http request",
    "z": "flow1",
    "name": "Write metrics",
    "method": "POST",
    "ret": "obj",
    "paytoqs": "ignore",
    "url": "__NODE_RED_DB_URL__",
    "tls": "",
    "persist": false,
    "proxy": "",
    "authType": "",
    "senderr": false,
    "headers": [],
    "x": 940,
    "y": 120,
    "wires": [["debug-1"]]
  },
  {
    "id": "debug-1",
    "type": "debug",
    "z": "flow1",
    "name": "DB response",
    "active": true,
    "tosidebar": true,
    "console": false,
    "tostatus": false,
    "complete": "payload",
    "targetType": "msg",
    "x": 1130,
    "y": 120,
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

  run_cmd "sed -i \"s|__NODE_RED_DB_URL__|$NODE_RED_DB_URL|g\" $DATA_DIR/volumes/node-red/flows.json"
  run_cmd "sed -i \"s|__MQTT_USER__|$MQTT_USER|g\" $DATA_DIR/volumes/node-red/flows.json"
  run_cmd "sed -i \"s|__MQTT_PASS__|$MQTT_PASS|g\" $DATA_DIR/volumes/node-red/flows.json"

  NODE_RED_DEPENDS="      - grafana"
  if [ "$STACK_TYPE" = "vm" ]; then
    NODE_RED_DEPENDS="${NODE_RED_DEPENDS}\n      - victoriametrics"
  else
    NODE_RED_DEPENDS="${NODE_RED_DEPENDS}\n      - influxdb"
  fi
  if [ "$ENABLE_MQTT" = true ]; then
    NODE_RED_DEPENDS="${NODE_RED_DEPENDS}\n      - mosquitto"
  fi

  append_file "$COMPOSE_FILE" <<EOF
  nodered:
    image: nodered/node-red:latest
    restart: unless-stopped
    ports:
      - "$NODE_RED_PORT:1880"
    volumes:
      - $DATA_DIR/volumes/node-red:/data
    depends_on:
${NODE_RED_DEPENDS}
EOF
fi

# Create Grafana datasource provisioning file
DSPROV="$DATA_DIR/provisioning/datasources/datasource.yml"
log "Generating Grafana datasource configuration"
if [ "$STACK_TYPE" = "vm" ]; then
  write_file "$DSPROV" <<EOF
apiVersion: 1
datasources:
  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://victoriametrics:8428
    isDefault: true
EOF
else
  write_file "$DSPROV" <<EOF
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    database: $INFLUX_DB
    user: $INFLUX_ADMIN_USER
    password: $INFLUX_ADMIN_PASS
    isDefault: true
    jsonData:
      httpMode: POST
      httpHeaderName1: Authorization
EOF
fi

# Create Grafana dashboard provisioning (simple example dashboard)
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

# Write a very basic dashboard that charts the sample metric/measurement
log "Generating Grafana dashboard JSON"
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

# Launch the stack
log "Launching services with Docker Compose"
if [ "$DRY_RUN" = true ]; then
  echo "DRY‑RUN: docker compose -f $COMPOSE_FILE pull"
  echo "DRY‑RUN: docker compose -f $COMPOSE_FILE up -d"
else
  docker compose -f "$COMPOSE_FILE" pull
  docker compose -f "$COMPOSE_FILE" up -d
fi

if [ "$DRY_RUN" = true ]; then
  log "Dry-run mode enabled; skipping readiness checks and test ingestion."
  log "Bootstrap complete. Grafana is available on port 3000 (admin credentials: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})."
  exit 0
fi

# Wait for services to be ready and perform basic ingestion tests
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
else
  log "Grafana port is not exposed; skipping localhost:3000 check"
fi

if [ "$STACK_TYPE" = "vm" ]; then
  log "Waiting for VictoriaMetrics on port 8428..."
  wait_for_port localhost 8428 || { log "VictoriaMetrics did not become ready"; exit 1; }
  log "Sending test metric to VictoriaMetrics"
  run_cmd "curl -s -X POST --data-binary 'test_metric value=1' http://localhost:8428/write"
  sleep 2
  log "Querying metric via VictoriaMetrics API"
  run_cmd "curl -s 'http://localhost:8428/api/v1/query?query=test_metric'"
else
  log "Waiting for InfluxDB on port 8086..."
  wait_for_port localhost 8086 || { log "InfluxDB did not become ready"; exit 1; }
  log "Sending test measurement to InfluxDB"
  run_cmd "curl -s -i -XPOST 'http://localhost:8086/write?db=$INFLUX_DB' --data-binary 'test_metric value=1'"
  sleep 2
  log "Querying measurement via InfluxDB API"
  run_cmd "curl -s -G 'http://localhost:8086/query' --data-urlencode 'db=$INFLUX_DB' --data-urlencode 'q=SELECT * FROM test_metric LIMIT 1'"
fi

if [ "$ENABLE_NGINX" = true ]; then
  log "Waiting for Nginx on port 80..."
  wait_for_port localhost 80 || { log "Nginx did not become ready"; exit 1; }
fi

if [ "$ENABLE_MQTT" = true ]; then
  log "Validating MQTT broker connectivity"
  if [ "$DRY_RUN" = true ]; then
    echo "DRY‑RUN: docker run --rm --network host eclipse-mosquitto:2 sh -c \"mosquitto_sub -h localhost -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t iot/test -C 1 -W 5 & sleep 1; mosquitto_pub -h localhost -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t iot/test -m hello; wait\""
  else
    docker run --rm --network host eclipse-mosquitto:2 sh -c "mosquitto_sub -h localhost -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t iot/test -C 1 -W 5 & sleep 1; mosquitto_pub -h localhost -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t iot/test -m hello; wait"
  fi
fi

if [ "$ENABLE_NODE_RED" = true ]; then
  log "Waiting for Node-RED on port ${NODE_RED_PORT}..."
  wait_for_port localhost "$NODE_RED_PORT" || { log "Node-RED did not become ready"; exit 1; }
fi

log "Bootstrap complete. Grafana is available on port 3000 (admin credentials: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})."
