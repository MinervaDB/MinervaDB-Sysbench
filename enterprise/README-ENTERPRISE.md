# MinervaDB-Sysbench — Enterprise Edition

> **Production-Ready Scriptable Database & System Performance Benchmarking Platform**  
> Maintained by [MinervaDB](https://minervadb.com) · Built on [sysbench 1.0.x](https://github.com/akopytov/sysbench)

[![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Enterprise Ready](https://img.shields.io/badge/Enterprise-Ready-green.svg)]()
[![Production Grade](https://img.shields.io/badge/Production-Grade-brightgreen.svg)]()

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Enterprise Features](#enterprise-features)
4. [Prerequisites & System Requirements](#prerequisites--system-requirements)
5. [Installation Guide](#installation-guide)
6. [Configuration Management](#configuration-management)
7. [Running Benchmarks](#running-benchmarks)
8. [Advanced Workload Configuration](#advanced-workload-configuration)
9. [Observability & Reporting](#observability--reporting)
10. [CI/CD Integration](#cicd-integration)
11. [Security Hardening](#security-hardening)
12. [Operational Runbook](#operational-runbook)
13. [Troubleshooting](#troubleshooting)
14. [Contributing](#contributing)
15. [License](#license)

---

## Overview

MinervaDB-Sysbench is an **enterprise-grade**, production-ready wrapper and enhancement layer around the battle-tested `sysbench` benchmark engine. It is designed specifically for:

- **DBAs and infrastructure engineers** needing repeatable, auditable performance baselines
- **Platform engineering teams** embedding benchmarks into CI/CD pipelines
- **Capacity planning** workflows across MySQL, PostgreSQL, and MariaDB
- **Regression detection** across schema changes, configuration tuning, and version upgrades

### What Makes This Enterprise-Grade

| Capability | Standard sysbench | MinervaDB-Sysbench Enterprise |
|---|---|---|
| Configuration management | CLI flags only | YAML/env-file profiles per environment |
| Output formats | Plain text | JSON, CSV, Prometheus metrics |
| Error handling | Minimal | Structured exit codes + alerting hooks |
| Security | Plaintext credentials | Secrets via env vars / vault integration |
| Observability | stdout only | Structured logs + metrics export |
| CI/CD | Manual | GitHub Actions / GitLab CI templates |
| Multi-DB testing | Manual loops | Parallel matrix runner |
| Result storage | None | Timestamped result archives |
| Alerting | None | Threshold-based pass/fail with Slack/PagerDuty hooks |

---

## Architecture

```
+-------------------------------------------------------------+
|                  MinervaDB-Sysbench Enterprise               |
|                                                             |
|  +--------------+    +----------------+   +-------------+  |
|  |  Config      |    |  Benchmark     |   |  Result     |  |
|  |  Profiles    +---->  Orchestrator  +---->  Collector  |  |
|  |  (YAML/ENV)  |    |  (shell layer) |   |  & Reporter |  |
|  +--------------+    +-------+--------+   +------+------+  |
|                              |                    |         |
|                    +---------v------------------+ |         |
|                    |   sysbench core            | |         |
|                    |   (LuaJIT engine)          | |         |
|                    +---------+------------------+ |         |
|                              |               +----v------+  |
|              +---------------+----------+   |  Outputs: |  |
|              v               v          v   |  - JSON   |  |
|          MySQL/         PostgreSQL  FileIO  |  - CSV    |  |
|          MariaDB                            |  - Prom.  |  |
|                                            |  - Alerts |  |
|                                            +-----------+  |
+-------------------------------------------------------------+
```

---

## Enterprise Features

### 1. Environment-Aware Configuration Profiles
Store benchmark parameters per environment (dev, staging, production) in `enterprise/config/` env files. No more hand-crafting long CLI commands — each environment has its own tuned parameter set.

### 2. Structured JSON Output
All benchmark results are written to timestamped JSON files in `enterprise/results/` enabling downstream processing, Grafana dashboards, and long-term trending analysis.

### 3. Threshold-Based Pass/Fail (SLO Enforcement)
Define SLO thresholds (e.g., p95 < 10ms, TPS > 1000) in config files. The orchestrator exits non-zero when thresholds are breached — enabling hard CI/CD pipeline gates.

### 4. Secrets Management
Database credentials are never stored in scripts or config files. Use environment variables, `.env` files (git-excluded), or HashiCorp Vault integration via the provided helper.

### 5. Parallel Multi-Database Testing
The matrix runner (`enterprise/scripts/matrix_run.sh`) runs the same workload against multiple DB targets in parallel and produces a consolidated HTML/JSON report.

### 6. Prometheus Metrics Export
Results are pushed to a Pushgateway endpoint after each run, enabling real-time Grafana dashboards and historical trending without additional tooling.

### 7. Audit Trail & Reproducibility
Every benchmark run generates a signed run manifest capturing: hostname, timestamp, git SHA, OS version, DB version, sysbench version, and config hash — ensuring complete reproducibility of any historical result.

### 8. Ramp-Up / Graduated Load Testing
The ramp test script gradually increases thread concurrency across configurable steps, automatically finding the saturation point and generating a concurrency/latency curve.

### 9. Automatic Result Archiving
Results are automatically timestamped, compressed, and rotated per configurable retention policy. Old results are archived, not deleted.

### 10. Slack / PagerDuty Alerting
SLO violations immediately trigger configurable webhook notifications to Slack channels or PagerDuty incidents, enabling on-call response without manual result review.

---

## Prerequisites & System Requirements

### Hardware Minimums (Production Benchmarking)

| Resource | Minimum | Recommended |
|---|---|---|
| CPU cores | 4 | 16+ |
| RAM | 8 GB | 64 GB+ |
| Storage (fileio tests) | 50 GB free | 500 GB NVMe SSD |
| Network (remote DB) | 1 Gbps | 10 Gbps low-latency |

### Software Requirements

| Component | Minimum Version | Notes |
|---|---|---|
| Linux | RHEL 8+ / Ubuntu 20.04+ / Debian 10+ | x86_64 or aarch64 |
| sysbench | 1.0.20+ | Core benchmark engine |
| Bash | 4.4+ | Enterprise scripts require arrays and `declare -A` |
| Python | 3.8+ | Result processing and reporting |
| jq | 1.6+ | JSON output parsing |
| bc | any | Floating-point arithmetic for SLO checks |
| Docker | 20.10+ | Optional container deployment |
| MySQL / MariaDB | 5.7+ / 10.4+ | For OLTP benchmarks |
| PostgreSQL | 12+ | For OLTP benchmarks |

---

## Installation Guide

### Binary Package Installation

**Debian / Ubuntu:**
```bash
curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | sudo bash
sudo apt -y install sysbench jq python3 python3-pip bc
pip3 install pyyaml tabulate requests
```

**RHEL / CentOS / Rocky Linux 8+:**
```bash
curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.rpm.sh | sudo bash
sudo yum -y install sysbench jq python3 python3-pip bc
pip3 install pyyaml tabulate requests
```

**Fedora:**
```bash
curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.rpm.sh | sudo bash
sudo dnf -y install sysbench jq python3 bc
pip3 install pyyaml tabulate requests
```

**macOS (Homebrew):**
```bash
brew install sysbench jq python3
pip3 install pyyaml tabulate requests
```

### Source Build

```bash
git clone https://github.com/MinervaDB/MinervaDB-Sysbench.git
cd MinervaDB-Sysbench

# Install build dependencies (Debian/Ubuntu)
sudo apt -y install make automake libtool pkg-config libaio-dev \
    libmysqlclient-dev libssl-dev libpq-dev

./autogen.sh
./configure --with-mysql --with-pgsql
make -j$(nproc)
sudo make install

# Verify installation
sysbench --version
```

### Docker / Container Deployment

```bash
# Build the enterprise image
docker build -f enterprise/docker/Dockerfile.enterprise -t minervadb-sysbench:enterprise .

# Run a complete benchmark stack (sysbench + MySQL) via Compose
docker-compose -f enterprise/docker/docker-compose.yml up --abort-on-container-exit

# Run against an existing database
docker run --rm \
  -e DB_HOST=10.0.1.50 \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -v "$(pwd)/enterprise/results:/results" \
  minervadb-sysbench:enterprise \
  --profile production --workload oltp_read_write
```

---

## Configuration Management

### Environment Profiles

Configuration profiles live in `enterprise/config/`. Copy the template and customize for each environment:

```bash
cp enterprise/config/profile.template.env enterprise/config/production.env
vim enterprise/config/production.env
```

**Example `production.env`:**
```bash
# ============================================================
# MinervaDB-Sysbench Production Profile
# ============================================================

# === Database Connection ===
DB_TYPE=mysql                          # mysql | pgsql
DB_HOST=db-primary.prod.internal
DB_PORT=3306
DB_NAME=sbtest
DB_USER=sbtest_user
DB_SSL=on                              # on | off
# DB_PASSWORD — inject from environment; never hardcode here

# === Benchmark Workload ===
SB_THREADS=64
SB_TIME=300                            # seconds
SB_REPORT_INTERVAL=10                  # intermediate report every N seconds
SB_TABLES=20                           # number of test tables
SB_TABLE_SIZE=1000000                  # rows per table
SB_PERCENTILE=99                       # latency percentile to report
SB_WARMUP_TIME=30                      # warmup seconds (excluded from stats)
SB_RAND_TYPE=uniform                   # uniform | gaussian | special | pareto | zipfian

# === SLO Thresholds (0 = disabled) ===
SLO_MIN_TPS=5000
SLO_MAX_P95_LATENCY_MS=20
SLO_MAX_P99_LATENCY_MS=50
SLO_MAX_ERROR_RATE_PCT=0.1

# === Output & Storage ===
RESULTS_DIR=/var/lib/minervadb-sysbench/results
OUTPUT_FORMAT=json                     # json | csv | text | all

# === Integrations (leave empty to disable) ===
PROMETHEUS_PUSHGATEWAY=               # http://pushgw:9091
SLACK_WEBHOOK_URL=                    # https://hooks.slack.com/services/...
PAGERDUTY_ROUTING_KEY=               # PD integration key for SLO violations
```

### Secret Injection

Never commit credentials. Use one of the following approaches:

```bash
# Method 1: Runtime environment variable (recommended for CI/CD)
export DB_PASSWORD="$(vault kv get -field=password secret/db/sbtest)"
./enterprise/scripts/run_benchmark.sh --profile production

# Method 2: Restricted .env file (600 permissions, git-excluded)
echo "DB_PASSWORD=secret" >> enterprise/config/production.local.env
chmod 600 enterprise/config/production.local.env

# Method 3: Kubernetes secret
kubectl create secret generic sbtest-db --from-literal=password=secret
# Reference via envFrom in the pod spec

# Method 4: AWS Secrets Manager (via helper)
export DB_PASSWORD="$(./enterprise/scripts/secrets_helper.sh aws-sm prod/bench/db-password)"
```

---

## Running Benchmarks

### Quick Start

```bash
# 1. Set credentials
export DB_HOST=localhost DB_USER=sbtest DB_PASSWORD=secret DB_NAME=sbtest

# 2. Prepare test tables
./enterprise/scripts/run_benchmark.sh --profile dev --command prepare

# 3. Run OLTP read/write workload
./enterprise/scripts/run_benchmark.sh --profile dev --workload oltp_read_write --command run

# 4. Clean up test tables
./enterprise/scripts/run_benchmark.sh --profile dev --command cleanup
```

### OLTP Benchmarks

| Workload | Script | Use Case |
|---|---|---|
| Read/Write Mixed | `oltp_read_write` | General OLTP baseline (default) |
| Read-Only | `oltp_read_only` | Read replica / cache effectiveness |
| Write-Only | `oltp_write_only` | Write-heavy insert/update scenarios |
| Point Selects | `oltp_point_select` | Primary key lookup performance |
| Insert | `oltp_insert` | Bulk insert throughput |
| Delete | `oltp_delete` | Purge / archival workload performance |
| Update Index | `oltp_update_index` | Index maintenance overhead |
| Update Non-Index | `oltp_update_non_index` | Row update without index churn |

```bash
# Read-only benchmark against production replica (300s, 128 threads)
./enterprise/scripts/run_benchmark.sh \
  --profile production \
  --workload oltp_read_only \
  --threads 128 \
  --time 600 \
  --command run
```

### Filesystem Benchmarks

```bash
# Sequential write — baseline for SSD vs HDD classification
./enterprise/scripts/run_benchmark.sh \
  --workload fileio \
  --fileio-mode seqwr \
  --file-total-size 10G \
  --threads 16 \
  --command run

# Random read/write — simulates InnoDB buffer pool miss pattern
./enterprise/scripts/run_benchmark.sh \
  --workload fileio \
  --fileio-mode rndrw \
  --file-total-size 10G \
  --file-block-size 16384 \
  --command run
```

### CPU & Memory Benchmarks

```bash
# CPU benchmark — prime number computation, cross-core comparison
./enterprise/scripts/run_benchmark.sh \
  --workload cpu \
  --cpu-max-prime 20000 \
  --threads 32

# Memory bandwidth benchmark — write saturation test
./enterprise/scripts/run_benchmark.sh \
  --workload memory \
  --memory-block-size 1M \
  --memory-total-size 100G \
  --memory-operation write
```

### Multi-Environment Execution (Matrix Runner)

```bash
# Run the same OLTP workload across dev, staging, and production sequentially
./enterprise/scripts/matrix_run.sh \
  --profiles dev,staging,production \
  --workload oltp_read_write \
  --output-report /tmp/matrix_report.html

# Parallel multi-target execution (use with caution on production)
./enterprise/scripts/matrix_run.sh \
  --profiles dev,staging \
  --workload oltp_read_only \
  --parallel \
  --output-report /tmp/parallel_report.json
```

### Graduated Load (Ramp-Up) Testing

```bash
# Automatically test thread counts: 1,2,4,8,16,32,64,128 for 60s each
# Identifies saturation point and produces TPS vs concurrency curve
./enterprise/scripts/ramp_test.sh \
  --profile production \
  --workload oltp_read_write \
  --steps 1,2,4,8,16,32,64,128 \
  --step-duration 60
```

---

## Advanced Workload Configuration

### Custom Lua Scripts

Place custom workload scripts in `enterprise/workloads/` and reference them by path:

```bash
./enterprise/scripts/run_benchmark.sh \
  --workload enterprise/workloads/custom_mixed.lua \
  --profile production
```

**Example custom workload (`enterprise/workloads/custom_mixed.lua`):**
```lua
-- Custom workload: 70% point selects, 20% updates, 10% inserts
-- Mimics a typical social media application read/write ratio

local oltp_common = require("oltp_common")

function thread_init()
   oltp_common.set_vars()
end

function event()
   local r = math.random(100)
   if r <= 70 then
      oltp_common.point_selects()
   elseif r <= 90 then
      oltp_common.non_index_updates()
   else
      oltp_common.bulk_inserts()
   end
end

function sysbench.hooks.report_intermediate(stat)
   oltp_common.report_intermediate(stat)
end
```

### Parameterized Table Schemas

For testing with production-like schemas, use the schema override feature:

```bash
# Use a custom table DDL instead of sysbench's default schema
./enterprise/scripts/run_benchmark.sh \
  --workload enterprise/workloads/custom_schema.lua \
  --custom-schema enterprise/schemas/ecommerce_orders.sql \
  --profile staging
```

---

## Observability & Reporting

### JSON Result Structure

Every run produces a structured JSON result in `enterprise/results/`:

```json
{
  "run_id": "20260612-143022-abc123",
  "timestamp": "2026-06-12T14:30:22Z",
  "hostname": "bench-node-01",
  "git_sha": "df89d34",
  "profile": "production",
  "workload": "oltp_read_write",
  "db_type": "mysql",
  "db_version": "8.0.35-MySQL Community Server",
  "sysbench_version": "1.0.20",
  "os_release": "Ubuntu 22.04.3 LTS",
  "config": {
    "threads": 64,
    "time": 300,
    "warmup_time": 30,
    "tables": 20,
    "table_size": 1000000,
    "percentile": 99
  },
  "results": {
    "tps": 12547.83,
    "qps": 250956.6,
    "latency_avg_ms": 5.1,
    "latency_p95_ms": 9.84,
    "latency_p99_ms": 14.23,
    "latency_max_ms": 147.22,
    "errors_per_sec": 0.00,
    "reconnects_per_sec": 0.00,
    "total_transactions": 3764349,
    "total_queries": 75286980
  },
  "slo_status": "PASS",
  "slo_violations": [],
  "duration_actual_sec": 300.12
}
```

### Prometheus Metrics Push

When `PROMETHEUS_PUSHGATEWAY` is set in the profile, these metrics are pushed:

```
minervadb_sysbench_tps{profile="production",workload="oltp_read_write",host="bench01"} 12547.83
minervadb_sysbench_qps{...} 250956.6
minervadb_sysbench_latency_avg_ms{...} 5.1
minervadb_sysbench_latency_p95_ms{...} 9.84
minervadb_sysbench_latency_p99_ms{...} 14.23
minervadb_sysbench_errors_per_sec{...} 0.00
minervadb_sysbench_slo_pass{...} 1
minervadb_sysbench_run_timestamp_unix{...} 1749737422
```

### Grafana Dashboard

Import `enterprise/dashboards/minervadb-sysbench-grafana.json` into Grafana. The pre-built dashboard provides:

- **TPS / QPS** over time with configurable environment selector
- **Latency percentile heatmaps** (p50, p95, p99)
- **SLO compliance gauge** with color-coded pass/fail
- **Concurrency vs Throughput** scatter plot (from ramp tests)
- **Cross-environment comparison** panels

### HTML Reports

Generate a standalone HTML report for sharing with stakeholders:

```bash
python3 enterprise/scripts/generate_report.py \
  --results-dir enterprise/results/ \
  --output /tmp/benchmark_report.html \
  --compare-last 7d
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/nightly_benchmark.yml
name: Nightly Database Benchmark
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:
    inputs:
      profile:
        description: 'Benchmark profile'
        required: false
        default: 'staging'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - name: Install sysbench & dependencies
        run: |
          curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | sudo bash
          sudo apt-get -y install sysbench jq bc python3 python3-pip
          pip3 install pyyaml tabulate requests

      - name: Prepare benchmark tables
        env:
          DB_HOST: ${{ secrets.BENCH_DB_HOST }}
          DB_USER: ${{ secrets.BENCH_DB_USER }}
          DB_PASSWORD: ${{ secrets.BENCH_DB_PASSWORD }}
        run: |
          ./enterprise/scripts/run_benchmark.sh \
            --profile ${{ github.event.inputs.profile || 'staging' }} \
            --workload oltp_read_write \
            --command prepare

      - name: Run benchmark
        env:
          DB_HOST: ${{ secrets.BENCH_DB_HOST }}
          DB_USER: ${{ secrets.BENCH_DB_USER }}
          DB_PASSWORD: ${{ secrets.BENCH_DB_PASSWORD }}
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_BENCH_WEBHOOK }}
        run: |
          ./enterprise/scripts/run_benchmark.sh \
            --profile ${{ github.event.inputs.profile || 'staging' }} \
            --workload oltp_read_write \
            --command run

      - name: Cleanup
        if: always()
        env:
          DB_HOST: ${{ secrets.BENCH_DB_HOST }}
          DB_USER: ${{ secrets.BENCH_DB_USER }}
          DB_PASSWORD: ${{ secrets.BENCH_DB_PASSWORD }}
        run: |
          ./enterprise/scripts/run_benchmark.sh \
            --profile ${{ github.event.inputs.profile || 'staging' }} \
            --command cleanup

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-results-${{ github.run_id }}
          path: enterprise/results/
          retention-days: 90
```

### GitLab CI

```yaml
benchmark:nightly:
  stage: benchmark
  image: ubuntu:22.04
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_PIPELINE_SOURCE == "web"
  before_script:
    - apt-get update -qq && apt-get install -y curl jq bc python3 python3-pip
    - curl -s https://packagecloud.io/install/repositories/akopytov/sysbench/script.deb.sh | bash
    - apt-get install -y sysbench
    - pip3 install pyyaml tabulate requests
  script:
    - ./enterprise/scripts/run_benchmark.sh --profile staging --workload oltp_read_write --command prepare
    - ./enterprise/scripts/run_benchmark.sh --profile staging --workload oltp_read_write --command run
  after_script:
    - ./enterprise/scripts/run_benchmark.sh --profile staging --command cleanup || true
  artifacts:
    paths:
      - enterprise/results/
    expire_in: 30 days
  variables:
    DB_HOST: $BENCH_DB_HOST
    DB_PASSWORD: $BENCH_DB_PASSWORD
```

---

## Security Hardening

### Database User — Least Privilege

Create a dedicated benchmark user with only the required privileges:

**MySQL / MariaDB:**
```sql
CREATE USER 'sbtest'@'10.0.1.%' IDENTIFIED BY 'StrongRandomPassword!';
CREATE DATABASE IF NOT EXISTS sbtest CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT CREATE, DROP, INSERT, UPDATE, DELETE, SELECT, INDEX, ALTER
  ON sbtest.* TO 'sbtest'@'10.0.1.%';
FLUSH PRIVILEGES;

-- After benchmarking, revoke and drop (optional hardening)
-- REVOKE ALL ON sbtest.* FROM 'sbtest'@'10.0.1.%';
-- DROP USER 'sbtest'@'10.0.1.%';
```

**PostgreSQL:**
```sql
CREATE ROLE sbtest WITH LOGIN PASSWORD 'StrongRandomPassword!';
CREATE DATABASE sbtest OWNER sbtest ENCODING 'UTF8';
\c sbtest
GRANT ALL ON SCHEMA public TO sbtest;
```

### Network Security

- Run benchmarks from a **dedicated benchmark host**, never from application servers
- Use **TLS/SSL** for all connections: add `--mysql-ssl=on` to MySQL or `--pgsql-sslmode=require` to PostgreSQL profiles
- Restrict the benchmark DB user to specific source IP CIDR ranges
- Use **VPN or SSH tunneling** when benchmarking production databases from external networks
- Ensure the benchmark host is **not internet-accessible**

### File and Process Hardening

```bash
# Protect config files containing sensitive values
chmod 600 enterprise/config/*.env
chmod 600 enterprise/config/*.local.env

# Run benchmark scripts as a dedicated non-root service account
useradd -r -s /sbin/nologin -d /var/lib/minervadb-sysbench minervadb-bench
chown -R minervadb-bench:minervadb-bench /var/lib/minervadb-sysbench/
su -s /bin/bash minervadb-bench -c './enterprise/scripts/run_benchmark.sh --profile production'
```

### Credential Best Practices

```bash
# GOOD: Inject from HashiCorp Vault
export DB_PASSWORD="$(vault kv get -field=password secret/db/sbtest)"

# GOOD: Read from permission-restricted file
source /etc/minervadb-sysbench/secrets.env   # chmod 600, owned by service account

# GOOD: AWS Secrets Manager
export DB_PASSWORD="$(aws secretsmanager get-secret-value \
  --secret-id prod/bench/db-password --query SecretString --output text | jq -r .password)"

# BAD: Never store in scripts or commit to git
./run_benchmark.sh --db-password=plaintextpassword       # NEVER

# BAD: Never log credentials
echo "Connecting with password: $DB_PASSWORD"            # NEVER
```

---

## Operational Runbook

### Pre-Benchmark Checklist

- [ ] Confirm database server is **not primary production** (use replica or isolated test DB)
- [ ] Record baseline DB configuration: `SHOW GLOBAL VARIABLES; SHOW GLOBAL STATUS;`
- [ ] Verify sufficient disk space: `df -h` (need 2x file-total-size free for fileio tests)
- [ ] Disable OS power management and CPU frequency scaling (see below)
- [ ] Record OS and DB version, kernel version in the run manifest
- [ ] Ensure NTP sync between benchmark host and DB host (`chronyc tracking`)
- [ ] Pre-warm the DB buffer pool if testing steady-state performance
- [ ] Disable or quiesce scheduled jobs (backups, ANALYZE, VACUUM) during the benchmark window
- [ ] Verify network path MTU and no packet loss: `ping -s 1472 -c 100 $DB_HOST`

### Disabling CPU Frequency Scaling (Linux)

```bash
# Set all cores to performance governor for consistent results
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance | sudo tee "$cpu" > /dev/null
done

# Verify
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# Expected output: performance
```

### Buffer Pool Warm-Up

```bash
# For InnoDB: pre-warm by running a read-only workload before the timed run
./enterprise/scripts/run_benchmark.sh \
  --profile production \
  --workload oltp_read_only \
  --threads 16 \
  --time 120 \
  --command run
# Then run the actual timed benchmark
```

### Post-Benchmark Cleanup

```bash
# Remove benchmark tables from the database
./enterprise/scripts/run_benchmark.sh --profile production --command cleanup

# Archive results with timestamp
tar -czf "benchmark-results-$(date +%Y%m%d-%H%M%S).tar.gz" enterprise/results/
mv "benchmark-results-*.tar.gz" /archive/benchmarks/

# Rotate result files older than 90 days
find enterprise/results/ -name "*.json" -mtime +90 -delete

# Re-enable CPU frequency scaling (if changed)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo ondemand | sudo tee "$cpu" > /dev/null
done
```

### Interpreting Results

| Metric | Meaning | Warning Signs |
|---|---|---|
| TPS | Transactions per second — primary throughput metric | Below SLO threshold; declining trend across runs |
| QPS | Queries per second | Unusual ratio to TPS may indicate plan changes |
| Latency avg | Mean response time | >10ms for latency-sensitive OLTP |
| Latency p95 | 95th percentile — "tail latency" | >50ms affects ~5% of users |
| Latency p99 | 99th percentile — worst 1% | >100ms indicates outliers/lock contention |
| Latency max | Single worst request | Spikes indicate lock waits or GC pauses |
| Errors/sec | Failed transactions | Any non-zero value requires investigation |
| Reconnects/sec | Connection instability | Any non-zero value indicates network/auth issues |

---

## Troubleshooting

### FATAL: Cannot Connect to MySQL/PostgreSQL Server

```bash
# Test connectivity directly
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;"
# Check port is reachable
nc -zv "$DB_HOST" "$DB_PORT"
# Check firewall rules
sudo iptables -L -n | grep "$DB_PORT"
```

### ERROR 1044: Access Denied for User

```sql
-- Check user exists and has correct grants
SELECT host, user FROM mysql.user WHERE user = 'sbtest';
SHOW GRANTS FOR 'sbtest'@'%';
-- Re-run the grant statements in the Security Hardening section
```

### Low TPS on First Run (Cold Cache)

Add warmup time to the profile:
```bash
SB_WARMUP_TIME=120   # 2 minutes of excluded warmup
```

### sysbench: Command Not Found

```bash
which sysbench && sysbench --version
# If not found, re-run the package installation:
sudo apt-get install --reinstall sysbench   # Debian/Ubuntu
sudo yum reinstall sysbench                 # RHEL/CentOS
```

### High Latency Variance / Jitter

- Check for background MySQL jobs: `SHOW PROCESSLIST;`
- Check for InnoDB page flushing spikes: monitor `Innodb_buffer_pool_pages_dirty`
- Verify CPU governor is set to `performance`
- Check for network retransmits: `ss -s` and `netstat -s | grep retransmit`
- Disable transparent huge pages: `echo never > /sys/kernel/mm/transparent_hugepage/enabled`

### Out of Disk During Fileio Tests

```bash
# Check available space before running
df -h .
du -sh enterprise/results/
# Reduce file size in profile or use smaller block count
SB_FILE_TOTAL_SIZE=5G   # reduce from default 100G
```

### SLO Violations in CI/CD Pipeline

When the benchmark exits with non-zero status due to SLO violation:

```bash
# Review the latest result
cat $(ls -t enterprise/results/*.json | head -1) | jq '.slo_violations'
# Example output:
# [{"metric": "p99_latency_ms", "threshold": 50, "actual": 67.3, "status": "FAIL"}]
```

---

## Contributing

We welcome contributions from the community and enterprise users.

### Development Workflow

```bash
# Fork the repository and create a feature branch
git checkout -b feature/enterprise-enhancement

# Make changes, ensure scripts pass shellcheck
shellcheck enterprise/scripts/*.sh

# Run the test suite
cd tests && ./test_run.sh

# Commit with conventional commit format
git commit -m "feat(enterprise): add Redis benchmark workload support"
git push origin feature/enterprise-enhancement
# Open a Pull Request
```

### Code Standards

- Shell scripts must pass `shellcheck` with no warnings
- All new features require a corresponding entry in `enterprise/CHANGELOG.md`
- New configuration options must be documented in `profile.template.env`
- Result-affecting changes require benchmark comparisons in the PR description

### Enterprise Support & Consulting

For enterprise support, custom workload development, performance consulting, and SLA-backed production assistance, contact the MinervaDB team:

- **Website**: https://minervadb.com
- **Email**: info@minervadb.com
- **GitHub Issues**: https://github.com/MinervaDB/MinervaDB-Sysbench/issues

---

## License

MinervaDB-Sysbench is licensed under the **GNU General Public License v2.0**.  
See [COPYING](../COPYING) for the full license text.

---

*Documentation maintained by the MinervaDB Engineering Team. Last updated: June 2026.*
