#!/usr/bin/env bash
# =============================================================================
# MinervaDB-Sysbench Enterprise — Graduated Load / Ramp-Up Test
# =============================================================================
#          counts to find the database saturation point and generate a
#          concurrency vs. throughput curve.
#
# Usage:
#   ./enterprise/scripts/ramp_test.sh [OPTIONS]
#
# Options:
#   --profile   <name>     Environment profile (default: dev)
#   --workload  <name>     sysbench workload (default: oltp_read_write)
#   --steps     <list>     Comma-separated thread counts (default: 1,2,4,8,16,32,64)
#   --duration  <secs>     Duration per step in seconds (default: 60)
#   --warmup    <secs>     Warmup per step in seconds (default: 10)
#   --output    <path>     Write summary CSV to this file
#   --help                 Show this help
#
# Output:
#   - Individual JSON result per step in RESULTS_DIR
#   - Summary CSV with threads,tps,qps,p95_ms,p99_ms columns
#   - Console table with concurrency curve
#
# Exit Codes:
#   0  All steps completed
#   1  Configuration or dependency error
#   2  One or more steps failed
#
# Example:
#   DB_PASSWORD=secret ./enterprise/scripts/ramp_test.sh \
#     --profile staging \
#     --workload oltp_read_write \
#     --steps 1,2,4,8,16,32,64,128 \
#     --duration 120 \
#     --output /tmp/ramp_results.csv
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly ENTERPRISE_DIR="${REPO_ROOT}/enterprise"
readonly TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"

# Color output
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'; CYAN='\033[0;36m'
else
  RED=''; YELLOW=''; GREEN=''; BLUE=''; BOLD=''; RESET=''; CYAN=''
fi

log_info()  { echo -e "${BLUE}[RAMP][${TIMESTAMP}][INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[RAMP][${TIMESTAMP}][WARN]${RESET}  $*" >&2; }
log_error() { echo -e "${RED}[RAMP][${TIMESTAMP}][ERROR]${RESET} $*" >&2; }
log_ok()    { echo -e "${GREEN}[RAMP][${TIMESTAMP}][OK]${RESET}    $*"; }
log_step()  { echo -e "${CYAN}${BOLD}[RAMP] === STEP: $* ===${RESET}"; }

usage() {
  grep '^#' "${BASH_SOURCE[0]}" | grep -v '#!/' | sed 's/^# \{0,1\}//' | head -40
  exit 0
}

# ---------------------------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------------------------
PROFILE="dev"
WORKLOAD="oltp_read_write"
STEPS="1,2,4,8,16,32,64"
STEP_DURATION="60"
STEP_WARMUP="10"
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)  PROFILE="$2";       shift 2 ;;
    --workload) WORKLOAD="$2";      shift 2 ;;
    --steps)    STEPS="$2";         shift 2 ;;
    --duration) STEP_DURATION="$2"; shift 2 ;;
    --warmup)   STEP_WARMUP="$2";   shift 2 ;;
    --output)   OUTPUT_FILE="$2";   shift 2 ;;
    --help|-h)  usage ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Pre-flight Checks
# ---------------------------------------------------------------------------
check_deps() {
  for cmd in sysbench jq bc column; do
    command -v "$cmd" &>/dev/null || {
      log_error "Missing dependency: $cmd"
      exit 1
    }
  done

  if [[ ! -f "${ENTERPRISE_DIR}/scripts/run_benchmark.sh" ]]; then
    log_error "run_benchmark.sh not found. Run from repository root."
    exit 1
  fi
  chmod +x "${ENTERPRISE_DIR}/scripts/run_benchmark.sh"
}

# ---------------------------------------------------------------------------
# Run a Single Step
# ---------------------------------------------------------------------------
run_step() {
  local threads="$1"
  log_step "Threads: ${threads} | Duration: ${STEP_DURATION}s | Warmup: ${STEP_WARMUP}s"

  local step_result
  set +e
  step_result="$("${ENTERPRISE_DIR}/scripts/run_benchmark.sh" \
    --profile "${PROFILE}" \
    --workload "${WORKLOAD}" \
    --threads "${threads}" \
    --time "${STEP_DURATION}" \
    --command run 2>&1)"
  local exit_code=$?
  set -e

  if [[ $exit_code -gt 2 ]]; then
    log_error "Step with ${threads} threads failed (exit: ${exit_code})"
    return 1
  fi

  # Find the most recently written result file for this step
  local result_file
  result_file="$(ls -t "${ENTERPRISE_DIR}/results/"*.json 2>/dev/null | head -1 || true)"

  if [[ -z "$result_file" ]]; then
    log_warn "No result file found for ${threads}-thread step"
    echo "${threads}|0|0|0|0|0"
    return 0
  fi

  local tps qps p95 p99 avg
  tps="$(jq -r '.results.tps // 0' "$result_file")"
  qps="$(jq -r '.results.qps // 0' "$result_file")"
  p95="$(jq -r '.results.latency_p95_ms // 0' "$result_file")"
  p99="$(jq -r '.results.latency_p99_ms // 0' "$result_file")"
  avg="$(jq -r '.results.latency_avg_ms // 0' "$result_file")"

  echo "${threads}|${tps}|${qps}|${avg}|${p95}|${p99}"
}

# ---------------------------------------------------------------------------
# Print ASCII Concurrency Curve
# ---------------------------------------------------------------------------
print_curve() {
  local -n _results=$1
  local max_tps=0

  # Find max TPS for scaling
  for row in "${_results[@]}"; do
    local tps
    tps="$(echo "$row" | cut -d'|' -f2)"
    if (( $(echo "$tps > $max_tps" | bc -l) )); then
      max_tps="$tps"
    fi
  done

  echo ""
  echo -e "${BOLD}${CYAN}  Concurrency vs. Throughput (TPS) Curve${RESET}"
  echo "  Workload: ${WORKLOAD} | Profile: ${PROFILE}"
  echo ""

  local bar_width=40
  for row in "${_results[@]}"; do
    local threads tps
    threads="$(echo "$row" | cut -d'|' -f1)"
    tps="$(echo "$row" | cut -d'|' -f2)"

    local bar_len=0
    if (( $(echo "$max_tps > 0" | bc -l) )); then
      bar_len=$(echo "scale=0; $tps * $bar_width / $max_tps" | bc)
    fi

    local bar
    bar="$(printf '%*s' "$bar_len" '' | tr ' ' '=')"
    printf "  %4s threads: ${GREEN}%-40s${RESET} %.0f TPS\n" "$threads" "$bar" "$tps"
  done
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log_info "MinervaDB-Sysbench Ramp Test starting"
  log_info "Profile: ${PROFILE} | Workload: ${WORKLOAD}"
  log_info "Steps: ${STEPS} | Duration: ${STEP_DURATION}s per step"

  check_deps

  # Prepare benchmark tables once before the ramp
  log_info "Preparing benchmark tables..."
  "${ENTERPRISE_DIR}/scripts/run_benchmark.sh" \
    --profile "${PROFILE}" \
    --workload "${WORKLOAD}" \
    --command prepare || {
    log_error "Failed to prepare tables. Check database connectivity."
    exit 1
  }

  # Initialize CSV output
  local csv_file="${OUTPUT_FILE:-${ENTERPRISE_DIR}/results/ramp-${TIMESTAMP}-${PROFILE}-${WORKLOAD//\//_}.csv}"
  mkdir -p "$(dirname "$csv_file")"
  echo "threads,tps,qps,latency_avg_ms,latency_p95_ms,latency_p99_ms" > "$csv_file"
  log_info "Writing CSV summary to: ${csv_file}"

  # Run each step
  local -a results=()
  local failed_steps=0

  IFS=',' read -ra THREAD_STEPS <<< "$STEPS"
  for threads in "${THREAD_STEPS[@]}"; do
    threads="${threads// /}"  # strip whitespace
    local result
    if result="$(run_step "$threads")"; then
      results+=("$result")
      echo "${result//|/,}" >> "$csv_file"
      log_ok "Step complete: ${threads} threads — TPS: $(echo "$result" | cut -d'|' -f2)"
    else
      log_warn "Step failed for ${threads} threads, continuing..."
      (( failed_steps++ )) || true
    fi
    # Small pause between steps to allow DB to stabilize
    sleep 2
  done

  # Cleanup tables
  log_info "Cleaning up benchmark tables..."
  "${ENTERPRISE_DIR}/scripts/run_benchmark.sh" \
    --profile "${PROFILE}" \
    --workload "${WORKLOAD}" \
    --command cleanup || log_warn "Cleanup failed (non-fatal)"

  # Print summary table
  echo ""
  echo -e "${BOLD}Ramp Test Summary${RESET}"
  echo ""
  printf "%-10s %-12s %-12s %-12s %-12s %-12s\n" \
    "Threads" "TPS" "QPS" "Avg (ms)" "P95 (ms)" "P99 (ms)"
  printf "%-10s %-12s %-12s %-12s %-12s %-12s\n" \
    "-------" "---" "---" "--------" "--------" "--------"
  for row in "${results[@]}"; do
    IFS='|' read -r th tps qps avg p95 p99 <<< "$row"
    printf "%-10s %-12s %-12s %-12s %-12s %-12s\n" \
      "$th" "$tps" "$qps" "$avg" "$p95" "$p99"
  done

  # Print ASCII curve
  print_curve results

  log_ok "CSV results: ${csv_file}"
  log_info "Individual JSON results: ${ENTERPRISE_DIR}/results/"

  if [[ $failed_steps -gt 0 ]]; then
    log_warn "${failed_steps} step(s) failed. Review individual result files."
    exit 2
  fi

  log_ok "Ramp test completed successfully."
}

main "$@"
