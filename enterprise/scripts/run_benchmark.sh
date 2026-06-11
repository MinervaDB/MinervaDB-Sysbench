#!/usr/bin/env bash
# =============================================================================
# MinervaDB-Sysbench Enterprise — Benchmark Orchestrator
# =============================================================================
# Script:  enterprise/scripts/run_benchmark.sh
# Purpose: Production-grade wrapper around sysbench with environment profiles,
#          structured JSON output, SLO enforcement, and alerting hooks.
#
# Usage:
#   ./enterprise/scripts/run_benchmark.sh [OPTIONS]
#
# Options:
#   --profile    <name>      Environment profile name (default: dev)
#                            Loads enterprise/config/<name>.env
#   --workload   <name>      sysbench workload/script (default: oltp_read_write)
#   --command    <cmd>       prepare | run | cleanup (default: run)
#   --threads    <n>         Override SB_THREADS from profile
#   --time       <s>         Override SB_TIME from profile
#   --tables     <n>         Override SB_TABLES from profile
#   --table-size <n>         Override SB_TABLE_SIZE from profile
#   --results-dir <path>     Override RESULTS_DIR from profile
#   --dry-run                Print the sysbench command without executing it
#   --help                   Show this help message
#
# Environment Variables (can override profile values):
#   DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME, DB_TYPE
#   SB_THREADS, SB_TIME, SB_TABLES, SB_TABLE_SIZE
#   SLACK_WEBHOOK_URL, PROMETHEUS_PUSHGATEWAY
#
# Exit Codes:
#   0   Benchmark completed successfully, all SLOs passed
#   1   General error (missing deps, config error, DB connection failure)
#   2   Benchmark completed but one or more SLO thresholds were violated
#   3   Benchmark timed out or was interrupted
#
# Examples:
#   # Run OLTP read/write against production profile for 5 minutes
#   DB_PASSWORD=secret ./run_benchmark.sh --profile production --workload oltp_read_write
#
#   # Quick dev test with 4 threads for 30 seconds
#   ./run_benchmark.sh --profile dev --threads 4 --time 30
#
#   # Dry-run to preview the sysbench command
#   ./run_benchmark.sh --profile staging --dry-run
#
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & Defaults
# ---------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly ENTERPRISE_DIR="${REPO_ROOT}/enterprise"
readonly CONFIG_DIR="${ENTERPRISE_DIR}/config"
readonly RESULTS_DIR_DEFAULT="${ENTERPRISE_DIR}/results"
readonly TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
readonly RUN_ID="${TIMESTAMP}-$(head -c4 /dev/urandom | xxd -p 2>/dev/null || echo 'xxxx')"
readonly LOG_PREFIX="[MinervaDB-Sysbench][${TIMESTAMP}]"

# ---------------------------------------------------------------------------
# Color Output (disabled when not a TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; BLUE=''; BOLD=''; RESET=''
fi

log_info()  { echo -e "${BLUE}${LOG_PREFIX}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}${LOG_PREFIX}[WARN]${RESET}  $*" >&2; }
log_error() { echo -e "${RED}${LOG_PREFIX}[ERROR]${RESET} $*" >&2; }
log_ok()    { echo -e "${GREEN}${LOG_PREFIX}[OK]${RESET}    $*"; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  grep '^#' "${BASH_SOURCE[0]}" | grep -v '#!/' | sed 's/^# \{0,1\}//' | head -60
  exit 0
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
PROFILE="dev"
WORKLOAD="oltp_read_write"
COMMAND="run"
DRY_RUN=false
OVERRIDE_THREADS=""
OVERRIDE_TIME=""
OVERRIDE_TABLES=""
OVERRIDE_TABLE_SIZE=""
OVERRIDE_RESULTS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)     PROFILE="$2";             shift 2 ;;
    --workload)    WORKLOAD="$2";            shift 2 ;;
    --command)     COMMAND="$2";             shift 2 ;;
    --threads)     OVERRIDE_THREADS="$2";   shift 2 ;;
    --time)        OVERRIDE_TIME="$2";      shift 2 ;;
    --tables)      OVERRIDE_TABLES="$2";    shift 2 ;;
    --table-size)  OVERRIDE_TABLE_SIZE="$2";shift 2 ;;
    --results-dir) OVERRIDE_RESULTS_DIR="$2";shift 2 ;;
    --dry-run)     DRY_RUN=true;             shift ;;
    --help|-h)     usage ;;
    *) log_error "Unknown option: $1"; usage ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate command
# ---------------------------------------------------------------------------
case "$COMMAND" in
  prepare|run|cleanup) ;;
  *) log_error "Invalid command '${COMMAND}'. Must be: prepare, run, or cleanup."; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Check Dependencies
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()
  for cmd in sysbench jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing[*]}"
    log_error "Install with: sudo apt-get install sysbench jq bc (Debian/Ubuntu)"
    log_error "              sudo yum install sysbench jq bc      (RHEL/CentOS)"
    exit 1
  fi
  log_ok "All dependencies satisfied (sysbench $(sysbench --version 2>&1 | head -1))"
}

# ---------------------------------------------------------------------------
# Load Configuration Profile
# ---------------------------------------------------------------------------
load_profile() {
  local profile_file="${CONFIG_DIR}/${PROFILE}.env"
  local local_file="${CONFIG_DIR}/${PROFILE}.local.env"

  if [[ ! -f "$profile_file" ]]; then
    log_error "Profile not found: $profile_file"
    log_error "Available profiles:"
    ls "${CONFIG_DIR}"/*.env 2>/dev/null | xargs -n1 basename | sed 's/.env//' || true
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$profile_file"
  log_info "Loaded profile: $profile_file"

  # Load local overrides (git-excluded, for secrets)
  if [[ -f "$local_file" ]]; then
    # shellcheck source=/dev/null
    source "$local_file"
    log_info "Loaded local overrides: $local_file"
  fi

  # Apply CLI overrides
  [[ -n "$OVERRIDE_THREADS" ]]    && SB_THREADS="$OVERRIDE_THREADS"
  [[ -n "$OVERRIDE_TIME" ]]       && SB_TIME="$OVERRIDE_TIME"
  [[ -n "$OVERRIDE_TABLES" ]]     && SB_TABLES="$OVERRIDE_TABLES"
  [[ -n "$OVERRIDE_TABLE_SIZE" ]] && SB_TABLE_SIZE="$OVERRIDE_TABLE_SIZE"
  [[ -n "$OVERRIDE_RESULTS_DIR" ]]&& RESULTS_DIR="$OVERRIDE_RESULTS_DIR"

  # Set defaults for optional vars
  DB_TYPE="${DB_TYPE:-mysql}"
  DB_HOST="${DB_HOST:-localhost}"
  DB_PORT="${DB_PORT:-3306}"
  DB_NAME="${DB_NAME:-sbtest}"
  DB_USER="${DB_USER:-sbtest}"
  DB_SSL="${DB_SSL:-off}"
  SB_THREADS="${SB_THREADS:-4}"
  SB_TIME="${SB_TIME:-60}"
  SB_TABLES="${SB_TABLES:-4}"
  SB_TABLE_SIZE="${SB_TABLE_SIZE:-10000}"
  SB_PERCENTILE="${SB_PERCENTILE:-95}"
  SB_WARMUP_TIME="${SB_WARMUP_TIME:-0}"
  SB_REPORT_INTERVAL="${SB_REPORT_INTERVAL:-10}"
  SB_RAND_TYPE="${SB_RAND_TYPE:-uniform}"
  SLO_MIN_TPS="${SLO_MIN_TPS:-0}"
  SLO_MAX_P95_LATENCY_MS="${SLO_MAX_P95_LATENCY_MS:-0}"
  SLO_MAX_P99_LATENCY_MS="${SLO_MAX_P99_LATENCY_MS:-0}"
  SLO_MAX_ERROR_RATE_PCT="${SLO_MAX_ERROR_RATE_PCT:-0}"
  RESULTS_DIR="${RESULTS_DIR:-${RESULTS_DIR_DEFAULT}}"
  OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"
  PROMETHEUS_PUSHGATEWAY="${PROMETHEUS_PUSHGATEWAY:-}"
  SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
  PAGERDUTY_ROUTING_KEY="${PAGERDUTY_ROUTING_KEY:-}"
}

# ---------------------------------------------------------------------------
# Validate Required Variables
# ---------------------------------------------------------------------------
validate_config() {
  local errors=()

  [[ -z "${DB_HOST:-}" ]]     && errors+=("DB_HOST is not set")
  [[ -z "${DB_USER:-}" ]]     && errors+=("DB_USER is not set")
  [[ -z "${DB_PASSWORD:-}" ]] && errors+=("DB_PASSWORD is not set — set via environment variable")
  [[ -z "${DB_NAME:-}" ]]     && errors+=("DB_NAME is not set")

  if [[ ${#errors[@]} -gt 0 ]]; then
    log_error "Configuration errors:"
    for err in "${errors[@]}"; do
      log_error "  - $err"
    done
    exit 1
  fi

  log_info "Configuration validated:"
  log_info "  DB:       ${DB_TYPE}://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
  log_info "  Workload: ${WORKLOAD}"
  log_info "  Threads:  ${SB_THREADS}"
  log_info "  Duration: ${SB_TIME}s (warmup: ${SB_WARMUP_TIME}s)"
  log_info "  Tables:   ${SB_TABLES} x ${SB_TABLE_SIZE} rows"
}

# ---------------------------------------------------------------------------
# Build sysbench Command
# ---------------------------------------------------------------------------
build_sysbench_cmd() {
  local cmd="sysbench"

  # Database driver options
  case "${DB_TYPE}" in
    mysql|mariadb)
      cmd+=" --db-driver=mysql"
      cmd+=" --mysql-host=${DB_HOST}"
      cmd+=" --mysql-port=${DB_PORT}"
      cmd+=" --mysql-user=${DB_USER}"
      cmd+=" --mysql-password=${DB_PASSWORD}"
      cmd+=" --mysql-db=${DB_NAME}"
      [[ "${DB_SSL}" == "on" ]] && cmd+=" --mysql-ssl=on"
      ;;
    pgsql|postgresql|postgres)
      cmd+=" --db-driver=pgsql"
      cmd+=" --pgsql-host=${DB_HOST}"
      cmd+=" --pgsql-port=${DB_PORT}"
      cmd+=" --pgsql-user=${DB_USER}"
      cmd+=" --pgsql-password=${DB_PASSWORD}"
      cmd+=" --pgsql-db=${DB_NAME}"
      ;;
    *)
      log_error "Unsupported DB_TYPE: ${DB_TYPE}. Supported: mysql, mariadb, pgsql, postgresql"
      exit 1
      ;;
  esac

  # Workload-specific options (only for OLTP workloads)
  if [[ "${WORKLOAD}" == oltp_* ]] || [[ "${WORKLOAD}" == *"oltp"* ]]; then
    cmd+=" --tables=${SB_TABLES}"
    cmd+=" --table-size=${SB_TABLE_SIZE}"
  fi

  # General options
  cmd+=" --threads=${SB_THREADS}"
  cmd+=" --time=${SB_TIME}"
  cmd+=" --report-interval=${SB_REPORT_INTERVAL}"
  cmd+=" --percentile=${SB_PERCENTILE}"
  cmd+=" --rand-type=${SB_RAND_TYPE}"
  [[ "${SB_WARMUP_TIME}" -gt 0 ]] && cmd+=" --warmup-time=${SB_WARMUP_TIME}"

  cmd+=" ${WORKLOAD}"
  cmd+=" ${COMMAND}"

  echo "$cmd"
}

# ---------------------------------------------------------------------------
# Parse Results from sysbench Output
# ---------------------------------------------------------------------------
parse_results() {
  local output="$1"
  local tps qps lat_avg lat_p95 lat_p99 lat_max err_rate reconnects

  tps="$(echo "$output" | grep -oP 'transactions:.*?\(\K[0-9.]+(?= per sec)' || echo '0')"
  qps="$(echo "$output" | grep -oP 'queries:.*?\(\K[0-9.]+(?= per sec)' || echo '0')"
  lat_avg="$(echo "$output" | grep 'avg:' | grep -oP '[0-9.]+' | head -1 || echo '0')"
  lat_p95="$(echo "$output" | grep '95th percentile' | grep -oP '[0-9.]+' || echo '0')"
  lat_p99="$(echo "$output" | grep 'percentile' | awk '{print $NF}' | head -1 || echo '0')"
  lat_max="$(echo "$output" | grep 'max:' | grep -oP '[0-9.]+' | head -1 || echo '0')"
  err_rate="$(echo "$output" | grep 'ignored errors' | grep -oP '[0-9.]+(?= per sec)' || echo '0')"
  reconnects="$(echo "$output" | grep 'reconnects' | grep -oP '[0-9.]+(?= per sec)' || echo '0')"

  echo "${tps}|${qps}|${lat_avg}|${lat_p95}|${lat_p99}|${lat_max}|${err_rate}|${reconnects}"
}

# ---------------------------------------------------------------------------
# Check SLO Thresholds
# ---------------------------------------------------------------------------
check_slos() {
  local tps="$1" lat_p95="$2" lat_p99="$3" err_rate="$4"
  local violations=()
  local slo_status="PASS"

  # TPS minimum
  if [[ "$SLO_MIN_TPS" -gt 0 ]]; then
    if (( $(echo "$tps < $SLO_MIN_TPS" | bc -l) )); then
      violations+=("{"metric":"tps","threshold":$SLO_MIN_TPS,"actual":$tps,"status":"FAIL"}")
      slo_status="FAIL"
      log_warn "SLO VIOLATION: TPS ${tps} < minimum ${SLO_MIN_TPS}"
    fi
  fi

  # P95 latency maximum
  if [[ "$SLO_MAX_P95_LATENCY_MS" -gt 0 ]]; then
    if (( $(echo "$lat_p95 > $SLO_MAX_P95_LATENCY_MS" | bc -l) )); then
      violations+=("{"metric":"p95_latency_ms","threshold":$SLO_MAX_P95_LATENCY_MS,"actual":$lat_p95,"status":"FAIL"}")
      slo_status="FAIL"
      log_warn "SLO VIOLATION: P95 latency ${lat_p95}ms > maximum ${SLO_MAX_P95_LATENCY_MS}ms"
    fi
  fi

  # P99 latency maximum
  if [[ "$SLO_MAX_P99_LATENCY_MS" -gt 0 ]]; then
    if (( $(echo "$lat_p99 > $SLO_MAX_P99_LATENCY_MS" | bc -l) )); then
      violations+=("{"metric":"p99_latency_ms","threshold":$SLO_MAX_P99_LATENCY_MS,"actual":$lat_p99,"status":"FAIL"}")
      slo_status="FAIL"
      log_warn "SLO VIOLATION: P99 latency ${lat_p99}ms > maximum ${SLO_MAX_P99_LATENCY_MS}ms"
    fi
  fi

  # Error rate maximum
  if [[ "$SLO_MAX_ERROR_RATE_PCT" != "0" ]]; then
    if (( $(echo "$err_rate > $SLO_MAX_ERROR_RATE_PCT" | bc -l) )); then
      violations+=("{"metric":"error_rate_pct","threshold":$SLO_MAX_ERROR_RATE_PCT,"actual":$err_rate,"status":"FAIL"}")
      slo_status="FAIL"
      log_warn "SLO VIOLATION: Error rate ${err_rate}% > maximum ${SLO_MAX_ERROR_RATE_PCT}%"
    fi
  fi

  VIOLATIONS_JSON="[$(IFS=,; echo "${violations[*]}")]"
  echo "$slo_status"
}

# ---------------------------------------------------------------------------
# Write JSON Result
# ---------------------------------------------------------------------------
write_json_result() {
  local tps="$1" qps="$2" lat_avg="$3" lat_p95="$4" lat_p99="$5"
  local lat_max="$6" err_rate="$7" reconnects="$8" slo_status="$9"
  local duration="${10:-$SB_TIME}"

  mkdir -p "${RESULTS_DIR}"
  local result_file="${RESULTS_DIR}/${RUN_ID}-${PROFILE}-${WORKLOAD//\//_}.json"

  local git_sha db_version os_release sb_version
  git_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  db_version="$(sysbench --db-driver=mysql --mysql-host="${DB_HOST}" \
    --mysql-user="${DB_USER}" --mysql-password="${DB_PASSWORD}" \
    --mysql-db="${DB_NAME}" --tables=1 --table-size=1 oltp_read_only run 2>&1 | \
    grep -i 'server version' | head -1 || echo 'unknown')"
  os_release="$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo 'unknown')"
  sb_version="$(sysbench --version 2>&1 | head -1 || echo 'unknown')"

  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg host "$(hostname -f 2>/dev/null || hostname)" \
    --arg git_sha "${git_sha}" \
    --arg profile "${PROFILE}" \
    --arg workload "${WORKLOAD}" \
    --arg db_type "${DB_TYPE}" \
    --arg db_host "${DB_HOST}" \
    --arg sb_version "${sb_version}" \
    --arg os_release "${os_release}" \
    --argjson threads "${SB_THREADS}" \
    --argjson time "${SB_TIME}" \
    --argjson warmup "${SB_WARMUP_TIME}" \
    --argjson tables "${SB_TABLES}" \
    --argjson tsize "${SB_TABLE_SIZE}" \
    --argjson pct "${SB_PERCENTILE}" \
    --argjson tps "${tps:-0}" \
    --argjson qps "${qps:-0}" \
    --argjson lat_avg "${lat_avg:-0}" \
    --argjson lat_p95 "${lat_p95:-0}" \
    --argjson lat_p99 "${lat_p99:-0}" \
    --argjson lat_max "${lat_max:-0}" \
    --argjson errors "${err_rate:-0}" \
    --argjson reconnects "${reconnects:-0}" \
    --arg slo_status "${slo_status}" \
    --argjson slo_violations "${VIOLATIONS_JSON:-[]}" \
    --argjson duration "${duration}" \
    '{
      run_id: $run_id,
      timestamp: $ts,
      hostname: $host,
      git_sha: $git_sha,
      profile: $profile,
      workload: $workload,
      db_type: $db_type,
      db_host: $db_host,
      sysbench_version: $sb_version,
      os_release: $os_release,
      config: {
        threads: $threads,
        time: $time,
        warmup_time: $warmup,
        tables: $tables,
        table_size: $tsize,
        percentile: $pct
      },
      results: {
        tps: $tps,
        qps: $qps,
        latency_avg_ms: $lat_avg,
        latency_p95_ms: $lat_p95,
        latency_p99_ms: $lat_p99,
        latency_max_ms: $lat_max,
        errors_per_sec: $errors,
        reconnects_per_sec: $reconnects
      },
      slo_status: $slo_status,
      slo_violations: $slo_violations,
      duration_actual_sec: $duration
    }' > "${result_file}"

  log_ok "Results written: ${result_file}"
  echo "${result_file}"
}

# ---------------------------------------------------------------------------
# Send Prometheus Metrics
# ---------------------------------------------------------------------------
push_prometheus() {
  local result_file="$1"
  [[ -z "${PROMETHEUS_PUSHGATEWAY}" ]] && return 0

  if ! command -v curl &>/dev/null; then
    log_warn "curl not found; skipping Prometheus push"
    return 0
  fi

  local job="minervadb_sysbench"
  local instance="$(hostname -f 2>/dev/null || hostname)"
  local labels="profile="${PROFILE}",workload="${WORKLOAD}",host="${instance}""

  local tps qps p95 p99 slo_pass
  tps="$(jq -r '.results.tps' "$result_file")"
  qps="$(jq -r '.results.qps' "$result_file")"
  p95="$(jq -r '.results.latency_p95_ms' "$result_file")"
  p99="$(jq -r '.results.latency_p99_ms' "$result_file")"
  slo_pass="$(jq -r 'if .slo_status == "PASS" then 1 else 0 end' "$result_file")"

  local payload
  payload="# TYPE minervadb_sysbench_tps gauge
minervadb_sysbench_tps{${labels}} ${tps}
# TYPE minervadb_sysbench_qps gauge
minervadb_sysbench_qps{${labels}} ${qps}
# TYPE minervadb_sysbench_latency_p95_ms gauge
minervadb_sysbench_latency_p95_ms{${labels}} ${p95}
# TYPE minervadb_sysbench_latency_p99_ms gauge
minervadb_sysbench_latency_p99_ms{${labels}} ${p99}
# TYPE minervadb_sysbench_slo_pass gauge
minervadb_sysbench_slo_pass{${labels}} ${slo_pass}
# TYPE minervadb_sysbench_run_timestamp_unix gauge
minervadb_sysbench_run_timestamp_unix{${labels}} $(date +%s)
"

  echo "$payload" | curl -s --data-binary @- \
    "${PROMETHEUS_PUSHGATEWAY}/metrics/job/${job}/instance/${instance}" && \
    log_ok "Metrics pushed to Prometheus Pushgateway" || \
    log_warn "Failed to push metrics to Prometheus Pushgateway"
}

# ---------------------------------------------------------------------------
# Send Slack Alert on SLO Violation
# ---------------------------------------------------------------------------
send_slack_alert() {
  local result_file="$1" slo_status="$2"
  [[ -z "${SLACK_WEBHOOK_URL}" ]] && return 0
  [[ "$slo_status" == "PASS" ]] && return 0
  ! command -v curl &>/dev/null && { log_warn "curl not found; skipping Slack alert"; return 0; }

  local violations
  violations="$(jq -r '.slo_violations[] | "• (.metric): actual=(.actual) threshold=(.threshold)"' "$result_file" | head -10)"

  local payload
  payload="$(jq -n \
    --arg profile "$PROFILE" \
    --arg workload "$WORKLOAD" \
    --arg host "$(hostname -f 2>/dev/null || hostname)" \
    --arg violations "$violations" \
    --arg run_id "$RUN_ID" \
    '{
      username: "MinervaDB-Sysbench",
      icon_emoji: ":warning:",
      text: ":rotating_light: *SLO VIOLATION* — MinervaDB-Sysbench Benchmark",
      attachments: [{
        color: "danger",
        fields: [
          {title: "Profile",    value: $profile,    short: true},
          {title: "Workload",   value: $workload,   short: true},
          {title: "Host",       value: $host,       short: true},
          {title: "Run ID",     value: $run_id,     short: true},
          {title: "Violations", value: $violations, short: false}
        ]
      }]
    }')"

  curl -s -X POST -H 'Content-type: application/json' \
    --data "$payload" "$SLACK_WEBHOOK_URL" && \
    log_warn "Slack SLO violation alert sent" || \
    log_warn "Failed to send Slack alert"
}

# ---------------------------------------------------------------------------
# Print Results Summary
# ---------------------------------------------------------------------------
print_summary() {
  local tps="$1" qps="$2" lat_avg="$3" lat_p95="$4" lat_p99="$5"
  local lat_max="$6" err="$7" slo_status="$8"

  echo ""
  echo -e "${BOLD}========================================================"
  echo "  MinervaDB-Sysbench Enterprise — Benchmark Results"
  echo -e "========================================================${RESET}"
  echo "  Profile:          ${PROFILE}"
  echo "  Workload:         ${WORKLOAD}"
  echo "  Threads:          ${SB_THREADS}"
  echo "  Duration:         ${SB_TIME}s"
  echo "  Database:         ${DB_TYPE}://${DB_HOST}/${DB_NAME}"
  echo ""
  echo -e "${BOLD}  --- Performance Metrics ---${RESET}"
  echo "  TPS:              ${tps}"
  echo "  QPS:              ${qps}"
  echo "  Latency avg:      ${lat_avg} ms"
  echo "  Latency p95:      ${lat_p95} ms"
  echo "  Latency p99:      ${lat_p99} ms"
  echo "  Latency max:      ${lat_max} ms"
  echo "  Errors/sec:       ${err}"
  echo ""
  if [[ "$slo_status" == "PASS" ]]; then
    echo -e "${GREEN}${BOLD}  SLO Status:       PASS ✓${RESET}"
  else
    echo -e "${RED}${BOLD}  SLO Status:       FAIL ✗${RESET}"
    echo ""
    echo -e "${RED}  SLO Violations:${RESET}"
    echo "${VIOLATIONS_JSON}" | jq -r '.[] | "    • (.metric): actual=(.actual) threshold=(.threshold)"' 2>/dev/null || true
  fi
  echo -e "${BOLD}========================================================${RESET}"
  echo ""
}

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------
main() {
  log_info "MinervaDB-Sysbench Enterprise Orchestrator starting"
  log_info "Run ID: ${RUN_ID}"
  log_info "Command: ${COMMAND} | Profile: ${PROFILE} | Workload: ${WORKLOAD}"

  check_deps
  load_profile
  validate_config

  local sb_cmd
  sb_cmd="$(build_sysbench_cmd)"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN — sysbench command that would be executed:"
    # Mask password in dry-run output
    echo "${sb_cmd}" | sed "s/--mysql-password=[^ ]*/--mysql-password=*****/g" \
                       | sed "s/--pgsql-password=[^ ]*/--pgsql-password=*****/g"
    echo ""
    exit 0
  fi

  # Create results directory
  mkdir -p "${RESULTS_DIR}"

  # For non-run commands, execute directly
  if [[ "$COMMAND" != "run" ]]; then
    log_info "Executing sysbench ${COMMAND}..."
    eval "$sb_cmd" 2>&1 | tee "${RESULTS_DIR}/${RUN_ID}-${COMMAND}.log"
    log_ok "sysbench ${COMMAND} completed successfully"
    exit 0
  fi

  # Execute the benchmark and capture output
  log_info "Starting benchmark (threads=${SB_THREADS}, time=${SB_TIME}s)..."
  local output start_time end_time duration
  start_time="$(date +%s)"

  if ! output="$(eval "$sb_cmd" 2>&1 | tee "${RESULTS_DIR}/${RUN_ID}-raw.log")"; then
    log_error "sysbench exited with non-zero status"
    cat "${RESULTS_DIR}/${RUN_ID}-raw.log" >&2
    exit 1
  fi

  end_time="$(date +%s)"
  duration=$(( end_time - start_time ))

  log_ok "Benchmark completed in ${duration}s"

  # Parse results
  local parsed_results
  parsed_results="$(parse_results "$output")"
  IFS='|' read -r tps qps lat_avg lat_p95 lat_p99 lat_max err_rate reconnects <<< "$parsed_results"

  # Check SLOs
  VIOLATIONS_JSON="[]"
  local slo_status
  slo_status="$(check_slos "$tps" "$lat_p95" "$lat_p99" "$err_rate")"

  # Print summary
  print_summary "$tps" "$qps" "$lat_avg" "$lat_p95" "$lat_p99" "$lat_max" "$err_rate" "$slo_status"

  # Write JSON result
  local result_file
  result_file="$(write_json_result "$tps" "$qps" "$lat_avg" "$lat_p95" "$lat_p99" \
    "$lat_max" "$err_rate" "$reconnects" "$slo_status" "$duration")"

  # Push metrics and send alerts
  push_prometheus "$result_file"
  send_slack_alert "$result_file" "$slo_status"

  # Exit with SLO status
  if [[ "$slo_status" == "FAIL" ]]; then
    log_error "Benchmark FAILED SLO thresholds. Check results for details."
    exit 2
  fi

  log_ok "Benchmark PASSED all SLO thresholds."
  exit 0
}

# Trap for cleanup on unexpected exit
trap 'log_warn "Script interrupted or failed unexpectedly (exit code: $?)"' ERR

main "$@"
