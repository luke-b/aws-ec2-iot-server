# Operator Installation Guide (EC2)

This document is a **step-by-step, operator-grade** guide for installing and validating the IoT monitoring stack on an EC2 instance using the provided `bootstrap_iot_stack.sh` script. It is **self-contained** and grounded in the current repository implementation.

---

## 1) What this script installs (at a glance)

The bootstrap script:

1. Installs Docker Engine and Docker Compose plugin (if missing).
2. Creates persistent data directories.
3. Generates a Docker Compose file for either:
   - **VictoriaMetrics + Grafana** (`--stack=vm`), or
   - **InfluxDB 1.8 + Grafana** (`--stack=influx`).
4. Provisions Grafana with a datasource and a minimal example dashboard.
5. Starts containers and performs a basic ingest/query test against the database API.

These behaviors are implemented in `bootstrap_iot_stack.sh`.【F:bootstrap_iot_stack.sh†L1-L268】

---

## 2) Preconditions (operator checks)

### 2.1 EC2 instance requirements

- **OS**: Ubuntu 22.04 LTS (or another Debian-based distro with `apt-get`). The script warns if `apt-get` is missing.【F:bootstrap_iot_stack.sh†L60-L63】
- **Instance size**: `t3.micro` is sufficient for the PoC (matches repo README).【F:README.md†L16-L18】
- **Privileges**: you must run the script as `root` or with `sudo` (enforced by the script).【F:bootstrap_iot_stack.sh†L54-L58】
- **Outbound Internet**: required to fetch Docker packages and images.

### 2.2 Network and Security Group ports

Open inbound ports in the EC2 security group **only as needed**:

- **Grafana**: TCP 3000 (always used).【F:README.md†L20-L21】
- **VictoriaMetrics**: TCP 8428 (only if using `--stack=vm`).【F:README.md†L20-L21】
- **InfluxDB**: TCP 8086 (only if using `--stack=influx`).【F:README.md†L20-L21】

> Recommendation: restrict ingress to your admin IP or VPN endpoint whenever possible.

> **Note:** Do not skip the security group setup in **Section 2.2**—Grafana (TCP 3000) is always required, while VictoriaMetrics (TCP 8428) or InfluxDB (TCP 8086) are only needed for their respective stack choices.

---

## 3) Installation workflow (operator-grade step-by-step)

### Step 1 — Connect to your EC2 instance

```sh
ssh -i /path/to/key.pem ubuntu@<ec2-public-ip>
```

### Step 2 — Upload or clone the repository

If you have a Git URL:

```sh
git clone <repo-url>
cd aws-ec2-iot-server
```

Or upload files via SCP and `cd` into the repository directory.

### Step 3 — Review the script (recommended)

This is a production operator best-practice step. You can use `less` to review what will execute:

```sh
less bootstrap_iot_stack.sh
```

### Step 4 — (Optional) Dry run to preview actions

The script supports a `--dry-run` mode that prints commands instead of executing them.【F:bootstrap_iot_stack.sh†L33-L45】【F:bootstrap_iot_stack.sh†L49-L52】

```sh
sudo ./bootstrap_iot_stack.sh --stack=vm --dry-run
```

### Step 5 — Run the installation

Pick **one** stack type:

- **VictoriaMetrics (recommended for light Prometheus-style workloads):**

  ```sh
  sudo ./bootstrap_iot_stack.sh --stack=vm
  ```

- **InfluxDB 1.8 (if you need the Influx 1.x API):**

  ```sh
  sudo ./bootstrap_iot_stack.sh --stack=influx
  ```

The script will:

- Install Docker if it is not present.【F:bootstrap_iot_stack.sh†L67-L80】
- Start the Docker service if not running.【F:bootstrap_iot_stack.sh†L83-L87】
- Create persistent directories under `/opt/iotstack` by default.【F:bootstrap_iot_stack.sh†L90-L94】
- Generate a `docker-compose.yml` and Grafana provisioning files.【F:bootstrap_iot_stack.sh†L96-L178】
- Start containers and run a basic ingest + query test.【F:bootstrap_iot_stack.sh†L213-L267】

> Note: The default admin credentials for Grafana and InfluxDB are `admin/admin` unless you override them via flags.【F:bootstrap_iot_stack.sh†L18-L24】【F:bootstrap_iot_stack.sh†L35-L41】

---

## 4) Post-install validation (operator checks)

### 4.1 Verify containers are running

```sh
docker ps
```

You should see `grafana` plus either `victoriametrics` or `influxdb` running (names are from the Compose file).【F:bootstrap_iot_stack.sh†L101-L177】

### 4.2 Verify Grafana is reachable

```sh
curl -I http://localhost:3000
```

A `200` or `302` response indicates Grafana is alive. The script also waits for port 3000 to be open before proceeding.【F:bootstrap_iot_stack.sh†L224-L226】

### 4.3 Validate VictoriaMetrics stack (if `--stack=vm`)

The script itself sends a test metric and queries it via the Prometheus API.【F:bootstrap_iot_stack.sh†L228-L238】

You can re-run the checks manually:

```sh
# Write a test metric
curl -s -X POST --data-binary 'test_metric value=1' http://localhost:8428/write

# Query it back
curl -s 'http://localhost:8428/api/v1/query?query=test_metric'
```

Expected: the query response should contain a time series with `test_metric`.

### 4.4 Validate InfluxDB stack (if `--stack=influx`)

The script sends a test measurement and queries it.【F:bootstrap_iot_stack.sh†L240-L266】

You can re-run the checks manually:

```sh
# Write a test measurement
curl -s -i -XPOST 'http://localhost:8086/write?db=iot' --data-binary 'test_metric value=1'

# Query it back
curl -s -G 'http://localhost:8086/query' \
  --data-urlencode 'db=iot' \
  --data-urlencode 'q=SELECT * FROM test_metric LIMIT 1'
```

Expected: the query response should include `test_metric` fields.

---

## 5) Configuration options (operator overrides)

You can override defaults via CLI flags:

| Option | Description | Default | Source |
| --- | --- | --- | --- |
| `--stack=vm|influx` | Choose backend | `vm` | Script config【F:bootstrap_iot_stack.sh†L12-L14】【F:bootstrap_iot_stack.sh†L33-L41】 |
| `--data-dir=/opt/iotstack` | Base directory for volumes/configs | `/opt/iotstack` | Script config【F:bootstrap_iot_stack.sh†L13-L14】 |
| `--vm-retention=30d` | VictoriaMetrics retention | `30d` | Script config【F:bootstrap_iot_stack.sh†L14-L15】 |
| `--influx-db=iot` | InfluxDB database | `iot` | Script config【F:bootstrap_iot_stack.sh†L15-L16】 |
| `--grafana-user` / `--grafana-pass` | Grafana admin credentials | `admin/admin` | Script config【F:bootstrap_iot_stack.sh†L16-L18】 |
| `--influx-user` / `--influx-pass` | InfluxDB admin credentials | `admin/admin` | Script config【F:bootstrap_iot_stack.sh†L19-L20】 |
| `--dry-run` | Print commands without executing | `false` | Script config【F:bootstrap_iot_stack.sh†L21-L22】【F:bootstrap_iot_stack.sh†L49-L52】 |

Example with overrides:

```sh
sudo ./bootstrap_iot_stack.sh \
  --stack=vm \
  --data-dir=/opt/iotstack \
  --vm-retention=90d \
  --grafana-user=operator \
  --grafana-pass='STRONG-PASSWORD'
```

---

## 6) Operational notes and safeguards

- **Idempotency**: The script includes checks for Docker installation and service state, so it can be re-run safely.【F:bootstrap_iot_stack.sh†L67-L87】
- **Persistent storage**: All data lives under `$DATA_DIR/volumes` to survive container restarts.【F:bootstrap_iot_stack.sh†L90-L94】
- **Grafana provisioning**: The script provisions the datasource and a sample dashboard at startup.【F:bootstrap_iot_stack.sh†L138-L212】
- **Security**: Update default passwords and restrict ingress. Default credentials are `admin/admin` unless overridden.【F:bootstrap_iot_stack.sh†L16-L20】

---

## 7) Troubleshooting quick reference

### Docker not installed or failing

- Script logs “Installing Docker…” and installs required packages via `apt-get`.【F:bootstrap_iot_stack.sh†L67-L80】
- Ensure the instance has outbound internet and DNS resolution.

### Grafana not reachable

- The script explicitly checks port 3000 and fails if it doesn’t open.【F:bootstrap_iot_stack.sh†L224-L226】
- Confirm security group ingress allows TCP 3000 from your IP.

### Grafana datasource cannot connect (VictoriaMetrics)

- The provisioned datasource URL is `http://victoriametrics:8428`, which is correct **inside the Docker network** because Grafana and VictoriaMetrics share the same Compose network and can resolve the `victoriametrics` service name.【F:bootstrap_iot_stack.sh†L106-L128】【F:bootstrap_iot_stack.sh†L166-L176】
- If Grafana is running outside Docker, update the datasource URL to the host-reachable address (for example, `http://localhost:8428` on the EC2 host or `http://<ec2-private-ip>:8428`), and ensure the security group allows TCP 8428 if accessing it remotely.

### Database not ready

- VictoriaMetrics waits for port 8428, InfluxDB for port 8086. The script exits if they never open.【F:bootstrap_iot_stack.sh†L228-L242】
- Ensure those ports are not blocked by a local firewall.

---

## 8) Clean removal (optional)

If you need to remove the stack cleanly:

```sh
# Stop and remove containers
sudo docker compose -f /opt/iotstack/compose/docker-compose.yml down

# (Optional) remove data
sudo rm -rf /opt/iotstack
```

Adjust the path if you used `--data-dir`.

---

## 9) Operator validation checklist

Use this checklist to confirm a clean install:

- [ ] Script ran without errors (no non-zero exit).
- [ ] `docker ps` shows Grafana and the chosen DB container.
- [ ] `curl -I http://localhost:3000` returns a successful response.
- [ ] Data ingest test returns expected query output (VM or Influx).
- [ ] Grafana dashboard “IoT Example Dashboard” is visible in the UI.

---

## 10) Summary

This guide provides a repeatable installation path with validation steps that map directly to the repository’s bootstrap script. If you follow each step in order, you will have a functioning IoT monitoring stack with verified ingestion and query capability.
