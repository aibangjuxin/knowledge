#!/usr/bin/env bash
set -euo pipefail

# verify-timeout-chain.sh
# Purpose: collect timeout-chain evidence for
# Client -> A(L7) -> B(L4) -> C(GKE Gateway) -> D(Kong) -> E(Runtime)

URL="${URL:-https://dev-api.aliyun.cloud.aibang/api-proxy/v1/summary}"
HOST_HEADER="${HOST_HEADER:-dev-api.aliyun.cloud.aibang}"
METHOD="${METHOD:-POST}"
BODY='${BODY:-{"query":"test"}}'

KONG_NS="${KONG_NS:-kong-namespace}"
KONG_LABEL="${KONG_LABEL:-app=kong}"
GATEWAY_NS="${GATEWAY_NS:-gateway-namespace}"
GATEWAY_LABEL="${GATEWAY_LABEL:-app=gateway}"
RUNTIME_NS="${RUNTIME_NS:-your-namespace}"
RUNTIME_LABEL="${RUNTIME_LABEL:-app=your-app}"

LOOKBACK="${LOOKBACK:-30m}"
TIMEOUTS="${TIMEOUTS:-30 60 120 180 240 320}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"

REPORT_ROOT="${REPORT_ROOT:-/tmp}"
RUN_ID="timeout-chain-$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="${REPORT_ROOT}/${RUN_ID}"

mkdir -p "$REPORT_DIR"

echo "[INFO] report dir: $REPORT_DIR"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[WARN] command not found: $cmd"
    return 1
  fi
  return 0
}

run_safe() {
  local name="$1"
  shift
  local outfile="$REPORT_DIR/${name}.txt"
  echo "[INFO] collecting: $name"
  if "$@" >"$outfile" 2>&1; then
    echo "[OK] $name"
  else
    echo "[WARN] $name failed (see $outfile)"
  fi
}

write_meta() {
  cat > "$REPORT_DIR/meta.txt" <<META
run_id=$RUN_ID
date=$(date -Iseconds)
url=$URL
host_header=$HOST_HEADER
method=$METHOD
kong_ns=$KONG_NS
gateway_ns=$GATEWAY_NS
runtime_ns=$RUNTIME_NS
lookback=$LOOKBACK
timeouts=$TIMEOUTS
META
}

collect_k8s() {
  need_cmd kubectl || return 0

  run_safe k8s_gateway_list kubectl get gateway -A
  run_safe k8s_httproute_yaml kubectl get httproute -A -o yaml
  run_safe k8s_gcpbackendpolicy_yaml kubectl get gcpbackendpolicy -A -o yaml

  run_safe kong_pods kubectl -n "$KONG_NS" get pods -l "$KONG_LABEL" -o wide
  run_safe gateway_pods kubectl -n "$GATEWAY_NS" get pods -l "$GATEWAY_LABEL" -o wide
  run_safe runtime_pods kubectl -n "$RUNTIME_NS" get pods -l "$RUNTIME_LABEL" -o wide

  run_safe kong_logs kubectl -n "$KONG_NS" logs -l "$KONG_LABEL" --since="$LOOKBACK"
  run_safe gateway_logs kubectl -n "$GATEWAY_NS" logs -l "$GATEWAY_LABEL" --since="$LOOKBACK"
  run_safe runtime_logs kubectl -n "$RUNTIME_NS" logs -l "$RUNTIME_LABEL" --since="$LOOKBACK"

  run_safe kong_log_focus bash -lc "kubectl -n '$KONG_NS' logs -l '$KONG_LABEL' --since='$LOOKBACK' | egrep 'prematurely closed|upstream timed out|summary|request_id|timeout'"
  run_safe gateway_log_focus bash -lc "kubectl -n '$GATEWAY_NS' logs -l '$GATEWAY_LABEL' --since='$LOOKBACK' | egrep 'timeout|upstream|closed|summary|request_id'"
  run_safe runtime_log_focus bash -lc "kubectl -n '$RUNTIME_NS' logs -l '$RUNTIME_LABEL' --since='$LOOKBACK' | egrep 'summary|bigquery|timeout|request_id|error'"
}

collect_gcloud() {
  need_cmd gcloud || return 0

  run_safe gcloud_backend_services_kong \
    gcloud compute backend-services list --filter="name~kong"

  local bs
  bs=$(gcloud compute backend-services list --filter="name~kong" --format='value(name)' | head -n1 || true)
  if [[ -n "${bs}" ]]; then
    echo "$bs" > "$REPORT_DIR/backend_service_name.txt"
    run_safe gcloud_backend_service_timeout \
      gcloud compute backend-services describe "$bs" --global --format='table(name,timeoutSec,connectionDraining.drainingTimeoutSec)'
  else
    echo "[WARN] no backend service matched name~kong" | tee "$REPORT_DIR/gcloud_backend_service_timeout.txt"
  fi
}

run_curl_matrix() {
  need_cmd curl || return 0

  local summary="$REPORT_DIR/curl_summary.tsv"
  echo -e "timeout_s\thttp_code\ttime_total\tresult\trequest_id" > "$summary"

  for t in $TIMEOUTS; do
    local rid="timeout-debug-${t}-$(date +%s)"
    local body_file="$REPORT_DIR/curl_t${t}.body"
    local err_file="$REPORT_DIR/curl_t${t}.stderr"

    echo "[INFO] curl max-time=${t}s rid=${rid}"

    set +e
    local metrics
    metrics=$(curl -sS -o "$body_file" \
      -w '%{http_code}\t%{time_total}' \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$t" \
      -X "$METHOD" "$URL" \
      -H "Host: $HOST_HEADER" \
      -H 'Content-Type: application/json' \
      -H "X-Request-ID: $rid" \
      -d "$BODY" 2>"$err_file")
    local rc=$?
    set -e

    local code time_total
    code=$(echo "$metrics" | awk -F'\t' '{print $1}')
    time_total=$(echo "$metrics" | awk -F'\t' '{print $2}')

    local result
    if [[ $rc -eq 0 ]]; then
      result="ok"
    else
      result="curl_exit_${rc}"
    fi

    echo -e "${t}\t${code:-000}\t${time_total:-0}\t${result}\t${rid}" >> "$summary"
  done
}

derive_hints() {
  local out="$REPORT_DIR/hints.txt"
  {
    echo "=== Quick Hints ==="

    if [[ -f "$REPORT_DIR/curl_summary.tsv" ]]; then
      echo ""
      echo "[curl summary]"
      cat "$REPORT_DIR/curl_summary.tsv"

      local first_fail
      first_fail=$(awk -F'\t' 'NR>1 && ($4 != "ok" || $2 !~ /^2/) {print $1; exit}' "$REPORT_DIR/curl_summary.tsv" || true)
      if [[ -n "$first_fail" ]]; then
        echo ""
        echo "first_fail_timeout_s=$first_fail"
        if [[ "$first_fail" -le 60 ]]; then
          echo "hint: fail happens early (<=60s), prioritize client defaults / gateway / front-chain behavior."
        elif [[ "$first_fail" -le 180 ]]; then
          echo "hint: fail before expected 300s budget, prioritize cascade-close timeline correlation."
        else
          echo "hint: fail near upper budget, inspect upstream runtime and queueing under load."
        fi
      fi
    fi

    if [[ -f "$REPORT_DIR/gcloud_backend_service_timeout.txt" ]]; then
      local tsec
      tsec=$(awk 'NR>1 && NF>=2 {print $2; exit}' "$REPORT_DIR/gcloud_backend_service_timeout.txt" || true)
      if [[ -n "$tsec" ]]; then
        echo ""
        echo "backend_service_timeoutSec=$tsec"
        echo "note: treat timeoutSec as required check, not sole root-cause proof."
      fi
    fi

    echo ""
    echo "next: align A/B/C/D/E logs by request_id from curl_summary.tsv"
  } > "$out"
}

write_meta
collect_k8s
collect_gcloud
run_curl_matrix
derive_hints

echo "[DONE] Evidence generated at: $REPORT_DIR"
echo "[DONE] Start with: $REPORT_DIR/hints.txt"
