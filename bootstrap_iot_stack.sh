#!/usr/bin/env bash
# Bootstrap script for deploying a lightweight IoT monitoring stack on a free‑tier EC2 instance.
#
# This script installs Docker, creates the necessary directories, and launches a stack
# consisting of either VictoriaMetrics + Grafana (Prometheus style metrics) or InfluxDB 1.8 + Grafana.
# It also provisions Grafana with a datasource and a simple dashboard, then performs a basic
# ingestion and query test to confirm the stack is working. The script can be run safely multiple
# times due to idempotent checks.

set -euo pipefail

# Default configuration variables. These may be overridden via environment variables or command
# line arguments. See README.md for details.
STACK_TYPE=${STACK_TYPE:-vm}               # "vm" for VictoriaMetrics, "influx" for InfluxDB 1.8
DATA_DIR=${DATA_DIR:-/opt/iotstack}        # Base directory for persistent data and config
RETENTION=${VM_RETENTION:-30d}             # Data retention for VictoriaMetrics
INFLUX_DB=${INFLUX_DB:-iot}               # Default InfluxDB database name
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASS=${GRAFANA_ADMIN_PASS:-admin}
INFLUX_ADMIN_USER=${INFLUX_ADMIN_USER:-admin}
INFLUX_ADMIN_PASS=${INFLUX_ADMIN_PASS:-admin}
DRY_RUN=false

# Parse command‑line arguments
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

# Pre‑flight checks: ensure script is run as root and OS is Debian/Ubuntu
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  log "This script expects a Debian/Ubuntu system with apt-get."
fi

log "Starting bootstrap for stack type: $STACK_TYPE"

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
run_cmd "mkdir -p $DATA_DIR/volumes/{grafana,vmdata,influxdb}"
run_cmd "mkdir -p $DATA_DIR/compose"
run_cmd "mkdir -p $DATA_DIR/provisioning/datasources"
run_cmd "mkdir -p $DATA_DIR/provisioning/dashboards"
run_cmd "chown -R 472:472 $DATA_DIR/volumes/grafana"

# Build docker-compose.yml depending on the chosen stack type
COMPOSE_FILE="$DATA_DIR/compose/docker-compose.yml"
log "Generating docker-compose.yml for stack type $STACK_TYPE"

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
    ports:
      - "3000:3000"
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
    ports:
      - "3000:3000"
    volumes:
      - $DATA_DIR/volumes/grafana:/var/lib/grafana
      - $DATA_DIR/provisioning:/etc/grafana/provisioning
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

# Wait for services to be ready and perform basic ingestion tests
function wait_for_port() {
  local host="$1"; local port="$2"; local retries=30;
  for i in $(seq 1 $retries); do
    if nc -z "$host" "$port"; then return 0; fi
    sleep 2
  done
  return 1
}

log "Waiting for Grafana to become available..."
wait_for_port localhost 3000 || { log "Grafana did not become ready"; exit 1; }

if [ "$STACK_TYPE" = "vm" ]; then
  log "Waiting for VictoriaMetrics on port 8428..."
  wait_for_port localhost 8428 || { log "VictoriaMetrics did not become ready"; exit 1; }
  # Test ingestion: write a sample metric using Influx line protocol which VictoriaMetrics accepts【944701197905164†L765-L771】
  log "Sending test metric to VictoriaMetrics"
  run_cmd "curl -s -X POST --data-binary 'test_metric value=1' http://localhost:8428/write"
  # Query the metric via Prometheus API
  sleep 2
  log "Querying metric via VictoriaMetrics API"
  run_cmd "curl -s 'http://localhost:8428/api/v1/query?query=test_metric'"
else
  log "Waiting for InfluxDB on port 8086..."
  wait_for_port localhost 8086 || { log "InfluxDB did not become ready"; exit 1; }
  # Test ingestion: write via HTTP API【36867540830004†L220-L233】
  log "Sending test measurement to InfluxDB"
  run_cmd "curl -s -i -XPOST 'http://localhost:8086/write?db=$INFLUX_DB' --data-binary 'test_metric value=1'"
  sleep 2
  # Query the measurement
  log "Querying measurement via InfluxDB API"
  run_cmd "curl -s -G 'http://localhost:8086/query' --data-urlencode 'db=$INFLUX_DB' --data-urlencode 'q=SELECT * FROM test_metric LIMIT 1'"
fi

log "Bootstrap complete. Grafana is available on port 3000 (admin credentials: ${GRAFANA_ADMIN_USER}/${GRAFANA_ADMIN_PASS})."
