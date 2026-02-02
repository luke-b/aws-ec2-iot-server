# System Configurations

This directory contains example system configurations that call the core bootstrap scripts with explicit parameters, plus a demo metrics generator. The goal is to provide ready-to-run, audit-friendly entrypoints for typical deployment profiles.

## Prerequisites

- Debian/Ubuntu host with `bash`, `curl`, and `sudo`.
- Run scripts as a user with sudo access (the bootstrap scripts require root).

## Configuration Profiles

> Tip: You can set `DRY_RUN=true` in your shell before running a config script to preview the commands without making changes.

1. **01_lightweight_vm_grafana.sh**
   - Minimal VictoriaMetrics + Grafana stack for metrics storage and dashboards.
2. **02_lightweight_influx_grafana.sh**
   - Minimal InfluxDB 1.8 + Grafana stack for metrics storage and dashboards.
3. **03_vm_grafana_nginx.sh**
   - VictoriaMetrics + Grafana behind an Nginx reverse proxy.
4. **04_vm_grafana_mqtt_nodered.sh**
   - VictoriaMetrics + Grafana + Mosquitto MQTT broker + Node-RED for ingestion.
5. **05_full_stack.sh**
   - Full stack: VictoriaMetrics + Grafana via Nginx, MQTT broker, Node-RED, and DB API exposure through Nginx.
6. **06_variant_a_prometheus_iotdb_ainode.sh**
   - Variant A: Prometheus + VictoriaMetrics + IoTDB + AINode + MQTT + Node-RED dual-write flow.

## Demo Metrics Generator

**generate_demo_metrics.sh** can send demo data to VictoriaMetrics or InfluxDB and optionally publish MQTT messages for Node-RED flows.

Examples:

```bash
./generate_demo_metrics.sh --stack=vm --vm-url=http://localhost:8428 --count=5
./generate_demo_metrics.sh --stack=influx --influx-url=http://localhost:8086 --influx-db=iot
./generate_demo_metrics.sh --stack=vm --send-mqtt --mqtt-host=localhost --mqtt-user=iot --mqtt-pass=iot
```

## Usage

Make the scripts executable once:

```bash
chmod +x system_configs/*.sh
```

Run a configuration:

```bash
./system_configs/01_lightweight_vm_grafana.sh
```

Run the demo metrics generator:

```bash
./system_configs/generate_demo_metrics.sh --stack=vm
```
