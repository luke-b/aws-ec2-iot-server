# Detailní technický implementační plán: Prometheus + IoTDB + AINode + edge AI

## 1) Stav codebase (grounded z repozitáře)

- Základní stack je nasazován skriptem `bootstrap_iot_stack.sh` jako **Grafana + VictoriaMetrics** nebo **Grafana + InfluxDB 1.8**; součástí je provisioning Grafany a test ingest + query.【F:bootstrap_iot_stack.sh†L1-L268】
- Rozšířený stack `bootstrap_iot_stack_extended.sh` umí volitelně **Nginx**, **MQTT (Mosquitto)** a **Node‑RED**, včetně flow pro převod MQTT payloadu na line protocol a zápis do DB.【F:bootstrap_iot_stack_extended.sh†L1-L398】
- README dokumentuje oba základní stacky a zmiňuje rozšířený scénář s Nginx/MQTT/Node‑RED, včetně portů a instalace přes profily v `system_configs/`.【F:README.md†L1-L168】
- `tech_description.html` popisuje datový tok (IoT → TSDB → Grafana) a volitelné rozšíření s MQTT/Node‑RED.【F:tech_description.html†L24-L104】

## 2) Cíl a rozsah

**Cíl:** Integrovat do stávajícího stacku:
1. **Prometheus** (scrape/alerts + kompatibilita s Prometheus ekosystémem),
2. **IoTDB** jako IoT/TSDB vrstvu pro historická data a AI scénáře,
3. **AINode** jako AI/ML výpočetní vrstvu nad IoTDB,
4. **Edge AI** – možnost přesunu části inference na edge HW.

**Principy návrhu:**
- Minimální zásah do existujícího PoC (zachovat kompatibilitu Grafana + VictoriaMetrics/InfluxDB).【F:bootstrap_iot_stack.sh†L1-L268】
- Znovupoužít existující ingest vrstvu (MQTT + Node‑RED), která už je přítomná v extended scriptu.【F:bootstrap_iot_stack_extended.sh†L1-L398】
- Postupné rozšiřování v samostatných profilech/skriptech, aby byla zachována „lightweight“ varianta pro t3.micro.【F:README.md†L70-L120】

## 3) Architektonický cílový návrh (logické bloky)

### 3.1 Monitoring a metriky
- **Prometheus server**: sběr metrik z interních služeb (Node‑RED, Mosquitto, OS/exportéry).
- **VictoriaMetrics** jako **long‑term storage** přes `remote_write` (Prometheus → VictoriaMetrics).
- **Grafana** jako společná vizualizace (datasource na VictoriaMetrics a případně IoTDB).

### 3.2 IoT data / TSDB
- **IoTDB** pro ukládání a dotazování IoT dat (long‑term storage, strukturované měření, přirozené řazení dle device/measurement).
- Ingest přes **MQTT → Node‑RED → IoTDB** (HTTP/Session API) s možností duálního zápisu i do VictoriaMetrics pro monitoring metrik.

### 3.3 AI / AINode
- **AINode** čte historická data z IoTDB, provádí trénink/validaci a zapisuje výsledky zpět do IoTDB (predikce, anomaly score).
- AINode může běžet v samostatném kontejneru nebo externě (VM/K8s), s jasně definovanými endpointy pro přístup k IoTDB.

### 3.4 Edge AI
- Edge HW provádí inference, posílá na MQTT pouze agregace/anomálie.
- Edge dostává update modelu z AINode (OTA pull přes registry, HTTP endpoint).
- Node‑RED může směrovat odlišné topic prefixy (`iot/raw`, `iot/inference`).

## 4) Detailní implementační plán (kroky)

### Fáze 0 – Analýza a baseline
1. **Zmapovat současné profily** v `system_configs/` a ověřit, které služby/porty jsou už popsány v README.【F:README.md†L36-L120】
2. **Rozhodnout o cílové variantě** (viz níže v diskusi) a rozsahu (kontejnerizace AINode vs. externí služba).

### Fáze 1 – Nový bootstrap profil pro IoTDB + AINode
1. **Vytvořit nový skript** (např. `bootstrap_iot_stack_iotdb.sh`) inspirovaný `bootstrap_iot_stack_extended.sh`:
   - Re‑use argument parser a struktura adresářů (compose + provisioning + mqtt/node-red).【F:bootstrap_iot_stack_extended.sh†L1-L120】
   - Přidat nové adresáře pro IoTDB data (volume) a AINode konfiguraci.
2. **Přidat IoTDB service** do compose:
   - Porty (např. 6667/18080 dle IoTDB konfigurace).
   - Volume mount pro data/logs.
3. **Přidat AINode service** (pokud je kontejnerizovatelný):
   - Konfigurace přístupu k IoTDB.
   - Healthcheck endpoint.
4. **Upravit Node‑RED flow** (volitelné):
   - Varianta A: nový flow pro zápis do IoTDB.
   - Varianta B: duální zápis (VM + IoTDB).
   - Využít stávající flow JSON pattern (placeholdery), jako v extended scriptu.【F:bootstrap_iot_stack_extended.sh†L296-L522】

### Fáze 2 – Prometheus integrace
1. **Přidat Prometheus service** do rozšířeného stacku (nový profil nebo volitelný flag):
   - `scrape_configs` pro Node‑RED, Mosquitto, host metrics.
   - `remote_write` do VictoriaMetrics pro dlouhodobé ukládání.
2. **Exportéry**:
   - Node‑RED metrics endpoint (pokud dostupný) nebo sidecar exporter.
   - Mosquitto exporter (pokud relevantní).
3. **Grafana datasources**:
   - Zachovat VictoriaMetrics jako Prometheus datasource (už existuje).【F:bootstrap_iot_stack.sh†L145-L170】

### Fáze 3 – Edge AI integrace (design + PoC)
1. **Topic taxonomy**: definovat MQTT prefixy (`iot/raw`, `iot/inference`, `iot/alerts`).
2. **Model distribution**:
   - AINode publikuje modely do storage (S3/HTTP).
   - Edge pravidelně stahuje modely a provádí canary deploy.
3. **Payload schema**:
   - Jasná struktura JSON (device_id, ts, measurement, fields, tags, model_version).

### Fáze 4 – Dokumentace a onboarding
1. **README aktualizace** o nové profily (IoTDB/AINode/Prometheus).
2. **Tech description** doplnit o IoTDB/AINode vrstvy (diagram nebo text).【F:tech_description.html†L24-L104】
3. **Operátorský guide** rozšířit o nové porty a validace (IoTDB healthcheck, AINode endpoint).

## 5) Konkrétní technické deliverables

- `bootstrap_iot_stack_iotdb.sh` (nový script) – analogie k `bootstrap_iot_stack_extended.sh`.
- `docker-compose` rozšíření: IoTDB + AINode + Prometheus (volitelné služby, controlled flags).
- Node‑RED flow templates pro IoTDB ingest.
- Aktualizace `README.md`, `tech_description.html`, případně nové `docs/` (operational guide).

## 6) Rizika a mitigace

- **Resource constraints na t3.micro**: IoTDB + AINode mohou být náročné; doporučit větší instance pro full stack, zachovat lightweight profil.【F:README.md†L88-L120】
- **Datová konzistence**: při duálním zápisu (VM + IoTDB) vyjasnit „source of truth“.
- **Security**: otevřené porty omezit pouze na potřebné a preferovat Nginx/HTTPS frontu.【F:README.md†L66-L118】

## 7) Závěrečná diskuse (varianty rozhodnutí)

### Varianta A – „Minimal changes“ (doporučeno)
- Zachovat VictoriaMetrics jako Prometheus‑kompatibilní backend.
- Přidat Prometheus server s `remote_write` do VictoriaMetrics.
- IoTDB + AINode provozovat paralelně, Node‑RED zapisuje do obou.
- **Výhoda**: minimální změny do existujících skriptů a Grafany.【F:bootstrap_iot_stack.sh†L1-L268】

### Varianta B – „IoTDB‑centric“
- IoTDB jako hlavní TSDB pro IoT data.
- Prometheus pouze pro infra metriky.
- Grafana napojená primárně na IoTDB.
- **Výhoda**: jedna IoT data vrstva, ale náročnější migrace.

### Varianta C – „Edge‑first“
- Edge inference + minimalizace dat.
- Cloud uchovává agregace a anomálie, raw data selektivně.
- **Výhoda**: úspora bandwidth, menší storage footprint.

**Doporučení:** Začít Variantou A kvůli kompatibilitě se stávajícím PoC a snadnému postupnému rozšiřování, a následně validovat přínos IoTDB + AINode před přechodem na IoTDB‑centric nebo edge‑first design.
