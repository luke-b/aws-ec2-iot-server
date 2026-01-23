# Extended Stack Script Implementation Plan

This plan outlines how to create a **second** bootstrap script (for example,
`bootstrap_iot_stack_extended.sh`) that builds on the current
`bootstrap_iot_stack.sh` by adding:

* **Nginx reverse proxy** in front of Grafana (and optionally the data API).
* **MQTT broker** (e.g., Eclipse Mosquitto) for device ingest.

It is written to map directly to the existing script’s flow and file layout so
the new script can be maintained alongside the original without breaking the
current lightweight stack.

## 1) Scope and goals

**Goal:** Keep the existing base behavior intact while offering a “v2” script
that adds optional services for HTTPS termination, access control, and MQTT
ingest. The original script should remain unchanged for the minimal PoC
experience.

**Baseline reference:** the current script installs Docker, creates the
directory layout, generates `docker-compose.yml`, provisions Grafana, and runs
simple health/ingest checks.【F:bootstrap_iot_stack.sh†L1-L268】

## 2) Proposed extended script name and parameters

Create a new script:

```
bootstrap_iot_stack_extended.sh
```

Add parameters (all optional, with safe defaults):

* `--enable-nginx` (default: false)
* `--enable-mqtt` (default: false)
* `--nginx-domain=<fqdn>` (default: empty; when set, generate server_name)
* `--nginx-email=<email>` (optional; for certbot integration later)
* `--mqtt-user=<user>` / `--mqtt-pass=<pass>` (default: iot/iot)
* `--mqtt-port=<port>` (default: 1883)
* `--mqtt-ws-port=<port>` (default: 9001)
* `--expose-db-via-nginx` (default: false; optional path routing)

## 3) Directory layout additions

Extend the existing `$DATA_DIR` layout used in the current script:

```
$DATA_DIR/
  compose/
  nginx/
    conf.d/
  mqtt/
    mosquitto.conf
    passwd
```

This mirrors the current structure where compose and Grafana provisioning are
generated under `$DATA_DIR` while keeping new services isolated in their own
subdirectories.【F:bootstrap_iot_stack.sh†L90-L178】

## 4) Compose additions (high-level)

Generate a **second compose file** or **augment** the existing one when
`--enable-*` flags are set:

### 4.1 Nginx service (conditional)

Add a service similar to:

```yaml
nginx:
  image: nginx:stable
  restart: unless-stopped
  ports:
    - "80:80"
    - "443:443" # optional for future TLS
  volumes:
    - $DATA_DIR/nginx/conf.d:/etc/nginx/conf.d:ro
  depends_on:
    - grafana
```

Routing strategy:

* `/` → `grafana:3000`
* Optionally `/api/vm` → `victoriametrics:8428` (only when `--stack=vm`)
* Optionally `/api/influx` → `influxdb:8086` (only when `--stack=influx`)

### 4.2 MQTT service (conditional)

Add a Mosquitto service:

```yaml
mosquitto:
  image: eclipse-mosquitto:2
  restart: unless-stopped
  ports:
    - "$MQTT_PORT:1883"
    - "$MQTT_WS_PORT:9001"
  volumes:
    - $DATA_DIR/mqtt/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
    - $DATA_DIR/mqtt/passwd:/mosquitto/config/passwd:ro
```

Provide a `mosquitto.conf` that enables password auth and a basic listener for
TCP (and optionally WS).

## 5) Config generation steps (mapped to current script)

Follow the existing script’s pattern (write files first, then compose, then run
containers):

1. **Parse flags** (extend the existing argument parser with new flags).
2. **Create directories** (`$DATA_DIR/nginx`, `$DATA_DIR/mqtt`) alongside the
   current `compose`/`provisioning` directories.
3. **Write configs**:
   * `nginx/conf.d/default.conf` (reverse proxy to Grafana, optional DB paths).
   * `mqtt/mosquitto.conf` (auth enabled, listeners defined).
   * `mqtt/passwd` (generated using `mosquitto_passwd` container or `openssl` if
     you want to avoid host dependencies).
4. **Generate compose**:
   * Keep the existing Grafana + DB services as-is.
   * Append Nginx and Mosquitto conditionally.
5. **Launch**:
   * Use `docker compose up -d` same as current script.
6. **Post checks**:
   * If Nginx enabled: check `localhost:80` → expect Grafana HTTP 200/302.
   * If MQTT enabled: run a quick `mosquitto_sub`/`mosquitto_pub` test from a
     one-off container and validate message flow.

## 6) Resource fit on t3.micro (guardrails)

To keep within 1 vCPU / 1 GB RAM:

* **Default off**: Nginx and MQTT remain disabled unless explicitly enabled.
* **Light configs**: low log verbosity, avoid extra plugins, avoid heavy TLS
  stacks unless required.
* **Retention defaults**: keep existing retention defaults unchanged so the
  DB footprint doesn’t grow unexpectedly.【F:bootstrap_iot_stack.sh†L12-L18】

## 7) Documentation updates

When the extended script is added, update:

* `README.md` with a new section “Extended stack script”.
* `tech_description.html` to show optional Nginx/MQTT components in the
  architecture diagram or text.

## 8) Milestone checklist

1. ✅ Add `bootstrap_iot_stack_extended.sh` skeleton (copy of current script).
2. ✅ Add new flags and directory creation.
3. ✅ Add Nginx config generation.
4. ✅ Add Mosquitto config + password generation.
5. ✅ Update compose generation to include conditional services.
6. ✅ Add health checks for Nginx and MQTT.
7. ✅ Update README/docs with usage and ports.

---

If you want, I can follow this plan and implement the extended script, update
docs, and add a minimal Nginx + Mosquitto configuration with safe defaults.
