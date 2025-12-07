问题分析

你原始脚本逻辑清晰、覆盖面广，但在鲁棒性与失败处理方面存在若干问题（set -e 导致意外退出、未检查依赖、jsonpath 解析不稳、证书解析不够健壮、把 backend port 错当为对外 listener port 等）。为了真实环境可用，需保证即便某些 kubectl 查询失败也能继续检查其它项，并给出明确的 summary 与错误提示，同时遵守部署前检查权限与 YAML 验证的最佳实践。

⸻

解决方案（要点）
• 使用 set -euo pipefail 并对可能失败的命令显式捕获错误（|| true），避免非预期退出。
• 依赖检查（kubectl, jq, openssl, curl）并在缺失时降级处理或提示。
• 使用 kubectl -o json + jq 做安全解析；当 jq 不可用时回退到安全的 jsonpath / 原样输出并发出提示。
• 证书处理：先判断 secret 类型，再 decode tls.crt，再用 openssl x509 解析（subject/issuer/dates/SAN）。
• 获取外部访问端口优先读取 Gateway spec.listeners[].port（只有在能正确解析 listener 时），否则回退到常见端口（443/80）。
• 所有“可能失败但不是致命”的命令都捕获并记录，最后输出 summary（errors/warnings）。
• 在脚本顶部提醒用户检查权限与 kubeconfig，上线前建议 kubectl apply --dry-run=client -f <yaml> 验证。

⸻

增强后脚本（可直接复制到 .sh 并执行）

使用说明：在执行前确认你有对集群读取权限，脚本会检查依赖并在能用 jq 时进行更准确的 JSON 处理。
示例：./verify-gke-gateway-claude.sh -g gateway-ns -u app-ns

```bash
#!/usr/bin/env bash
#==============================================================================
# Enhanced: GKE Internal Gateway Verification Script
# Purpose: Verify GKE Gateway API configuration and resource status (robust)
# Author: Infrastructure Team (enhanced)
# Version: 2.0
#==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Globals
GATEWAY_NAMESPACE=""
USER_NAMESPACE=""
VERBOSE=0
DEPENDENCIES=(kubectl openssl)
HAS_JQ=0
HAS_CURL=0

# Stats
ERRORS=0
WARNINGS=0

# Logging
log() { printf "%b\n" "$1"; }
log_info()    { log "${BLUE}[INFO]${NC} $1"; }
log_success() { log "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { WARNINGS=$((WARNINGS+1)); log "${YELLOW}[WARN]${NC} $1"; }
log_error()   { ERRORS=$((ERRORS+1)); log "${RED}[ERROR]${NC} $1"; }

print_section() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
}

show_usage() {
    cat <<EOF
Usage: $0 -g <gateway-namespace> -u <user-namespace> [-v]
Options:
  -g <gateway-namespace>   Gateway Namespace (required)
  -u <user-namespace>      User Namespace (required)
  -v                       Verbose (optional)
  -h                       Show help
Example:
  $0 -g gateway-ns -u application-ns
EOF
    exit 1
}

# ---- parse args
while getopts "g:u:vh" opt; do
    case "$opt" in
        g) GATEWAY_NAMESPACE="$OPTARG" ;;
        u) USER_NAMESPACE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) show_usage ;;
        *) show_usage ;;
    esac
done

if [ -z "${GATEWAY_NAMESPACE}" ] || [ -z "${USER_NAMESPACE}" ]; then
    log_error "Missing required arguments"
    show_usage
fi

# ---- dependency check
for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command '$cmd' not found in PATH. Please install it before running."
        exit 2
    fi
done

if command -v jq &>/dev/null; then
    HAS_JQ=1
else
    log_warn "jq not found: JSON parsing will be less precise. Install jq for better results."
fi

if command -v curl &>/dev/null; then
    HAS_CURL=1
fi

# ---- helper safe kubectl wrapper: run but don't exit script on failure (unless fatal flag)
run_kubectl() {
    # usage: run_kubectl <fatal:0|1> -- kubectl args...
    local fatal="$1"; shift
    # pass through the rest to kubectl
    if kubectl "$@" 2>/dev/null; then
        return 0
    else
        if [ "$fatal" -eq 1 ]; then
            log_error "kubectl failed: kubectl $*"
            exit 3
        else
            log_warn "kubectl returned non-zero: kubectl $*"
            return 1
        fi
    fi
}

# ---- pre-flight: check kube access
print_section "Pre-flight checks"
log_info "Checking kubectl connectivity and current context..."
if ! kubectl version --client &>/dev/null; then
    log_error "kubectl client not available"
    exit 2
fi

if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot reach cluster. Please verify kubeconfig and network access."
    exit 2
fi
log_success "kubectl is available and cluster is reachable"

log_info "Gateway Namespace: ${GATEWAY_NAMESPACE}"
log_info "User Namespace   : ${USER_NAMESPACE}"

#==============================================================================
# 1. Cluster Level Check
#==============================================================================
print_section "1. Cluster Level - GatewayClass & CRDs"

# GatewayClass
if run_kubectl 0 -- get gatewayclass -o name; then
    run_kubectl 0 -- get gatewayclass -o wide
    log_success "GatewayClass resources present (at least one)"
else
    log_error "No GatewayClass found. Ensure Gateway API is installed and CRDs are present."
fi

# CRD checks
REQUIRED_CRDS=(
  "gateways.gateway.networking.k8s.io"
  "httproutes.gateway.networking.k8s.io"
  "gatewayclasses.gateway.networking.k8s.io"
  "healthcheckpolicies.gateway.networking.k8s.io"
)
for crd in "${REQUIRED_CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        log_success "CRD installed: $crd"
    else
        log_warn "CRD missing: $crd"
    fi
done

#==============================================================================
# 2. Gateway Namespace Check
#==============================================================================
print_section "2. Gateway Namespace - ${GATEWAY_NAMESPACE}"

# Namespace exists?
if ! kubectl get namespace "${GATEWAY_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${GATEWAY_NAMESPACE} does not exist or you lack permission"
    exit 4
fi
log_success "Namespace ${GATEWAY_NAMESPACE} exists"

# List Gateways in namespace
GATEWAYS_JSON=""
if kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json &>/dev/null; then
    GATEWAYS_JSON=$(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o json)
else
    log_warn "No Gateway resources found in ${GATEWAY_NAMESPACE}"
fi

if [ -n "${GATEWAYS_JSON}" ]; then
    if [ "${HAS_JQ}" -eq 1 ]; then
        GATEWAY_NAMES=($(jq -r '.items[].metadata.name' <<<"$GATEWAYS_JSON" 2>/dev/null || true))
    else
        # fallback: try jsonpath (may be brittle)
        GATEWAY_NAMES=($(kubectl get gateway -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    fi

    if [ ${#GATEWAY_NAMES[@]} -eq 0 ]; then
        log_warn "No Gateway objects found (after parsing)"
    else
        for gw in "${GATEWAY_NAMES[@]}"; do
            echo ""
            log_info "Gateway: ${gw}"

            # print status (jsonpath if possible)
            if kubectl get gateway "${gw}" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.status}' &>/dev/null; then
                kubectl get gateway "${gw}" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.status}' || true
                echo ""
            else
                log_warn "No status available for Gateway ${gw}"
            fi

            # try to get assigned IP(s)
            if HAS_JQ=1; then :; fi # noop so shellcheck doesn't complain

            # use jq when available
            if command -v jq &>/dev/null; then
                GW_IPS=($(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .status.addresses[]?.value' <<<"$GATEWAYS_JSON" 2>/dev/null || true))
            else
                # fallback: try jsonpath for first address
                GW_IP=$(kubectl get gateway "$gw" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
                if [ -n "$GW_IP" ]; then
                    GW_IPS=("$GW_IP")
                else
                    GW_IPS=()
                fi
            fi

            if [ ${#GW_IPS[@]} -gt 0 ]; then
                for ip in "${GW_IPS[@]}"; do
                    log_success "Assigned Address: $ip"
                done
            else
                log_warn "No assigned addresses found for Gateway ${gw}"
            fi
        done
    fi
fi

# 2.2 HealthCheckPolicy
echo ""
log_info "Checking HealthCheckPolicy in ${GATEWAY_NAMESPACE}..."
if kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o wide || true
    HCP_NAMES=($(kubectl get healthcheckpolicy -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    for hcp in "${HCP_NAMES[@]}"; do
        echo ""
        log_info "HealthCheckPolicy: $hcp"
        kubectl get healthcheckpolicy "${hcp}" -n "${GATEWAY_NAMESPACE}" -o yaml || true
    done
else
    log_warn "No HealthCheckPolicy resources in ${GATEWAY_NAMESPACE}"
fi

# 2.3 NetworkPolicy
echo ""
log_info "Checking NetworkPolicy in ${GATEWAY_NAMESPACE}..."
if kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
    kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" -o wide || true
    NP_NAMES=($(kubectl get networkpolicy -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    for np in "${NP_NAMES[@]}"; do
        echo ""
        log_info "NetworkPolicy: $np"
        kubectl get networkpolicy "$np" -n "${GATEWAY_NAMESPACE}" -o yaml || true
    done
else
    log_warn "No NetworkPolicy resources in ${GATEWAY_NAMESPACE}"
fi

# 2.4 Gateway TLS / Certificate Checks
echo ""
log_info "Checking Gateway TLS listeners and referenced secrets..."

if [ -n "${GATEWAYS_JSON}" ]; then
    for gw in "${GATEWAY_NAMES[@]}"; do
        echo ""
        log_info "=== Gateway: ${gw} ==="
        GW_JSON=$(kubectl get gateway "$gw" -n "${GATEWAY_NAMESPACE}" -o json 2>/dev/null || true)

        # parse listeners and certificateRefs
        if command -v jq &>/dev/null; then
            LISTENERS_JSON=$(jq -r --arg name "$gw" '.items[] | select(.metadata.name==$name) | .spec.listeners' <<<"$GATEWAYS_JSON" 2>/dev/null || true)
            if [ -z "$LISTENERS_JSON" ] || [ "$LISTENERS_JSON" = "null" ]; then
                log_warn "No listeners defined in Gateway ${gw}"
                continue
            fi

            # for each listener, get listener.name, hostname, port and tls.certificateRefs[]
            echo "$LISTENERS_JSON" | jq -c '.[]' | while read -r listener; do
                listener_name=$(jq -r '.name // empty' <<<"$listener")
                listener_hostname=$(jq -r '.hostname // empty' <<<"$listener")
                listener_port=$(jq -r '.port // empty' <<<"$listener")
                cert_ref_names=($(jq -r '.tls.certificateRefs[]?.name // empty' <<<"$listener" | sed '/^$/d'))

                log_info "Listener: ${listener_name:-<unnamed>} hostname:${listener_hostname:-<none>} port:${listener_port:-<none>}"
                if [ ${#cert_ref_names[@]} -eq 0 ]; then
                    log_warn "No certificateRefs in listener ${listener_name:-<unnamed>}"
                else
                    for secret_name in "${cert_ref_names[@]}"; do
                        log_info "Referenced Secret: $secret_name (ns: ${GATEWAY_NAMESPACE})"
                        # get secret, check type
                        if kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
                            secret_type=$(kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.type}' 2>/dev/null || true)
                            if [ "$secret_type" != "kubernetes.io/tls" ]; then
                                log_warn "Secret $secret_name is type '$secret_type' (expected kubernetes.io/tls)"
                            fi

                            crt_b64=$(kubectl get secret "$secret_name" -n "${GATEWAY_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
                            if [ -n "${crt_b64}" ]; then
                                # decode into temp file
                                tmpcrt=$(mktemp)
                                printf '%s' "$crt_b64" | base64 -d > "$tmpcrt" 2>/dev/null || true
                                if [ -s "$tmpcrt" ]; then
                                    log_info "Certificate summary for $secret_name:"
                                    openssl x509 -in "$tmpcrt" -noout -subject -issuer -startdate -enddate \
                                        || log_warn "openssl failed to parse certificate for $secret_name"
                                    # show SAN if possible
                                    openssl x509 -in "$tmpcrt" -noout -text | sed -n '/Subject Alternative Name:/, /X509v3/{/DNS/p;}' || true
                                    rm -f "$tmpcrt"
                                else
                                    log_warn "Secret $secret_name contains no tls.crt"
                                fi
                            else
                                log_warn "Secret $secret_name missing tls.crt data"
                            fi
                        else
                            log_warn "Referenced secret $secret_name does not exist in ${GATEWAY_NAMESPACE}"
                        fi
                    done
                fi
            done
        else
            # no jq: fallback simple output
            log_warn "Skipping deep listener parsing (jq not installed). Showing raw Gateway YAML:"
            kubectl get gateway "$gw" -n "${GATEWAY_NAMESPACE}" -o yaml || true
        fi
    done
fi

#==============================================================================
# 3. User Namespace Check - HTTPRoute binding & test URL generation
#==============================================================================
print_section "3. User Namespace - ${USER_NAMESPACE}"

if ! kubectl get namespace "${USER_NAMESPACE}" &>/dev/null; then
    log_error "Namespace ${USER_NAMESPACE} does not exist or you lack permission"
    exit 5
fi
log_success "Namespace ${USER_NAMESPACE} exists"

# get HTTPRoute objects
HTR_JSON=""
if kubectl get httproute -n "${USER_NAMESPACE}" -o json &>/dev/null; then
    HTR_JSON=$(kubectl get httproute -n "${USER_NAMESPACE}" -o json)
else
    log_warn "No HTTPRoute resources found in ${USER_NAMESPACE}"
fi

if [ -n "$HTR_JSON" ]; then
    if command -v jq &>/dev/null; then
        ROUTE_NAMES=($(jq -r '.items[].metadata.name' <<<"$HTR_JSON" || true))
    else
        ROUTE_NAMES=($(kubectl get httproute -n "$USER_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true))
    fi

    for route in "${ROUTE_NAMES[@]}"; do
        echo ""
        log_info "=== HTTPRoute: ${route} ==="
        kubectl get httproute "${route}" -n "${USER_NAMESPACE}" -o yaml || true

        # extract hostnames and parentRefs
        if command -v jq &>/dev/null; then
            HOSTNAMES=($(jq -r --arg name "$route" '.items[] | select(.metadata.name==$name) | .spec.hostnames[]? // empty' <<<"$HTR_JSON" || true))
            # parentRefs can be many; extract names and namespace (if provided)
            # parentRefs usually: name + namespace(optional)
            PARENT_REFS=$(jq -c --arg name "$route" '.items[] | select(.metadata.name==$name) | .spec.parentRefs[]? // empty' <<<"$HTR_JSON" || true)
        else
            HOSTNAMES=($(kubectl get httproute "$route" -n "$USER_NAMESPACE" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null || true))
            PARENT_REFS="" # skip deep parsing without jq
        fi

        # for each hostname, try to determine listener port from referenced Gateway(s)
        if [ ${#HOSTNAMES[@]} -eq 0 ]; then
            HOSTNAMES=("<none>")
        fi

        for hostname in "${HOSTNAMES[@]}"; do
            # default port
            LISTENER_PORT=""
            # attempt to parse parentRefs and get gateway listener port that matches hostname
            if command -v jq &>/dev/null && [ -n "$PARENT_REFS" ]; then
                # iterate parentRefs
                echo "$PARENT_REFS" | jq -c '.' | while read -r parent; do
                    parent_name=$(jq -r '.name // empty' <<<"$parent")
                    parent_ns=$(jq -r '.namespace // empty' <<<"$parent")
                    [ -z "$parent_ns" ] && parent_ns="${GATEWAY_NAMESPACE}" # fallback to gateway ns assumption

                    # get gateway json
                    gwjson=$(kubectl get gateway "$parent_name" -n "$parent_ns" -o json 2>/dev/null || true)
                    if [ -z "$gwjson" ]; then
                        log_warn "Parent Gateway ${parent_name} not found in namespace ${parent_ns}"
                        continue
                    fi

                    # find listener that matches hostname or has no hostname (hostless)
                    listener_port=$(jq -r --arg host "$hostname" \
                        '.spec.listeners[]? | select((.hostname==($host)) or (.hostname==null) or (.hostname=="")) | .port // empty' \
                        <<<"$gwjson" 2>/dev/null || true)

                    if [ -n "$listener_port" ]; then
                        LISTENER_PORT="$listener_port"
                        break
                    fi
                done
            fi

            # fallback if not found
            if [ -z "$LISTENER_PORT" ]; then
                # Use 443 by default for HTTPS; note: this is not guaranteed correct if listener uses non-standard port.
                LISTENER_PORT=443
                log_warn "Could not determine listener port for hostname ${hostname}; defaulting to ${LISTENER_PORT}. Validate Gateway listeners for accurate port."
            fi

            # Attempt to extract path from first match rule (best-effort)
            PATH_VALUE="/"
            if command -v jq &>/dev/null; then
                PATH_VALUE=$(jq -r --arg r "$route" --arg host "$hostname" \
                  '.items[] | select(.metadata.name==$r) | .spec.rules[0].matches[0].path.value // "/"' \
                  <<<"$HTR_JSON" 2>/dev/null || echo "/")
            fi

            TEST_URL="https://${hostname}:${LISTENER_PORT}${PATH_VALUE}"
            log_success "Test URL: $TEST_URL"
            log_info "  Hostname: ${hostname}"
            log_info "  Listener Port (best-effort): ${LISTENER_PORT}"
            log_info "  Path (best-effort): ${PATH_VALUE}"

            # Optional live test
            if [ "${HAS_CURL}" -eq 1 ]; then
                # use -k to ignore cert errors (since we're only testing connectivity). Do not do this for real validation.
                log_info "Performing HEAD request to ${TEST_URL} (insecure)"
                if curl -k -I --max-time 10 "${TEST_URL}" &>/dev/null; then
                    log_success "Connectivity OK for ${TEST_URL}"
                else
                    log_warn "Connectivity test failed for ${TEST_URL} (this may be due to network/firewall/Cloud LB config)"
                fi
            else
                log_warn "curl not installed; skipping live HTTP connectivity test"
            fi
        done
    done
fi

#==============================================================================
# 4. Summary Report
#==============================================================================
print_section "Verification Complete"
log_info "Errors: ${ERRORS}, Warnings: ${WARNINGS}"
echo ""
cat <<EOF
Verification Scope:
  - Cluster Level: GatewayClass, Gateway API CRDs
  - Gateway Namespace (${GATEWAY_NAMESPACE}): Gateway, listeners, HealthCheckPolicy, NetworkPolicy, TLS secrets
  - User Namespace (${USER_NAMESPACE}): HTTPRoute bindings, hostnames, test URLs
EOF

if [ "${ERRORS}" -gt 0 ]; then
    log_error "Completed with errors. Please inspect output above and fix the issues."
    exit 6
else
    log_success "Completed successfully (warnings may exist)."
    exit 0
fi
```

⸻

流程图（Mermaid）

```mermaid
graph TD
    A[Start] --> B[Pre-flight: deps & kube connectivity]
    B --> C[Cluster checks: GatewayClass & CRDs]
    C --> D[Gateway Namespace Checks]
    D --> D1[Enumerate Gateways]
    D1 --> D2[Check status / addresses]
    D2 --> D3[Parse listeners & cert refs]
    D3 --> D4[Validate TLS secrets & openssl checks]
    D --> E[HealthCheckPolicy & NetworkPolicy checks]
    E --> F[User Namespace Checks]
    F --> F1[Enumerate HTTPRoute]
    F1 --> F2[Resolve parentRefs -> Gateway listeners]
    F2 --> F3[Generate Test URLs & connectivity test (curl)]
    F3 --> G[Summary and Exit]
```

注意：Mermaid 中节点标签避免使用 ()，若使用特殊字符请用 "" 包裹。

⸻

注意事项与最佳实践 1. 权限：运行该脚本需要对目标 namespace 的 get 权限（至少只读）。在执行前请确认 kubectl auth can-i get gateway --namespace=${GATEWAY_NAMESPACE}。 2. 依赖：推荐安装 jq, curl, openssl 用于更准确解析与联网检测。
• 安装示例（Debian/Ubuntu）：sudo apt-get update && sudo apt-get install -y jq curl openssl 3. YAML 验证：任何变更/应用前用 kubectl apply --dry-run=client -f <file.yaml> 或 kubectl apply --server-dry-run -f <file.yaml>（若集群支持）。 4. 证书：脚本使用 openssl 输出 subject, issuer, startdate, enddate。如需更多信息（OCSP/CRL），应额外检查。 5. 端口映射：HTTPRoute 的 backendRefs.port 表示服务内部目标端口 不是 Gateway listener port。脚本优先尝试读取 Gateway listener port；若无法推断，会默认 443（这只是便于测试连接，不代表真实暴露端口）。建议在 Gateway spec 中明确 listener.port，避免猜测。 6. 失败处理：脚本会尽量继续执行并在末尾汇总 Errors / Warnings，便于定位问题。 7. 可扩展性：如需把结果导出为 JSON/CSV/HTML 报告，可在脚本中追加 summary 收集并写出文件（我可以为你扩展）。

⸻

如果你希望，我可以下一步直接：
• 把这个脚本 压缩为更小的版本（减少 jq 依赖，适配受限环境），或
• 加入 HTML 报告导出 与更详细的证书字段（SAN 列表、issuer CN 等），或
• 为你 把脚本转换成 Kubernetes Job（在集群内以 Pod 形式运行并上传结果到 GCS/Artifact）。

你要我继续做哪一步？
