# Provozní instalační příručka (EC2)

Tento dokument je **praktický, krok‑za‑krokem** návod pro operátory. Vysvětluje, jak nasadit a ověřit IoT monitorovací stack pomocí skriptu `bootstrap_iot_stack.sh`.

---

## 1) Co skript nasadí (rychlý přehled)

Skript:

1. Nainstaluje Docker Engine a Docker Compose plugin (pokud chybí).
2. Vytvoří perzistentní datové adresáře.
3. Vygeneruje Docker Compose konfiguraci pro jednu z variant:
   - **VictoriaMetrics + Grafana** (`--stack=vm`), nebo
   - **InfluxDB 1.8 + Grafana** (`--stack=influx`).
4. Připraví Grafanu s datasource a ukázkovým dashboardem.
5. Spustí kontejnery a ověří ingest + query test.

Varianta A (`bootstrap_iot_stack_variant_a.sh`) rozšiřuje stack o **Prometheus**, **IoTDB** a **AINode**, zachovává VictoriaMetrics jako dlouhodobé úložiště a přidává MQTT + Node‑RED pro dual‑write ingest.

---

## 2) Předpoklady (operátorské kontroly)

### 2.1 EC2 požadavky

- **OS**: Ubuntu 22.04 LTS (nebo jiný Debian‑based systém s `apt-get`).
- **Instance**: `t3.micro` stačí pro PoC.
- **Práva**: skript vyžaduje `root`/`sudo`.
- **Outbound internet**: nutný pro Docker balíčky a image.

### 2.2 Network a Security Group porty

Otevírejte **jen nezbytné porty**:

- **Grafana**: TCP **3000** (vždy)
- **VictoriaMetrics**: TCP **8428** (jen pro `--stack=vm`)
- **InfluxDB**: TCP **8086** (jen pro `--stack=influx`)

> **Poznámka:** Nastavení security group nepřeskakujte. Bez otevřených portů se ke službám nepřipojíte.

---

## 3) Instalace – doporučený postup

### Krok 1 — Přihlášení na EC2

```sh
ssh -i /path/to/key.pem ubuntu@<ec2-public-ip>
```

### Krok 2 — Přenesení repozitáře

```sh
git clone <repo-url>
cd aws-ec2-iot-server
```

### Krok 3 — (Volitelně) Zkontrolujte skript

```sh
less bootstrap_iot_stack.sh
```

### Krok 4 — (Volitelně) Suchý běh

```sh
sudo ./bootstrap_iot_stack.sh --stack=vm --dry-run
```

### Krok 5 — Spuštění instalace

Vyberte **jednu** variantu:

- **VictoriaMetrics (doporučeno):**

  ```sh
  sudo ./bootstrap_iot_stack.sh --stack=vm
  ```

- **InfluxDB 1.8:**

  ```sh
  sudo ./bootstrap_iot_stack.sh --stack=influx
  ```

> Výchozí přihlašovací údaje pro Grafanu a InfluxDB jsou `admin/admin`, pokud je nepřepíšete parametry.

---

## 4) Ověření po instalaci

### 4.1 Kontejnery běží?

```sh
docker ps
```

### 4.2 Grafana je dostupná?

```sh
curl -I http://localhost:3000
```

### 4.3 VictoriaMetrics test (jen `--stack=vm`)

```sh
curl -s -X POST --data-binary 'test_metric value=1' http://localhost:8428/write
curl -s 'http://localhost:8428/api/v1/query?query=test_metric'
```

### 4.4 InfluxDB test (jen `--stack=influx`)

```sh
curl -s -i -XPOST 'http://localhost:8086/write?db=iot' --data-binary 'test_metric value=1'
curl -s -G 'http://localhost:8086/query' \
  --data-urlencode 'db=iot' \
  --data-urlencode 'q=SELECT * FROM test_metric LIMIT 1'
```

---

## 5) Konfigurační přepínače

| Parametr | Popis | Výchozí |
| --- | --- | --- |
| `--stack=vm|influx` | Volba backendu | `vm` |
| `--data-dir=/opt/iotstack` | Základní adresář pro data | `/opt/iotstack` |
| `--vm-retention=30d` | Retence VictoriaMetrics | `30d` |
| `--influx-db=iot` | Název DB pro InfluxDB | `iot` |
| `--grafana-user` / `--grafana-pass` | Admin Grafana | `admin/admin` |
| `--influx-user` / `--influx-pass` | Admin InfluxDB | `admin/admin` |
| `--dry-run` | Pouze vypíše příkazy | `false` |

---

## 6) Provozní poznámky

- **Data přežijí restart**: vše je pod `$DATA_DIR/volumes`.
- **Grafana provisioning**: datasource i dashboard se vytvoří automaticky.
- **Bezpečnost**: omezte přístup na IP/VPN a změňte výchozí hesla.

---

## 7) Troubleshooting

### Grafana nejde otevřít

- Zkontrolujte, že je otevřen port **3000** v security group.
- Na hostu ověřte, že port naslouchá: `ss -tulpn | grep 3000`.

### Datasource pro VictoriaMetrics nefunguje

- Výchozí URL je `http://victoriametrics:8428` – to **funguje uvnitř Docker sítě**, protože Grafana a VictoriaMetrics běží ve stejné Compose síti.
- Pokud Grafanu provozujete **mimo Docker**, změňte URL na host‑dostupnou adresu, např. `http://localhost:8428` nebo `http://<ec2-private-ip>:8428` a otevřete TCP **8428** v security group, pokud přistupujete zvenku.

---

## 8) Úklid (odstranění)

```sh
sudo docker compose -f /opt/iotstack/compose/docker-compose.yml down
sudo rm -rf /opt/iotstack
```

Cestu upravte, pokud jste použili `--data-dir`.
