```bash
#!/usr/bin/env bash
# verify-ns-labels.sh
#
# 用途：
#   1. 输出指定 Namespace 下的 NetworkPolicy
#   2. 列出该 Namespace 的所有标签
#   3. 检查是否存在标签 nsType=int-kdp
#   4. 如果不存在，则自动补充该标签
#
# 使用示例：
#   ./verify-ns-labels.sh -n my-namespace
#
# 前置条件：
#   - 已配置 kubectl 并具备对应 Namespace 的 get / patch 权限

set -euo pipefail

usage() {
  echo "Usage: $0 -n <namespace>"
  exit 1
}

# ---------- 参数解析 ----------
NAMESPACE=""

while getopts ":n:" opt; do
  case "${opt}" in
    n)
      NAMESPACE="${OPTARG}"
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "${NAMESPACE}" ]]; then
  usage
fi

# ---------- 基础检查 ----------
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[ERROR] Namespace '${NAMESPACE}' does not exist or access denied."
  exit 1
fi

echo "================================================="
echo "Namespace: ${NAMESPACE}"
echo "================================================="

# ---------- 1. 输出 NetworkPolicy ----------
echo
echo "[1] NetworkPolicy in namespace '${NAMESPACE}':"
echo "-------------------------------------------------"

if kubectl get networkpolicy -n "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl get networkpolicy -n "${NAMESPACE}" -o wide
else
  echo "No NetworkPolicy resource found (or NetworkPolicy CRD not enabled)."
fi

# ---------- 2. 列出 Namespace 标签 ----------
echo
echo "[2] Namespace labels:"
echo "-------------------------------------------------"

kubectl get namespace "${NAMESPACE}" --show-labels

# ---------- 3. 检查 nsType=int-kdp ----------
echo
echo "[3] Verify label 'nsType=int-kdp':"
echo "-------------------------------------------------"

CURRENT_LABEL=$(kubectl get namespace "${NAMESPACE}" \
  -o jsonpath='{.metadata.labels.nsType}' 2>/dev/null || true)

if [[ "${CURRENT_LABEL}" == "int-kdp" ]]; then
  echo "[OK] Label nsType=int-kdp already exists."
  exit 0
fi

# ---------- 4. 不存在则补充标签 ----------
echo "[WARN] Label nsType=int-kdp not found."
echo "[ACTION] Adding label nsType=int-kdp to namespace '${NAMESPACE}'..."

kubectl label namespace "${NAMESPACE}" nsType=int-kdp --overwrite

echo "[DONE] Label successfully added."

# ---------- 最终状态确认 ----------
echo
echo "[Final] Namespace labels after update:"
echo "-------------------------------------------------"

kubectl get namespace "${NAMESPACE}" --show-labels
```
注意事项
	•	请确保执行脚本的身份具备以下 RBAC 权限：
	•	get / list：namespaces
	•	patch：namespaces
	•	get / list：networkpolicies
	•	如果你的集群未启用 NetworkPolicy（如未安装对应 CNI），第 1 步可能返回空结果，这是正常现象
	•	--overwrite 已开启，避免标签存在但值不一致导致失败

如果你后续希望 只校验不自动修改，或增加 --dry-run 模式，我可以直接帮你改成企业级合规脚本版本。