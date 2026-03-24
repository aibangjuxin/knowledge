#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  lb-poc-from-mig.sh <mig-pattern> [options]

Options:
  --project <project-id>              GCP project id
  --region <region>                   Filter MIG/LB resources by region
  --zone <zone>                       Filter MIGs by zone
  --backend-pattern <regex>           Filter backend service names
  --url-map-pattern <regex>           Filter URL map names
  --forwarding-rule-pattern <regex>   Filter forwarding rule names
  --lb-scheme <scheme>                Filter backend service load balancing scheme
  --include-empty                     Show MIGs even if no related LB resources are found
  --suggest-names                     Print starter names for a POC clone
  -h, --help                          Show this help

Examples:
  lb-poc-from-mig.sh my-mig --project my-project
  lb-poc-from-mig.sh api --project my-project --region us-central1
  lb-poc-from-mig.sh api --project my-project --backend-pattern web --suggest-names

Dependencies:
  - gcloud
  - jq
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

name_from_ref() {
  local ref="${1:-}"
  ref="${ref%/}"
  echo "${ref##*/}"
}

matches_regex() {
  local value="${1:-}"
  local pattern="${2:-}"
  if [[ -z "$pattern" ]]; then
    return 0
  fi
  [[ "$value" =~ $pattern ]]
}

resource_scope() {
  local json="$1"
  local region
  region="$(jq -r '.region // empty' <<<"$json")"
  if [[ -n "$region" ]]; then
    echo "regional:$(name_from_ref "$region")"
  else
    echo "global"
  fi
}

suggest_name() {
  local mig="$1"
  local base
  base="$(echo "$mig" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  base="${base:0:35}"
  base="${base%-}"
  echo "$base"
}

PROJECT=""
REGION=""
ZONE=""
BACKEND_PATTERN=""
URL_MAP_PATTERN=""
FORWARDING_RULE_PATTERN=""
LB_SCHEME=""
INCLUDE_EMPTY="false"
SUGGEST_NAMES="false"
MIG_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --zone)
      ZONE="$2"
      shift 2
      ;;
    --backend-pattern)
      BACKEND_PATTERN="$2"
      shift 2
      ;;
    --url-map-pattern)
      URL_MAP_PATTERN="$2"
      shift 2
      ;;
    --forwarding-rule-pattern)
      FORWARDING_RULE_PATTERN="$2"
      shift 2
      ;;
    --lb-scheme)
      LB_SCHEME="$2"
      shift 2
      ;;
    --include-empty)
      INCLUDE_EMPTY="true"
      shift
      ;;
    --suggest-names)
      SUGGEST_NAMES="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$MIG_PATTERN" ]]; then
        MIG_PATTERN="$1"
      else
        echo "ERROR: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$MIG_PATTERN" ]]; then
  usage >&2
  exit 1
fi

require_cmd gcloud
require_cmd jq

GCLOUD_BASE=(gcloud)
if [[ -n "$PROJECT" ]]; then
  GCLOUD_BASE+=(--project "$PROJECT")
fi

run_gcloud_json() {
  "${GCLOUD_BASE[@]}" "$@" --format=json
}

MIGS_JSON="$(run_gcloud_json compute instance-groups managed list)"
BACKENDS_JSON="$(run_gcloud_json compute backend-services list)"
URL_MAPS_LIST_JSON="$(run_gcloud_json compute url-maps list)"
FORWARDING_RULES_JSON="$(run_gcloud_json compute forwarding-rules list)"
TARGET_HTTP_PROXIES_JSON="$(run_gcloud_json compute target-http-proxies list)"
TARGET_HTTPS_PROXIES_JSON="$(run_gcloud_json compute target-https-proxies list)"
TARGET_TCP_PROXIES_JSON="$(run_gcloud_json compute target-tcp-proxies list)"
TARGET_SSL_PROXIES_JSON="$(run_gcloud_json compute target-ssl-proxies list)"
TARGET_GRPC_PROXIES_JSON="$(run_gcloud_json compute target-grpc-proxies list 2>/dev/null || echo '[]')"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "$URL_MAPS_LIST_JSON" | jq -c '.[]' > "$TMP_DIR/url_maps_list.jsonl"
>"$TMP_DIR/url_maps_full.jsonl"

while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  name="$(jq -r '.name' <<<"$item")"
  region_ref="$(jq -r '.region // empty' <<<"$item")"
  if [[ -n "$region_ref" ]]; then
    region_name="$(name_from_ref "$region_ref")"
    run_gcloud_json compute url-maps describe "$name" --region "$region_name" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  else
    run_gcloud_json compute url-maps describe "$name" | jq -c '.' >> "$TMP_DIR/url_maps_full.jsonl"
  fi
done < "$TMP_DIR/url_maps_list.jsonl"

PROXIES_JSON="$TMP_DIR/proxies.jsonl"
>"$PROXIES_JSON"
echo "$TARGET_HTTP_PROXIES_JSON"  | jq -c '.[] | .proxyKind="http"'  >> "$PROXIES_JSON"
echo "$TARGET_HTTPS_PROXIES_JSON" | jq -c '.[] | .proxyKind="https"' >> "$PROXIES_JSON"
echo "$TARGET_TCP_PROXIES_JSON"   | jq -c '.[] | .proxyKind="tcp"'   >> "$PROXIES_JSON"
echo "$TARGET_SSL_PROXIES_JSON"   | jq -c '.[] | .proxyKind="ssl"'   >> "$PROXIES_JSON"
echo "$TARGET_GRPC_PROXIES_JSON"  | jq -c '.[] | .proxyKind="grpc"'  >> "$PROXIES_JSON"

echo "# Load Balancer Discovery From MIG"
echo
echo "- project: ${PROJECT:-"(gcloud default)"}"
echo "- mig filter: ${MIG_PATTERN}"
[[ -n "$REGION" ]] && echo "- region filter: ${REGION}"
[[ -n "$ZONE" ]] && echo "- zone filter: ${ZONE}"
[[ -n "$LB_SCHEME" ]] && echo "- lb scheme filter: ${LB_SCHEME}"
echo

MATCHED_COUNT=0

echo "$MIGS_JSON" | jq -c '.[]' | while IFS= read -r mig; do
  mig_name="$(jq -r '.name' <<<"$mig")"
  zone_ref="$(jq -r '.zone // empty' <<<"$mig")"
  region_ref="$(jq -r '.region // empty' <<<"$mig")"
  zone_name="$(name_from_ref "$zone_ref")"
  region_name="$(name_from_ref "$region_ref")"
  zone_region="${zone_name%-*}"

  matches_regex "$mig_name" "$MIG_PATTERN" || continue
  [[ -n "$ZONE" && "$zone_name" != "$ZONE" ]] && continue
  if [[ -n "$REGION" && "$REGION" != "$region_name" && "$REGION" != "$zone_region" ]]; then
    continue
  fi

  instance_group="$(jq -r '.instanceGroup // empty' <<<"$mig")"
  named_ports="$(jq -r '.namedPorts // [] | map("\(.name):\(.port)") | join(", ")' <<<"$mig")"

  backend_hits_file="$TMP_DIR/backend_hits_${mig_name}.jsonl"
  >"$backend_hits_file"

  echo "$BACKENDS_JSON" | jq -c '.[]' | while IFS= read -r backend; do
    backend_name="$(jq -r '.name' <<<"$backend")"
    backend_scheme="$(jq -r '.loadBalancingScheme // "UNKNOWN"' <<<"$backend")"
    backend_region_ref="$(jq -r '.region // empty' <<<"$backend")"
    backend_region_name="$(name_from_ref "$backend_region_ref")"

    matches_regex "$backend_name" "$BACKEND_PATTERN" || continue
    [[ -n "$LB_SCHEME" && "$backend_scheme" != "$LB_SCHEME" ]] && continue
    [[ -n "$REGION" && -n "$backend_region_name" && "$backend_region_name" != "$REGION" ]] && continue

    found_group="$(jq -r --arg ig "$instance_group" '.backends // [] | map(select(.group == $ig)) | length' <<<"$backend")"
    [[ "$found_group" -gt 0 ]] || continue

    echo "$backend" >> "$backend_hits_file"
  done

  if [[ ! -s "$backend_hits_file" && "$INCLUDE_EMPTY" != "true" ]]; then
    continue
  fi

  MATCHED_COUNT=$((MATCHED_COUNT + 1))
  echo "## MIG: ${mig_name}"
  echo
  echo "- zone: ${zone_name:-"-"}"
  echo "- region: ${region_name:-"-"}"
  echo "- instanceGroup: $(name_from_ref "$instance_group")"
  echo "- namedPorts: ${named_ports:-"-"}"
  echo

  if [[ ! -s "$backend_hits_file" ]]; then
    echo "_No related backend services found._"
    echo
  else
    while IFS= read -r backend; do
      backend_name="$(jq -r '.name' <<<"$backend")"
      backend_scope="$(resource_scope "$backend")"
      backend_scheme="$(jq -r '.loadBalancingScheme // "UNKNOWN"' <<<"$backend")"
      backend_protocol="$(jq -r '.protocol // "UNKNOWN"' <<<"$backend")"
      health_checks="$(jq -r '.healthChecks // [] | map(split("/")[-1]) | join(", ")' <<<"$backend")"
      session_affinity="$(jq -r '.sessionAffinity // "-"' <<<"$backend")"
      timeout_sec="$(jq -r '.timeoutSec // "-"' <<<"$backend")"

      echo "  - Backend Service: ${backend_name}"
      echo "    scope: ${backend_scope}"
      echo "    scheme: ${backend_scheme}"
      echo "    protocol: ${backend_protocol}"
      echo "    healthChecks: ${health_checks:-"-"}"
      echo "    sessionAffinity: ${session_affinity}"
      echo "    timeoutSec: ${timeout_sec}"

      backend_self_link="$(jq -r '.selfLink // empty' <<<"$backend")"

      while IFS= read -r url_map; do
        [[ -z "$url_map" ]] && continue
        url_map_name="$(jq -r '.name' <<<"$url_map")"
        matches_regex "$url_map_name" "$URL_MAP_PATTERN" || continue

        url_map_has_backend="$(
          jq -r \
            --arg bs "$backend_self_link" \
            --arg bs_name "$backend_name" \
            '
            [
              .defaultService,
              (.pathMatchers[]?.defaultService),
              (.pathMatchers[]?.pathRules[]?.service),
              (.pathMatchers[]?.routeRules[]?.service),
              (.hostRules[]?.pathMatcher)
            ]
            | flatten
            | map(select(. != null))
            | map(tostring)
            | map(split("/")[-1])
            | any(. == $bs_name)
            ' <<<"$url_map"
        )"

        [[ "$url_map_has_backend" == "true" ]] || continue

        echo "    - URL Map: ${url_map_name} ($(resource_scope "$url_map"))"
        default_service="$(jq -r '.defaultService // empty | split("/")[-1]' <<<"$url_map")"
        [[ -n "$default_service" ]] && echo "      defaultService: ${default_service}"

        url_map_self_link="$(jq -r '.selfLink // empty' <<<"$url_map")"

        while IFS= read -r proxy; do
          [[ -z "$proxy" ]] && continue
          proxy_url_map="$(jq -r '.urlMap // empty' <<<"$proxy")"
          [[ -n "$proxy_url_map" ]] || continue
          if [[ "$proxy_url_map" != "$url_map_self_link" && "$(name_from_ref "$proxy_url_map")" != "$url_map_name" ]]; then
            continue
          fi

          proxy_name="$(jq -r '.name' <<<"$proxy")"
          proxy_kind="$(jq -r '.proxyKind' <<<"$proxy")"
          echo "      - Target ${proxy_kind^^} Proxy: ${proxy_name} ($(resource_scope "$proxy"))"
          echo "        urlMap: ${url_map_name}"
          certs="$(jq -r '.sslCertificates // [] | map(split("/")[-1]) | join(", ")' <<<"$proxy")"
          [[ -n "$certs" ]] && echo "        sslCertificates: ${certs}"

          proxy_self_link="$(jq -r '.selfLink // empty' <<<"$proxy")"
          echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
            rule_name="$(jq -r '.name' <<<"$rule")"
            matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
            rule_target="$(jq -r '.target // empty' <<<"$rule")"
            [[ -n "$rule_target" ]] || continue
            if [[ "$rule_target" != "$proxy_self_link" && "$(name_from_ref "$rule_target")" != "$proxy_name" ]]; then
              continue
            fi
            rule_scope="$(resource_scope "$rule")"
            rule_scheme="$(jq -r '.loadBalancingScheme // "-"' <<<"$rule")"
            rule_ip="$(jq -r '.IPAddress // "-"' <<<"$rule")"
            rule_ports="$(jq -r 'if (.ports // empty) != empty then (.ports | join(",")) else (.portRange // "-") end' <<<"$rule")"
            echo "        - Forwarding Rule: ${rule_name} (${rule_scope})"
            echo "          scheme: ${rule_scheme}"
            echo "          ip: ${rule_ip}"
            echo "          ports: ${rule_ports}"
            echo "          target: ${proxy_name}"
          done
        done < "$PROXIES_JSON"
      done < "$TMP_DIR/url_maps_full.jsonl"

      echo "$PROXIES_JSON" | while IFS= read -r proxy; do
        [[ -z "$proxy" ]] && continue
        service_ref="$(jq -r '.service // empty' <<<"$proxy")"
        [[ -n "$service_ref" ]] || continue
        if [[ "$service_ref" != "$backend_self_link" && "$(name_from_ref "$service_ref")" != "$backend_name" ]]; then
          continue
        fi

        proxy_name="$(jq -r '.name' <<<"$proxy")"
        proxy_kind="$(jq -r '.proxyKind' <<<"$proxy")"
        echo "    - Direct backend-attached proxy: ${proxy_name} (${proxy_kind^^})"

        proxy_self_link="$(jq -r '.selfLink // empty' <<<"$proxy")"
        echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
          rule_name="$(jq -r '.name' <<<"$rule")"
          matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
          rule_target="$(jq -r '.target // empty' <<<"$rule")"
          [[ -n "$rule_target" ]] || continue
          if [[ "$rule_target" != "$proxy_self_link" && "$(name_from_ref "$rule_target")" != "$proxy_name" ]]; then
            continue
          fi
          echo "      - Forwarding Rule: ${rule_name} ($(resource_scope "$rule"))"
        done
      done

      echo "$FORWARDING_RULES_JSON" | jq -c '.[]' | while IFS= read -r rule; do
        rule_name="$(jq -r '.name' <<<"$rule")"
        matches_regex "$rule_name" "$FORWARDING_RULE_PATTERN" || continue
        bs_ref="$(jq -r '.backendService // empty' <<<"$rule")"
        [[ -n "$bs_ref" ]] || continue
        if [[ "$bs_ref" != "$backend_self_link" && "$(name_from_ref "$bs_ref")" != "$backend_name" ]]; then
          continue
        fi
        echo "    - Direct backend-attached forwarding rule: ${rule_name} ($(resource_scope "$rule"))"
      done
    done < "$backend_hits_file"
  fi

  if [[ "$SUGGEST_NAMES" == "true" ]]; then
    base="$(suggest_name "$mig_name")"
    echo
    echo "### POC Name Suggestions"
    echo
    echo "- health_check: ${base}-poc-hc"
    echo "- backend_service: ${base}-poc-bs"
    echo "- url_map: ${base}-poc-um"
    echo "- target_proxy: ${base}-poc-proxy"
    echo "- forwarding_rule: ${base}-poc-fr"
  fi
  echo
done

echo "## Notes"
echo
echo "- MIG 只能帮你反推出已绑定它的 backend service 和上游 LB 依赖链。"
echo "- 如果 MIG 还没有被任何 backend service 使用，这个脚本拿不到完整 LB 信息。"
echo "- 如果一个 MIG 被多个 backend service / LB 复用，这个脚本会全部列出来，便于你筛选适合 POC 的那一条。"
echo "- 做 POC 前仍然需要确认依赖是否可共享，例如 health check、named port、firewall、证书、静态 IP、proxy-only subnet。"
