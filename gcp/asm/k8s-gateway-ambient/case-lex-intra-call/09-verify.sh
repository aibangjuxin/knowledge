#!/usr/bin/env bash
# =============================================================================
# 09-verify.sh
# =============================================================================
# Intra-namespace call PoC 验证脚本
#
# 用法:
#   bash 09-verify.sh
#
# 前置: 00 ~ 08 已 apply 且 Pod 全部 Running
# =============================================================================
set -uo pipefail

NS=ba000000-lex-intra-call
FQDN="lex-api2-service.${NS}.svc.cluster.local"
CURL_IMG="curlimages/curl:8.10.1"

hr() { printf '\n\033[1;36m========== %s ==========\033[0m\n' "$1"; }

hr "1. 资源就绪检查"
kubectl get ns "${NS}" -o wide
kubectl get gateway,svc,httproute,deploy,pod -n "${NS}" -o wide || true

hr "2. waypoint 是否就绪(必须 2/2 Ready)"
kubectl get pods -n "${NS}" -l gateway.networking.k8s.io/gateway-name=waypoint-intra

hr "3. DNS 解析(FQDN 必须能解析到 ClusterIP)"
kubectl run dnscheck --rm -i --restart=Never --image=busybox:1.36 --quiet -- \
  nslookup "${FQDN}" 2>&1 | sed 's/^/  /'

hr "4. Service Endpoints(版本 Service 必须各自命中对应版本的 pod)"
echo "--- lex-api2-service (稳定入口) ---"
kubectl get endpoints lex-api2-service      -n "${NS}" -o wide
echo "--- lex-api2-service-v1 ---"
kubectl get endpoints lex-api2-service-v1   -n "${NS}" -o wide
echo "--- lex-api2-service-v2 ---"
kubectl get endpoints lex-api2-service-v2   -n "${NS}" -o wide

hr "5. HTTPRoute 是否被控制面接受(status.parents 应有 Accepted=True)"
kubectl get httproute lex-api2-version-route -n "${NS}" -o yaml | sed -n '/^status:/,$p'

hr "6. ★ 核心验证:同一个 URL,不同版本头,落到不同版本 ★"
call() {
  local desc="$1"; shift
  printf '  %-34s → ' "${desc}"
  kubectl run curlcheck --rm -i --restart=Never --image="${CURL_IMG}" --quiet -- \
    curl -sS -m 5 "$@" "${FQDN}/resource" 2>&1 | tr -d '\n' | sed 's/^/  /'
  printf '\n'
}
call "x-api-version: 1.0.0" -H 'x-api-version: 1.0.0'
call "x-api-version: 2.0.0" -H 'x-api-version: 2.0.0'
call "无版本头(兜底 → 默认版本)"

hr "7. 调用方日志(两个调用方应分别看到 v1 / v2)"
echo "--- lex-api1 (profile-v1) ---"
kubectl logs -n "${NS}" deploy/lex-api1 --tail=4 2>&1 | sed 's/^/  /'
echo "--- lex-api1-canary (profile-v2) ---"
kubectl logs -n "${NS}" deploy/lex-api1-canary --tail=4 2>&1 | sed 's/^/  /'

hr "8. 确认走的是 mesh(不是 internal ingress / hairpin)"
echo "--- ztunnel 接管的工作负载 ---"
istioctl ztunnel-config workloads 2>/dev/null | grep -i "lex-api" || echo "  (未找到,检查 istioctl 是否已安装 / istio-system 是否正常)"
echo "--- waypoint 上的路由(应能看到 lex-api2 的 v1/v2 cluster) ---"
kubectl run proxycfg --rm -i --restart=Never --image="${CURL_IMG}" --quiet -- \
  sh -c "curl -sS http://waypoint-intra.${NS}:15008/healthz" 2>/dev/null || true
istioctl proxy-config route deploy/waypoint-intra -n "${NS}" 2>/dev/null | head -20 || true

hr "9. 授权检查(应能看到 allow-caller-to-api2 已生效)"
istioctl x authz check -n "${NS}" 2>&1 | sed 's/^/  /' || true

hr "10. 反向验证:用未授权身份调用应被拒(可选)"
echo "  提示:把 07-authz.yaml 里的 principals 改成一个不存在的 SA 可模拟 403"

hr "完成"
