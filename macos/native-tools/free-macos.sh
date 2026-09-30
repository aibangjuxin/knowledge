#!/usr/bin/env bash
set -euo pipefail

TOP_N=10
SORT_BY="memory"
PAGE_SIZE=4096

usage() {
  cat <<'EOF'
Usage: free-macos.sh [TOP_N] [memory|cpu|combined]
       free-macos.sh [--top N] [--sort memory|cpu|combined]

Sort modes:
  memory    RSS descending; CPU is the tie-breaker (default)
  cpu       CPU descending; RSS is the tie-breaker
  combined  60% memory pressure + 40% CPU pressure

Examples:
  free-macos.sh                    # top 10 by RSS
  free-macos.sh 20 cpu             # top 20 by CPU
  free-macos.sh --sort combined    # balanced resource-heavy processes
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--top)
      [ "$#" -ge 2 ] || { echo "ERROR: $1 requires a value." >&2; exit 2; }
      TOP_N="$2"
      shift 2
      ;;
    -s|--sort)
      [ "$#" -ge 2 ] || { echo "ERROR: $1 requires a value." >&2; exit 2; }
      SORT_BY="$2"
      shift 2
      ;;
    --sort=*)
      SORT_BY="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    memory|cpu|combined)
      SORT_BY="$1"
      shift
      ;;
    ''|*[!0-9]*)
      echo "ERROR: unknown argument '$1'." >&2
      usage >&2
      exit 2
      ;;
    *)
      TOP_N="$1"
      shift
      ;;
  esac
done

case "$SORT_BY" in
  memory|cpu|combined) ;;
  *)
    echo "ERROR: invalid sort mode '$SORT_BY'. Use memory, cpu, or combined." >&2
    exit 2
    ;;
esac

if [ "$TOP_N" -lt 1 ]; then
  echo "ERROR: TOP_N must be at least 1." >&2
  exit 2
fi

echo "=============================================="
echo " macOS Memory Summary (Linux free -m style)"
echo "=============================================="

# ---------- 系统内存 ----------
TOTAL_MEM_BYTES=$(sysctl -n hw.memsize)
TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))

VM_STAT=$(vm_stat)

PAGES_FREE=$(echo "$VM_STAT" | awk '/Pages free/ {print $3}' | tr -d '.')
PAGES_ACTIVE=$(echo "$VM_STAT" | awk '/Pages active/ {print $3}' | tr -d '.')
PAGES_INACTIVE=$(echo "$VM_STAT" | awk '/Pages inactive/ {print $3}' | tr -d '.')
PAGES_SPECULATIVE=$(echo "$VM_STAT" | awk '/Pages speculative/ {print $3}' | tr -d '.')
PAGES_WIRED=$(echo "$VM_STAT" | awk '/Pages wired down/ {print $4}' | tr -d '.')

FREE_MB=$((PAGES_FREE * PAGE_SIZE / 1024 / 1024))
SPEC_MB=$((PAGES_SPECULATIVE * PAGE_SIZE / 1024 / 1024))
AVAILABLE_MB=$(((PAGES_FREE + PAGES_SPECULATIVE) * PAGE_SIZE / 1024 / 1024))
USED_MB=$((TOTAL_MEM_MB - AVAILABLE_MB))

printf "%-12s %8s MB\n" "Total:" "$TOTAL_MEM_MB"
printf "%-12s %8s MB\n" "Used:" "$USED_MB"
printf "%-12s %8s MB\n" "Free:" "$FREE_MB"
printf "%-12s %8s MB\n" "Available:" "$AVAILABLE_MB"

echo
echo "Breakdown:"
printf "  %-14s %8s MB\n" "Active:" $((PAGES_ACTIVE * PAGE_SIZE / 1024 / 1024))
printf "  %-14s %8s MB\n" "Inactive:" $((PAGES_INACTIVE * PAGE_SIZE / 1024 / 1024))
printf "  %-14s %8s MB\n" "Wired:" $((PAGES_WIRED * PAGE_SIZE / 1024 / 1024))
printf "  %-14s %8s MB\n" "Speculative:" "$SPEC_MB"

# ---------- Swap ----------
echo
echo "Swap:"
sysctl vm.swapusage | sed 's/.*total = \(.*\)M.*used = \(.*\)M.*/  Total: \1 MB\n  Used:  \2 MB/'

# ---------- Top Processes ----------
echo
echo "=============================================="
case "$SORT_BY" in
  memory) TITLE="Top ${TOP_N} Memory Consumers (RSS)" ;;
  cpu) TITLE="Top ${TOP_N} CPU Consumers" ;;
  combined) TITLE="Top ${TOP_N} Combined Resource Consumers (60% MEM / 40% CPU)" ;;
esac
echo " ${TITLE}"
echo "=============================================="
printf "%-6s %-8s %-10s %-9s %s\n" "PID" "RSS(MB)" "CPU(%)" "SCORE" "COMMAND"

# Keep sorting fields separate from presentation. `pcpu` is the recent CPU
# percentage reported by ps; the combined score normalises both dimensions to
# this machine's capacity before applying the 60/40 weighting.
CPU_COUNT=$(sysctl -n hw.ncpu)
ps -axo pid=,rss=,pcpu=,command= |
  awk -v total_mem_mb="$TOTAL_MEM_MB" -v cpu_count="$CPU_COUNT" '
    {
      pid = $1
      rss_mb = $2 / 1024
      cpu = $3
      $1 = $2 = $3 = ""
      sub(/^[[:space:]]+/, "")
      command = $0
      mem_pressure = (rss_mb / total_mem_mb) * 100
      cpu_pressure = cpu_count > 0 ? cpu / cpu_count : cpu
      score = (0.60 * mem_pressure) + (0.40 * cpu_pressure)
      # machine-readable fields: RSS, CPU, score, PID, then original command
      printf "%.3f\t%.3f\t%.3f\t%s\t%s\n", rss_mb, cpu, score, pid, command
    }
  ' |
  {
    case "$SORT_BY" in
      memory) sort -t $'\t' -k1,1nr -k2,2nr -k4,4n ;;
      cpu) sort -t $'\t' -k2,2nr -k1,1nr -k4,4n ;;
      combined) sort -t $'\t' -k3,3nr -k1,1nr -k2,2nr -k4,4n ;;
    esac
  } |
  # Do not use `head` here: with pipefail it can make an upstream `sort`
  # report SIGPIPE and incorrectly fail an otherwise successful script.
  awk -F '\t' -v limit="$TOP_N" 'NR <= limit {
    printf "%-6s %-8.0f %-10.1f %-9.2f %s\n", $4, $1, $2, $3, $5
  }'
