# Analýza a rozšíření schématu IoT stacku

## 1) Popis původního schématu (iot_diagram.png)

Původní diagram ukazuje jednoduchý ingest tok pro IoT metriky:

- **ESP32 senzor** posílá data přes **MQTT broker** do **Node‑RED**.
- **Node‑RED** slouží jako transformační vrstva, která data směruje do jedné ze dvou databází:
  - **VictoriaMetrics** (Prometheus‑kompatibilní TSDB), nebo
  - **InfluxDB 1.8** (line protocol + HTTP API).
- **Grafana** se napojuje na vybranou TSDB a zobrazuje dashboardy.

Schéma tedy vizualizuje proud: *Edge zařízení → MQTT → Node‑RED → TSDB → Grafana*.

## 2) Návrh rozšíření dle aktuálního stavu codebase (Varianta A)

Dle implementovaného Variant A stacku je vhodné rozšířit schéma o:

- **Prometheus** jako scrape + rule engine, který sbírá metriky a **remote_write** posílá do VictoriaMetrics.
- **AINode** jako inference službu, kterou spouští Node‑RED (HTTP call) pro výpočet skóre/anomálií.
- **IoTDB adapter** jako mezivrstvu, která mapuje Node‑RED payload na IoTDB REST API.
- **IoTDB** jako samostatnou data‑vrstvu pro ukládání AI výstupů (např. anomaly_score).
- **Dual‑write** model: Node‑RED zapisuje metriky do VictoriaMetrics a zároveň AI output do IoTDB.

Cílový tok v rozšířeném schématu:

1. **Edge zařízení** → **MQTT broker** → **Node‑RED**.
2. **Node‑RED** → **VictoriaMetrics** (metrics).
3. **Node‑RED** → **AINode** → **IoTDB adapter** → **IoTDB** (AI skóre).
4. **Prometheus** scrape z Node‑RED a **remote_write** do VictoriaMetrics.
5. **Grafana** čte metriky z VictoriaMetrics a AI data z IoTDB.

## 3) Nové schéma (aktualizovaný iot_diagram.png)

Nová verze diagramu reflektuje Variant A topologii a explicitně zobrazuje:

- oddělené větve pro metriky (VictoriaMetrics) a AI výstupy (IoTDB),
- Prometheus scrape + remote_write směr,
- přímé napojení Grafany na obě databáze.

Tento diagram je určen jako výchozí architektonická vizualizace pro novou variantu.
