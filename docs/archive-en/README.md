# Lightweight IoT Monitoring Stack

This repository contains a script (**`bootstrap_iot_stack.sh`**) that automates the deployment of a lightweight
time‑series monitoring stack on a free‑tier EC2 instance.  The stack is designed for small IoT workloads and runs either
VictoriaMetrics + Grafana or InfluxDB 1.8 + Grafana.  It takes care of installing Docker, creating
persistent data directories, generating a Docker Compose configuration, provisioning Grafana with a
pre‑configured datasource and dashboard, launching the services and performing a basic ingest/query
test.

## Contents

| File | Description |
| --- | --- |
| `bootstrap_iot_stack.sh` | Bash script that installs Docker, prepares volumes and configuration, starts VictoriaMetrics/InfluxDB and Grafana, and performs a self‑test. |
| `iot_diagram.png` | Architecture diagram used in the technical description (embedded in the HTML). |
| `tech_description.html` | Technical overview of the stack, configuration details and instructions for integrating an ESP32. |

## Prerequisites

* **Ubuntu Server 22.04 LTS** or another Debian‑based distribution with `apt`.  The EC2 **`t3.micro`** instance type (1 vCPU, 1 GB RAM) is eligible for the AWS Free Tier and sufficient for this PoC.
* Outbound internet access to download Docker images.
* Ports **3000**, **8428** (VictoriaMetrics) and **8086** (InfluxDB) must be available on the host.  VictoriaMetrics uses port 8428 for its Prometheus‑compatible API and accepts InfluxDB line protocol for ingestion【944701197905164†L843-L865】【944701197905164†L765-L771】.  InfluxDB 1.8 listens on port 8086 for HTTP write and query requests【934795437163520†L243-L276】.  Grafana maps port 3000 in the container to the host【761199471576249†L1803-L1817】.
* Root privileges (`sudo`) to install Docker and create system directories.

## Usage

1. **Upload the repository files to your EC2 instance** and SSH into it.
2. Make the script executable: `chmod +x bootstrap_iot_stack.sh`.
3. Run the script as root (or with `sudo`):

   ```sh
   sudo ./bootstrap_iot_stack.sh --stack=vm
   ```

   The `--stack` parameter selects the backend:

   * `vm` – uses VictoriaMetrics as the time‑series database.  VictoriaMetrics stores data under `/var/lib/victoria-metrics` and supports a configurable retention period【944701197905164†L843-L865】.  It accepts metrics via Prometheus push or InfluxDB line protocol and provides a Prometheus API on port 8428【944701197905164†L765-L771】.
   * `influx` – uses InfluxDB 1.8.  InfluxDB stores data in `/var/lib/influxdb` and exposes an HTTP API on port 8086 for writes and queries【934795437163520†L243-L276】.  Authentication is enabled by default through environment variables【934795437163520†L283-L331】.

   Additional options include:

   * `--data-dir=/opt/iotstack` – base directory for volumes and provisioning files.
   * `--vm-retention=30d` – data retention period for VictoriaMetrics (e.g., `30d` or `2y`).
   * `--influx-db=iot` – database name when using InfluxDB.
   * `--grafana-user` and `--grafana-pass` – admin credentials for Grafana.  Grafana can be run via Docker and uses environment variables `GF_SECURITY_ADMIN_USER` and `GF_SECURITY_ADMIN_PASSWORD` to set the default admin account【888395822639031†L98-L107】.  The script provisions Grafana to use the database automatically.
   * `--influx-user` and `--influx-pass` – admin credentials for InfluxDB.
   * `--dry-run` – prints commands instead of executing them (useful for review or debugging).

4. **Check the outputs.**  The script will:
   * Install Docker if it is not already installed.
   * Create persistent directories under the chosen data directory.
   * Generate a Docker Compose file (`docker-compose.yml`) and Grafana provisioning files.
   * Start the containers with `docker compose up -d`.
   * Write a sample metric (`test_metric value=1`) to the database via the appropriate HTTP API (VictoriaMetrics accepts the Influx line protocol at `/write`【903875310432696†L1151-L1163】; InfluxDB uses `/write?db=<db>`【36867540830004†L220-L233】).
   * Query the sample back (Prometheus API `/api/v1/query?query=test_metric` for VictoriaMetrics or `/query` for InfluxDB).  The output of the query is printed so you can verify ingestion.
   * Provision Grafana with a default dashboard that displays the sample metric.

5. **Access Grafana.**  Navigate to `http://<server-ip>:3000` in your browser.  Log in with the admin credentials you set.  You should see a dashboard named *“IoT Example Dashboard”* showing the sample metric.  You can create your own dashboards and queries using the configured datasource.

## Extending and Customising

* **Retention periods** can be tuned to your workload.  VictoriaMetrics defaults to 1 month retention【944701197905164†L843-L865】; this can be extended via `--vm-retention` (e.g., `90d` or `1y`).
* **Persistent storage**: volumes are mounted under `$DATA_DIR/volumes`.  Back them up regularly, especially before terminating the EC2 instance.
* **Grafana**: additional dashboards can be saved in the provisioning directory (`$DATA_DIR/provisioning/dashboards`), or created via the UI.  See [Grafana documentation](https://grafana.com/docs/) for details.
* **Security**: expose services only on private networks or via a VPN.  Configure HTTPS for Grafana if making it public.  Use strong passwords.

## Test with an ESP32

To simulate sensor data from an ESP32 (or any microcontroller), you can send HTTP POST requests containing line protocol.  For VictoriaMetrics, the endpoint `/write` accepts InfluxDB line protocol【903875310432696†L1151-L1163】.  For example:

```c
#include <WiFi.h>
#include <HTTPClient.h>

void sendMeasurement(float temperature) {
  HTTPClient client;
  client.begin("http://<server-ip>:8428/write");
  client.addHeader("Content-Type", "text/plain");
  String line = "temperature value=" + String(temperature);
  client.POST(line);
  client.end();
}
```

Replace `<server-ip>` with your EC2 instance’s IP address.  InfluxDB uses a similar approach but the URL becomes `http://<server-ip>:8086/write?db=<database>`【36867540830004†L220-L233】.

After sending data, refresh your Grafana dashboard to see the temperature series plotted.

## Further Information

* **VictoriaMetrics**: A high‑performance, cost‑effective time‑series database supporting Prometheus and Influx protocols.  Data directory and retention settings can be tuned【944701197905164†L843-L865】.
* **InfluxDB 1.8**: The script uses the 1.x series because it is lighter on resources and supports the classic HTTP API【934795437163520†L243-L276】.  The HTTP API allows writing data using line protocol【36867540830004†L220-L233】.
* **Grafana**: Visualisation platform which runs on port 3000 by default【761199471576249†L1803-L1817】.  Admin credentials are set via environment variables【888395822639031†L98-L107】.

For a deeper explanation of the architecture and component interactions, refer to the `tech_description.html` document in this repository.