#!/bin/bash

# migrate-secrets.sh - Kubernetes Secrets 迁移脚本
# 用法: ./migrate-secrets.sh -n <namespace>

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认值
NAMESPACE=""
OUTPUT_DIR="./secrets-backup"
EXCLUDE_PATTERNS="default-token-|^sh\.helm\.release"

# 显示使用说明
usage() {
    cat << EOF
用法: $0 -n <namespace> [选项]

选项:
    -n <namespace>    指定要迁移的 namespace (必需)
    -o <output_dir>   指定输出目录 (默认: ./secrets-backup)
    -e <pattern>      额外的排除模式 (使用 grep -E 格式)
    -h                显示帮助信息

示例:
    $0 -n production
    $0 -n production -o /backup/secrets
    $0 -n production -e "additional-pattern"
EOF
    exit 1
}

# 解析命令行参数
while getopts "n:o:e:h" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        e) EXCLUDE_PATTERNS="$EXCLUDE_PATTERNS|$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# 检查必需参数
if [ -z "$NAMESPACE" ]; then
    echo -e "${RED}错误: 必须指定 namespace${NC}"
    usage
fi

# 检查 kubectl 是否可用
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}错误: kubectl 命令未找到${NC}"
    exit 1
fi

# 检查 namespace 是否存在
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}错误: namespace '$NAMESPACE' 不存在${NC}"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR/$NAMESPACE"

echo -e "${GREEN}开始迁移 namespace: $NAMESPACE${NC}"
echo -e "${YELLOW}输出目录: $OUTPUT_DIR/$NAMESPACE${NC}"
echo -e "${YELLOW}排除模式: $EXCLUDE_PATTERNS${NC}"
echo ""

# 获取所有 secrets 并排除默认 token
SECRETS=$(kubectl get secrets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' | \
          tr ' ' '\n' | \
          grep -vE "$EXCLUDE_PATTERNS")

# 检查是否有需要迁移的 secrets
if [ -z "$SECRETS" ]; then
    echo -e "${YELLOW}警告: 没有找到需要迁移的 secrets${NC}"
    exit 0
fi

# 统计信息
TOTAL_SECRETS=$(echo "$SECRETS" | wc -l)
CURRENT=0
FAILED=0

echo -e "${GREEN}找到 $TOTAL_SECRETS 个需要迁移的 secrets${NC}"
echo ""

# 创建失败列表文件
FAILED_FILE="$OUTPUT_DIR/$NAMESPACE/failed-secrets.txt"
> "$FAILED_FILE"

# 导出每个 secret
for SECRET in $SECRETS; do
    CURRENT=$((CURRENT + 1))
    echo -e "${YELLOW}[$CURRENT/$TOTAL_SECRETS]${NC} 导出 secret: $SECRET"
    
    if kubectl get secret "$SECRET" -n "$NAMESPACE" -o yaml > "$OUTPUT_DIR/$NAMESPACE/$SECRET.yaml" 2>/dev/null; then
        # 清理 secret YAML 中的运行时字段
        sed -i.bak \
            -e '/^  creationTimestamp:/d' \
            -e '/^  resourceVersion:/d' \
            -e '/^  uid:/d' \
            -e '/^  selfLink:/d' \
            -e '/^status:/,$d' \
            "$OUTPUT_DIR/$NAMESPACE/$SECRET.yaml"
        
        # 删除备份文件
        rm -f "$OUTPUT_DIR/$NAMESPACE/$SECRET.yaml.bak"
        
        echo -e "${GREEN}  ✓ 成功${NC}"
    else
        echo -e "${RED}  ✗ 失败${NC}"
        echo "$SECRET" >> "$FAILED_FILE"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo -e "${GREEN}迁移完成!${NC}"
echo -e "成功: $((TOTAL_SECRETS - FAILED))/$TOTAL_SECRETS"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}失败: $FAILED/$TOTAL_SECRETS${NC}"
    echo -e "${RED}失败列表已保存到: $FAILED_FILE${NC}"
fi
echo -e "导出文件位置: $OUTPUT_DIR/$NAMESPACE/"

# 生成应用脚本
cat > "$OUTPUT_DIR/$NAMESPACE/apply-secrets.sh" << 'APPLY_SCRIPT'
#!/bin/bash
# 应用导出的 secrets 到目标集群
set -e

NAMESPACE="${1:-}"
if [ -z "$NAMESPACE" ]; then
    echo "用法: $0 <target-namespace>"
    exit 1
fi

# 确保目标 namespace 存在
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 应用所有 secret YAML 文件
for yaml_file in *.yaml; do
    if [ -f "$yaml_file" ]; then
        echo "应用: $yaml_file"
        kubectl apply -f "$yaml_file" -n "$NAMESPACE"
    fi
done

echo "所有 secrets 已成功应用到 namespace: $NAMESPACE"
APPLY_SCRIPT

chmod +x "$OUTPUT_DIR/$NAMESPACE/apply-secrets.sh"
echo -e "${GREEN}已生成应用脚本: $OUTPUT_DIR/$NAMESPACE/apply-secrets.sh${NC}"