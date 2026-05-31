#!/usr/bin/env bash
# K8s Gateway FQDN Resource Explorer and E2E URL Builder
# Usage:
#   ./k8s-gateway-fqdn-chatgpt.sh <fqdn> [namespace] [--validate]
#
# Given a public FQDN, this script traces the Gateway API chain:
#   HTTPRoute -> Gateway listener -> DestinationRule -> Service -> Deployment
# and prints complete client-facing URLs that can be used for E2E tests.

set -euo pipefail

FQDN="${1:-}"
TENANT_NS="${2:-}"
VALIDATE="${3:-}"

if [[ "${TENANT_NS:-}" == "--validate" ]]; then
  VALIDATE="--validate"
  TENANT_NS=""
fi

GATEWAY_NS_DEFAULT="${GATEWAY_NS:-infrastructure}"
GATEWAY_NAME_DEFAULT="${GATEWAY_NAME:-central-gateway}"
DEFAULT_SCHEME="${DEFAULT_SCHEME:-https}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; }
section() { echo ""; echo -e "${BOLD}# $*${NC}"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <fqdn> [namespace] [--validate]

Examples:
  $(basename "$0") api.team-a.example.com
  $(basename "$0") api.team-a.example.com team-a
  $(basename "$0") api.team-a.example.com team-a --validate

Environment overrides:
  GATEWAY_NS       Default gateway namespace fallback. Current: ${GATEWAY_NS_DEFAULT}
  GATEWAY_NAME     Default gateway name fallback. Current: ${GATEWAY_NAME_DEFAULT}
  DEFAULT_SCHEME   URL scheme when listener protocol cannot be detected. Current: ${DEFAULT_SCHEME}
EOF
  exit 1
}

[[ -z "$FQDN" ]] && usage

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1"
    exit 1
  fi
}

need_cmd kubectl
need_cmd jq

kubectl_json() {
  kubectl "$@" -o json 2>/dev/null || true
}

normalize_path() {
  local p="${1:-/}"
  [[ -z "$p" ]] && p="/"
  [[ "$p" != /* ]] && p="/$p"
  printf '%s' "$p" | sed -E 's#/+#/#g'
}

join_prefix_probe() {
  local match_type="$1"
  local route_path
  local probe_path
  route_path="$(normalize_path "$2")"
  probe_path="$(normalize_path "$3")"

  case "$match_type" in
    Exact)
      printf '%s' "$route_path"
      ;;
    PathPrefix|"")
      if [[ "$route_path" == "/" ]]; then
        printf '%s' "$probe_path"
      elif [[ "$probe_path" == "$route_path" || "$probe_path" == "$route_path/"* ]]; then
        printf '%s' "$probe_path"
      else
        printf '%s/%s' "${route_path%/}" "${probe_path#/}" | sed -E 's#/+#/#g'
      fi
      ;;
    *)
      printf '%s' "$route_path"
      ;;
  esac
}

unique_lines() {
  awk 'NF && !seen[$0]++'
}

url_authority() {
  local scheme="$1"
  local port="$2"
  if [[ "$scheme" == "https" && "$port" == "443" ]] || [[ "$scheme" == "http" && "$port" == "80" ]] || [[ -z "$port" ]]; then
    printf '%s' "$FQDN"
  else
    printf '%s:%s' "$FQDN" "$port"
  fi
}

print_banner() {
  echo ""
  echo "============================================================"
  echo "  K8s Gateway FQDN Explorer"
  echo "  FQDN      : $FQDN"
  echo "  Namespace : ${TENANT_NS:-auto}"
  echo "============================================================"
}

print_banner

section "Discover HTTPRoute"

if [[ -n "$TENANT_NS" ]]; then
  ROUTES_JSON="$(kubectl_json get httproute -n "$TENANT_NS")"
else
  ROUTES_JSON="$(kubectl_json get httproute -A)"
fi

if [[ -z "$ROUTES_JSON" ]]; then
  fail "Could not read HTTPRoute resources${TENANT_NS:+ in namespace $TENANT_NS}."
  exit 1
fi

if [[ "$(jq '.items // [] | length' <<<"$ROUTES_JSON")" == "0" ]]; then
  fail "No HTTPRoute resources found${TENANT_NS:+ in namespace $TENANT_NS}."
  exit 1
fi

MATCHED_ROUTES="$(jq -r --arg fqdn "${FQDN%.}" '
  def norm: rtrimstr(".");
  def host_match($fqdn; $host):
    ($host | norm) as $h |
    if $h == $fqdn then true
    elif ($h | startswith("*.")) then
      ($h | ltrimstr("*.")) as $suffix |
      (($fqdn | endswith("." + $suffix)) and (($fqdn | split(".") | length) == ($h | split(".") | length)))
    else false
    end;

  .items[]
  | select(any(.spec.hostnames[]?; host_match($fqdn; .)))
  | [.metadata.namespace, .metadata.name, ((.spec.hostnames // []) | join(","))]
  | @tsv
' <<<"$ROUTES_JSON")"

if [[ -z "$MATCHED_ROUTES" ]]; then
  warn "No direct HTTPRoute spec.hostnames match for $FQDN. Listing known hostnames for quick check:"
  jq -r '.items[] | [.metadata.namespace, .metadata.name, ((.spec.hostnames // ["<empty>"]) | join(","))] | @tsv' <<<"$ROUTES_JSON" |
    sed 's/^/  /'
  exit 1
fi

ROUTE_COUNT="$(wc -l <<<"$MATCHED_ROUTES" | tr -d ' ')"
ok "Matched HTTPRoute count: $ROUTE_COUNT"
printf '%s\n' "$MATCHED_ROUTES" | awk -F'\t' '{printf "  - %s/%s hostnames=%s\n", $1, $2, $3}'

declare -a GENERATED_URLS=()
declare -a CURL_COMMANDS=()
declare -a VALIDATION_TARGETS=()

while IFS=$'\t' read -r ROUTE_NS ROUTE_NAME ROUTE_HOSTNAMES; do
  [[ -z "$ROUTE_NS" || -z "$ROUTE_NAME" ]] && continue

  section "HTTPRoute: ${ROUTE_NS}/${ROUTE_NAME}"
  ROUTE_JSON="$(kubectl_json get httproute "$ROUTE_NAME" -n "$ROUTE_NS")"
  if [[ -z "$ROUTE_JSON" ]]; then
    warn "Cannot read HTTPRoute ${ROUTE_NS}/${ROUTE_NAME}; skipping."
    continue
  fi

  echo "Hostnames:"
  jq -r '.spec.hostnames[]? // empty' <<<"$ROUTE_JSON" | sed 's/^/  - /'

  echo ""
  echo "ParentRefs and listener context:"
  PARENTS="$(jq -c '.spec.parentRefs[]? // empty' <<<"$ROUTE_JSON")"
  if [[ -z "$PARENTS" ]]; then
    warn "HTTPRoute has no spec.parentRefs."
  fi

  GATEWAY_IP=""
  URL_SCHEME="$DEFAULT_SCHEME"
  URL_PORT="443"

  while IFS= read -r parent; do
    [[ -z "$parent" ]] && continue
    P_KIND="$(jq -r '.kind // "Gateway"' <<<"$parent")"
    P_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$parent")"
    P_NAME="$(jq -r '.name' <<<"$parent")"
    P_SECTION="$(jq -r '.sectionName // ""' <<<"$parent")"

    printf '  - %s %s/%s' "$P_KIND" "$P_NS" "$P_NAME"
    [[ -n "$P_SECTION" ]] && printf ' sectionName=%s' "$P_SECTION"
    echo ""

    if [[ "$P_KIND" == "Gateway" ]]; then
      GW_JSON="$(kubectl_json get gateway "$P_NAME" -n "$P_NS")"
      if [[ -z "$GW_JSON" ]]; then
        warn "    Gateway not readable: ${P_NS}/${P_NAME}"
        continue
      fi

      THIS_IP="$(jq -r '.status.addresses[0].value // empty' <<<"$GW_JSON")"
      [[ -z "$GATEWAY_IP" && -n "$THIS_IP" ]] && GATEWAY_IP="$THIS_IP"

      jq -r --arg section "$P_SECTION" '
        .spec.listeners[]
        | select($section == "" or .name == $section)
        | "    listener=" + .name
          + " protocol=" + (.protocol // "<none>")
          + " port=" + ((.port // "") | tostring)
          + " hostname=" + (.hostname // "<all>")
      ' <<<"$GW_JSON"

      LISTENER_HINT="$(jq -r --arg section "$P_SECTION" '
        [.spec.listeners[]
         | select($section == "" or .name == $section)
         | {protocol: (.protocol // ""), port: (.port // 0)}][0]
        | if . == null then "" else [.protocol, (.port | tostring)] | @tsv end
      ' <<<"$GW_JSON")"
      if [[ -n "$LISTENER_HINT" ]]; then
        L_PROTOCOL="$(cut -f1 <<<"$LISTENER_HINT")"
        L_PORT="$(cut -f2 <<<"$LISTENER_HINT")"
        case "$L_PROTOCOL" in
          HTTPS|TLS) URL_SCHEME="https" ;;
          HTTP) URL_SCHEME="http" ;;
        esac
        [[ "$L_PORT" != "0" && -n "$L_PORT" ]] && URL_PORT="$L_PORT"
      fi
    elif [[ "$P_KIND" == "ListenerSet" ]]; then
      LS_JSON="$(kubectl_json get listenerset "$P_NAME" -n "$P_NS")"
      if [[ -z "$LS_JSON" ]]; then
        warn "    ListenerSet not readable: ${P_NS}/${P_NAME}"
        continue
      fi
      jq -r --arg section "$P_SECTION" '
        .spec.listeners[]
        | select($section == "" or .name == $section)
        | "    listener=" + .name
          + " protocol=" + (.protocol // "<none>")
          + " port=" + ((.port // "") | tostring)
          + " hostname=" + (.hostname // "<all>")
      ' <<<"$LS_JSON"
    fi
  done <<<"$PARENTS"

  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kubectl get svc -n "$GATEWAY_NS_DEFAULT" -o json 2>/dev/null |
      jq -r '.items[] | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // empty' |
      head -n 1 || true)"
  fi
  if [[ -z "$GATEWAY_IP" ]]; then
    GATEWAY_IP="$(kubectl get gateway "$GATEWAY_NAME_DEFAULT" -n "$GATEWAY_NS_DEFAULT" -o json 2>/dev/null |
      jq -r '.status.addresses[0].value // empty' || true)"
  fi

  echo ""
  echo "Route status parents:"
  jq -r '
    .status.parents[]?
    | "  - " + (.parentRef.namespace // "<same-ns>") + "/" + .parentRef.name
      + "/" + (.parentRef.sectionName // "<all>")
      + " " + ([.conditions[]? | .type + "=" + .status] | join(","))
  ' <<<"$ROUTE_JSON"

  section "Rules, Backends, DestinationRules, Services, Deployments"
  RULES_COUNT="$(jq '.spec.rules | length' <<<"$ROUTE_JSON")"
  if [[ "$RULES_COUNT" == "0" ]]; then
    warn "HTTPRoute has no rules."
    continue
  fi

  for ((rule_idx=0; rule_idx<RULES_COUNT; rule_idx++)); do
    RULE_JSON="$(jq -c ".spec.rules[$rule_idx]" <<<"$ROUTE_JSON")"
    RULE_NAME="$(jq -r '.name // ""' <<<"$RULE_JSON")"
    echo ""
    echo -e "${BOLD}Rule[$rule_idx]${NC}${RULE_NAME:+ name=$RULE_NAME}"

    MATCH_LINES="$(jq -r '
      if ((.matches // []) | length) == 0 then
        "PathPrefix\t/\t<none>"
      else
        .matches[]
        | [(.path.type // "PathPrefix"), (.path.value // "/"), ((.headers // []) | map(.name + "=" + .value) | join(","))]
        | @tsv
      end
    ' <<<"$RULE_JSON")"

    echo "  Matches:"
    printf '%s\n' "$MATCH_LINES" | awk -F'\t' '{printf "    - %s %s headers=%s\n", $1, $2, ($3=="" ? "<none>" : $3)}'

    REQUEST_TIMEOUT="$(jq -r '.timeouts.request // empty' <<<"$RULE_JSON")"
    BACKEND_TIMEOUT="$(jq -r '.timeouts.backendRequest // .timeouts.backendTimeout // empty' <<<"$RULE_JSON")"
    [[ -n "$REQUEST_TIMEOUT$BACKEND_TIMEOUT" ]] &&
      echo "  Timeouts: request=${REQUEST_TIMEOUT:-<none>} backend=${BACKEND_TIMEOUT:-<none>}"

    BACKENDS="$(jq -c '.backendRefs[]? // empty' <<<"$RULE_JSON")"
    if [[ -z "$BACKENDS" ]]; then
      warn "  Rule[$rule_idx] has no backendRefs."
      continue
    fi

    while IFS= read -r backend; do
      [[ -z "$backend" ]] && continue
      B_KIND="$(jq -r '.kind // "Service"' <<<"$backend")"
      B_NAME="$(jq -r '.name' <<<"$backend")"
      B_NS="$(jq -r --arg ns "$ROUTE_NS" '.namespace // $ns' <<<"$backend")"
      B_PORT="$(jq -r '.port // ""' <<<"$backend")"
      B_WEIGHT="$(jq -r '.weight // 1' <<<"$backend")"

      echo ""
      echo "  BackendRef: ${B_KIND} ${B_NS}/${B_NAME}:${B_PORT} weight=${B_WEIGHT}"
      if [[ "$B_KIND" != "Service" ]]; then
        warn "    Backend kind is not Service; downstream Service/Deployment tracing skipped."
        continue
      fi

      DR_JSON="$(kubectl_json get destinationrule -n "$B_NS")"
      MATCHED_DR="$(jq -r --arg svc "$B_NAME" --arg ns "$B_NS" '
        .items[]?
        | select(
            .spec.host == $svc
            or .spec.host == ($svc + "." + $ns)
            or .spec.host == ($svc + "." + $ns + ".svc")
            or .spec.host == ($svc + "." + $ns + ".svc.cluster.local")
            or (.spec.host | contains($svc))
          )
        | [
            .metadata.name,
            .spec.host,
            (.spec.trafficPolicy.connectionPool.tcp.connectTimeout // ""),
            (.spec.trafficPolicy.connectionPool.http.idleTimeout // ""),
            (.spec.trafficPolicy.loadBalancer.simple // (.spec.trafficPolicy.loadBalancer.consistentHash | tojson?) // "")
          ]
        | @tsv
      ' <<<"${DR_JSON:-{\"items\":[]}}" | head -n 1)"
      if [[ -n "$MATCHED_DR" ]]; then
        IFS=$'\t' read -r DR_NAME DR_HOST DR_CONNECT_TIMEOUT DR_IDLE_TIMEOUT DR_LB <<<"$MATCHED_DR"
        echo "    DestinationRule: ${B_NS}/${DR_NAME} host=${DR_HOST}"
        echo "      connectTimeout=${DR_CONNECT_TIMEOUT:-<default>} idleTimeout=${DR_IDLE_TIMEOUT:-<default>} lb=${DR_LB:-<default>}"
      else
        echo "    DestinationRule: <none>"
      fi

      SVC_JSON="$(kubectl_json get svc "$B_NAME" -n "$B_NS")"
      if [[ -z "$SVC_JSON" ]]; then
        warn "    Service not found: ${B_NS}/${B_NAME}"
        continue
      fi

      SVC_TYPE="$(jq -r '.spec.type // "ClusterIP"' <<<"$SVC_JSON")"
      SVC_CLUSTER_IP="$(jq -r '.spec.clusterIP // "<none>"' <<<"$SVC_JSON")"
      SVC_SELECTOR="$(jq -r '.spec.selector // {} | to_entries | map(.key + "=" + .value) | join(",")' <<<"$SVC_JSON")"
      SVC_PORT_INFO="$(jq -r --argjson port "${B_PORT:-0}" '
        (.spec.ports[] | select((.port // 0) == $port)) // .spec.ports[0]
        | "port=" + ((.port // "") | tostring)
          + " targetPort=" + ((.targetPort // "") | tostring)
          + " protocol=" + (.protocol // "TCP")
          + " appProtocol=" + (.appProtocol // "<none>")
      ' <<<"$SVC_JSON")"
      echo "    Service: type=${SVC_TYPE} clusterIP=${SVC_CLUSTER_IP}"
      echo "      selector=${SVC_SELECTOR:-<none>}"
      echo "      ${SVC_PORT_INFO}"

      DEPLOY_NAME=""
      if [[ -n "$SVC_SELECTOR" ]]; then
        POD_JSON="$(kubectl_json get pods -n "$B_NS" -l "$SVC_SELECTOR")"
        RS_NAME="$(jq -r '.items[0].metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .name' <<<"${POD_JSON:-{\"items\":[]}}" | head -n 1)"
        if [[ -n "$RS_NAME" ]]; then
          DEPLOY_NAME="$(kubectl get rs "$RS_NAME" -n "$B_NS" -o json 2>/dev/null |
            jq -r '.metadata.ownerReferences[]? | select(.kind == "Deployment") | .name' | head -n 1 || true)"
        fi
        if [[ -z "$DEPLOY_NAME" ]]; then
          DEPLOY_NAME="$(kubectl get deploy -n "$B_NS" -o json 2>/dev/null |
            jq -r --argjson sel "$(jq -c '.spec.selector // {}' <<<"$SVC_JSON")" '
              .items[]
              | select(
                  ($sel | to_entries) as $s
                  | all($s[]; .spec.selector.matchLabels[.key] == .value)
                )
              | .metadata.name
            ' | head -n 1 || true)"
        fi
      fi
      [[ -z "$DEPLOY_NAME" ]] && DEPLOY_NAME="$B_NAME"

      DEPLOY_JSON="$(kubectl_json get deploy "$DEPLOY_NAME" -n "$B_NS")"
      if [[ -z "$DEPLOY_JSON" ]]; then
        warn "    Deployment not found by selector/name: ${B_NS}/${DEPLOY_NAME}"
        PROBE_PATHS="/health"
      else
        READY="$(jq -r '.status.readyReplicas // 0' <<<"$DEPLOY_JSON")"
        DESIRED="$(jq -r '.spec.replicas // 0' <<<"$DEPLOY_JSON")"
        UPDATED="$(jq -r '.status.updatedReplicas // 0' <<<"$DEPLOY_JSON")"
        echo "    Deployment: ${B_NS}/${DEPLOY_NAME} ready=${READY}/${DESIRED} updated=${UPDATED}"

        PROBES="$(jq -r '
          .spec.template.spec.containers[]
          | .name as $c
          | [
              ["readiness", .readinessProbe.httpGet.path, (.readinessProbe.httpGet.port // ""), (.readinessProbe.httpGet.scheme // "HTTP")],
              ["liveness", .livenessProbe.httpGet.path, (.livenessProbe.httpGet.port // ""), (.livenessProbe.httpGet.scheme // "HTTP")],
              ["startup", .startupProbe.httpGet.path, (.startupProbe.httpGet.port // ""), (.startupProbe.httpGet.scheme // "HTTP")]
            ][]
          | select(.[1] != null and .[1] != "")
          | [$c, .[0], .[1], (.[2] | tostring), .[3]]
          | @tsv
        ' <<<"$DEPLOY_JSON")"

        if [[ -n "$PROBES" ]]; then
          echo "      HTTP probes:"
          printf '%s\n' "$PROBES" |
            awk -F'\t' '{printf "        - container=%s type=%s path=%s port=%s scheme=%s\n", $1, $2, $3, $4, $5}'
          PROBE_PATHS="$(printf '%s\n' "$PROBES" | awk -F'\t' '{print $3}' | unique_lines)"
        else
          warn "      No HTTP readiness/liveness/startup probe found; using /health fallback for URL generation."
          PROBE_PATHS="/health"
        fi
      fi

      echo "    Generated E2E URLs:"
      while IFS=$'\t' read -r MATCH_TYPE MATCH_PATH MATCH_HEADERS; do
        [[ -z "$MATCH_TYPE" ]] && continue
        while IFS= read -r PROBE_PATH; do
          [[ -z "$PROBE_PATH" ]] && continue
          FINAL_PATH="$(join_prefix_probe "$MATCH_TYPE" "$MATCH_PATH" "$PROBE_PATH")"
          URL="${URL_SCHEME}://$(url_authority "$URL_SCHEME" "$URL_PORT")${FINAL_PATH}"
          echo "      - $URL"
          GENERATED_URLS+=("$URL")
          VALIDATION_TARGETS+=("${URL}"$'\t'"${URL_PORT}"$'\t'"${GATEWAY_IP}")

          if [[ -n "$GATEWAY_IP" ]]; then
            CURL_COMMANDS+=("curl -k -v --max-time 10 --resolve '${FQDN}:${URL_PORT}:${GATEWAY_IP}' '${URL}'")
          else
            CURL_COMMANDS+=("curl -k -v --max-time 10 '${URL}'")
          fi
        done <<<"$PROBE_PATHS"
      done <<<"$MATCH_LINES"
    done <<<"$BACKENDS"
  done
done <<<"$MATCHED_ROUTES"

section "Final E2E URL Summary"
if [[ ${#GENERATED_URLS[@]} -eq 0 ]]; then
  fail "No E2E URLs generated."
  exit 1
fi

printf '%s\n' "${GENERATED_URLS[@]}" | unique_lines | sed 's/^/  - /'

echo ""
echo "Curl commands:"
printf '%s\n' "${CURL_COMMANDS[@]}" | unique_lines | sed 's/^/  /'

if [[ "$VALIDATE" == "--validate" ]]; then
  section "Optional curl validation"
  printf '%s\n' "${VALIDATION_TARGETS[@]}" | unique_lines | while IFS=$'\t' read -r url port gateway_ip; do
    [[ -z "$url" ]] && continue
    curl_args=(-k -s -o /dev/null -w '%{http_code}' --max-time 10)
    if [[ -n "${gateway_ip:-}" ]]; then
      curl_args+=(--resolve "${FQDN}:${port}:${gateway_ip}")
    fi
    code="$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo "000")"
    case "$code" in
      200|201|202|204) ok "HTTP $code $url" ;;
      301|302|307|308) warn "HTTP $code redirect $url" ;;
      401|403) warn "HTTP $code auth required $url" ;;
      *) fail "HTTP $code $url" ;;
    esac
  done
fi
