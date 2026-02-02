# Architektonický report: integrace Prometheus + IoTDB + AINode + edge AI

## 1) Kontext a současný stack (co už repo nabízí)

- Základní skript `bootstrap_iot_stack.sh` nasazuje dvojici služeb: **Grafana** + **VictoriaMetrics** (Prometheus‑style API) nebo **Grafana** + **InfluxDB 1.8** a provede ingest i test dotazu.【F:bootstrap_iot_stack.sh†L1-L268】
- README popisuje dvě varianty stacku, jejich porty a rychlý start, včetně volitelného rozšířeného stacku s **Nginx**, **MQTT (Mosquitto)** a **Node-RED** pro ingest a transformaci payloadů.【F:README.md†L1-L168】
- Rozšířený skript `bootstrap_iot_stack_extended.sh` přidává **Nginx reverse proxy**, **MQTT broker** a **Node‑RED** se základním flow pro převod MQTT payloadu na line protocol a zápis do DB.【F:bootstrap_iot_stack_extended.sh†L1-L398】
- Technický popis stacku shrnuje, že ingest probíhá přes HTTP, grafy v Grafaně, a že je možné zapnout Nginx + MQTT + Node‑RED pro rozšířené scénáře.【F:tech_description.html†L24-L104】

### Shrnutí výchozího návrhu
- **Monitoring/observability stack** je postavený primárně na time‑series DB (VictoriaMetrics nebo InfluxDB) a Grafaně.
- Rozšířená varianta už obsahuje **IoT ingest** (MQTT) a **transformační vrstvu** (Node‑RED) mezi ingestem a DB.
- V repo **zatím není** Prometheus server, IoTDB ani AINode; tyto komponenty je potřeba navrhnout jako nové služby v compose nebo samostatný stack.

## 2) Cílová architektura pro požadované integrace (high‑level)

Níže je návrh „minimálně invazivní“ integrace, která zachová výhody současného stacku, ale doplní požadované komponenty.

### 2.1 Prometheus (kdy a jak ho přidat)

**Varianta A – ponechat VictoriaMetrics jako Prometheus‑kompatibilní backend**
- VictoriaMetrics už poskytuje **Prometheus API**, takže existující Grafana datasource funguje bez změn.【F:bootstrap_iot_stack.sh†L92-L170】
- Pokud potřebujete **Prometheus server** (scrape, alerting rules), přidejte ho jako další službu v compose a nastavte:
  - `scrape_configs` na interní služby (Node‑RED, vlastní exportéry).
  - `remote_write` do VictoriaMetrics (dlouhodobé ukládání / retention).
- **Výhoda**: zachování stávajícího stacku, minimální změny v Grafaně.

**Varianta B – Prometheus jako primární DB**
- Použijte Prometheus server pro krátkou retenci a **remote_write do IoTDB** (viz níže) nebo do VictoriaMetrics, pokud chcete vysokou kompatibilitu s Prometheus ekosystémem.
- **Nevýhoda**: vyšší RAM/CPU nároky na t3.micro a nutnost definovat retence a archivaci.

### 2.2 IoTDB + AINode (nová data vrstva + AI pipeline)

**Cíl**: IoTDB jako hlavní „industrial‑grade“ time‑series/IoT databáze a AINode jako výpočetní/AI vrstva nad daty.

**Základní integrační body**:
1. **Ingest**
   - MQTT broker (Mosquitto) → Node‑RED → IoTDB HTTP/Session API.
   - Alternativně přímé psaní z gateway do IoTDB (pokud gateway zvládá client SDK).
2. **AINode**
   - AINode napojený na IoTDB pro trénink/inferenci nad historickými daty.
   - Výstupy AINode (anomaly scores, predikce) zapisovat zpět do IoTDB (samostatné measurement/series).
3. **Vizualizace**
   - Grafana plugin pro IoTDB (nebo přes integrační vrstvu/exportéry), případně duální napojení Grafany (IoTDB + Prometheus/VictoriaMetrics).

**Dopad na současný stack**:
- Rozšířený skript už umí **MQTT + Node‑RED**, takže ingestion layer lze znovu použít.【F:bootstrap_iot_stack_extended.sh†L256-L522】
- Je potřeba přidat **IoTDB service** do compose (nový volume, porty, konfigurace) a navázat Node‑RED HTTP request na IoTDB endpoint.
- Přidat samostatnou službu **AINode** (pokud běží jako kontejner) nebo definovat externí job (k8s/VM) s přístupem k IoTDB.

## 3) Edge AI (AI na edge HW)

### 3.1 Kde edge AI zapadá do toku dat
- **Edge inference**: zpracování signálu/feature extraction přímo na zařízení/gateway.
- **Cloud training**: trénink modelů v AINode nad historickými daty v IoTDB.
- **Model distribution**: registry modelů (např. S3/HTTP) a OTA aktualizace na edge.

### 3.2 Návrh toku dat s edge AI
1. **Zařízení / edge gateway** provede inference (např. anomaly score) → odešle na MQTT.
2. **Node‑RED** může obohatit payload (device metadata, tags) → zapis do IoTDB.
3. **AINode** použije historická data pro retraining → publikuje nový model/konfiguraci.
4. **Edge** periodicky stahuje nový model → validuje → nasadí.

### 3.3 Doporučené praktické kroky
- Rozšířit MQTT topics (např. `iot/raw/...`, `iot/inference/...`).
- V Node‑RED přidat routing (RAW do IoTDB, inference do IoTDB + alerting stream do Prometheus/VictoriaMetrics).
- Uvažovat **minimalizaci dat**: na edge posílat jen agregace/anomálie a raw data ukládat selektivně.

## 4) Možné varianty výsledného stacku (doporučené volby)

### Varianta 1 – „Minimal changes“ (doporučeno na start)
- Zachovat **Grafana + VictoriaMetrics**.
- Přidat **Prometheus server** (scrape/exportéry) s `remote_write` do VictoriaMetrics.
- Přidat **IoTDB + AINode** jako **paralelní data vrstvu** pro AI use‑cases.
- Node‑RED zapisuje **duplicitně** (VictoriaMetrics pro monitoring, IoTDB pro AI/TSDB).

### Varianta 2 – „IoTDB‑centric“
- IoTDB hlavní TSDB (storage i query).
- Prometheus jen pro infra metrics (cluster health, exporters) → může ukládat do VictoriaMetrics.
- Grafana napojená na IoTDB plugin a (volitelně) na Prometheus/VictoriaMetrics.

### Varianta 3 – „Edge‑first“
- Edge inference + filtr → do cloudu jen agregace/anomálie.
- IoTDB drží agregovaná data, Prometheus/VictoriaMetrics drží provozní metriky.
- AINode spíše pro retraining než online inference.

## 5) Praktický návrh implementace v tomto repu (následující krok)

1. **Doplnit nový compose profil** (např. `bootstrap_iot_stack_iotdb.sh`):
   - IoTDB + AINode služby + volitelné MQTT/Node‑RED (navázat na stávající extended script).【F:bootstrap_iot_stack_extended.sh†L1-L522】
2. **Rozšířit README** o nové profily a porty (IoTDB, AINode).
3. **Přidat grafické schéma** (arch diagram) pro kombinaci Prometheus + IoTDB + AINode.
4. **Definovat edge integration** (README/guide): payloady, topics, model update flow.

## 6) Otevřené otázky pro finální rozhodnutí

- Má IoTDB sloužit jako **primární TSDB** nebo jen jako **AI/ML storage**?
- Preferovaný **mechanismus ingestu** do IoTDB (MQTT + Node‑RED vs. přímý SDK)?
- Kde bude AINode běžet (stejná VM, jiná VM, k8s)?
- Jaké **retence** a **compliance** požadavky budou platit pro raw data?

---

**Doporučení pro rychlý start**: Varianta 1 (minimální změny) umožní paralelně ověřit IoTDB + AINode bez narušení stávajícího monitorovacího stacku a zachová současné PoC workflow.【F:README.md†L1-L168】
