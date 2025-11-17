# Google Cloud Storage Buckets 配置迁移方案

## 问题分析

您需要将 GCS Bucket 的配置从 A 工程迁移到 B 工程，主要关注：

- **Lifecycle 规则**：可以直接导出 JSON 并应用到 B 工程
- **IAM Policy**：需要导出作为参考，手动调整成 B 工程的对应账户

## 解决方案

### 方案流程

```mermaid
graph TD
    A[开始] --> B[连接到 A 工程]
    B --> C[列出所有 Buckets]
    C --> D[导出 Lifecycle 配置]
    C --> E[导出 IAM Policy 配置]
    D --> F[保存为 JSON 文件]
    E --> G[保存为参考文档]
    F --> H[切换到 B 工程]
    G --> H
    H --> I[应用 Lifecycle 配置]
    I --> J[根据参考手动配置 IAM]
    J --> K[验证配置]
    K --> L[结束]
```

### 实施步骤

#### 1. 导出 A 工程配置

```bash
#!/bin/bash
# export_bucket_configs.sh - 导出 A 工程 Bucket 配置

set -e

# 配置变量
PROJECT_A="your-project-a-id"
OUTPUT_DIR="./bucket_configs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 创建输出目录
mkdir -p "${OUTPUT_DIR}/lifecycle"
mkdir -p "${OUTPUT_DIR}/iam"

# 设置当前工程
gcloud config set project "${PROJECT_A}"

echo "=== 开始导出 ${PROJECT_A} 的 Bucket 配置 ==="

# 获取所有 Buckets
BUCKETS=$(gsutil ls)

for BUCKET in ${BUCKETS}; do
    # 去掉 gs:// 前缀和末尾斜杠
    BUCKET_NAME=$(echo ${BUCKET} | sed 's|gs://||g' | sed 's|/||g')
    
    echo "处理 Bucket: ${BUCKET_NAME}"
    
    # 1. 导出 Lifecycle 配置
    echo "  - 导出 Lifecycle 配置..."
    if gsutil lifecycle get "gs://${BUCKET_NAME}" > "${OUTPUT_DIR}/lifecycle/${BUCKET_NAME}_lifecycle.json" 2>/dev/null; then
        echo "    ✓ Lifecycle 配置已保存"
    else
        echo "    ✗ 该 Bucket 无 Lifecycle 配置"
        echo "{}" > "${OUTPUT_DIR}/lifecycle/${BUCKET_NAME}_lifecycle.json"
    fi
    
    # 2. 导出 IAM Policy
    echo "  - 导出 IAM Policy..."
    gsutil iam get "gs://${BUCKET_NAME}" > "${OUTPUT_DIR}/iam/${BUCKET_NAME}_iam.json"
    
    # 3. 生成可读的 IAM 绑定列表
    echo "  - 生成 IAM 绑定参考文档..."
    cat > "${OUTPUT_DIR}/iam/${BUCKET_NAME}_iam_reference.txt" <<EOF
Bucket: ${BUCKET_NAME}
导出时间: ${TIMESTAMP}
工程: ${PROJECT_A}

=== IAM Policy 绑定 ===
EOF
    
    # 解析并格式化 IAM Policy
    gsutil iam get "gs://${BUCKET_NAME}" | \
        jq -r '.bindings[] | "角色: \(.role)\n成员: \(.members | join(", "))\n"' \
        >> "${OUTPUT_DIR}/iam/${BUCKET_NAME}_iam_reference.txt"
    
    echo "  ✓ ${BUCKET_NAME} 配置导出完成"
    echo ""
done

# 生成汇总报告
cat > "${OUTPUT_DIR}/export_summary_${TIMESTAMP}.txt" <<EOF
=== 配置导出汇总 ===
工程: ${PROJECT_A}
导出时间: ${TIMESTAMP}
导出目录: ${OUTPUT_DIR}

Lifecycle 配置文件: ${OUTPUT_DIR}/lifecycle/
IAM Policy 文件: ${OUTPUT_DIR}/iam/

下一步操作:
1. 检查 lifecycle/*.json 文件
2. 参考 iam/*_reference.txt 文件调整 B 工程的 IAM 绑定
3. 使用 apply_bucket_configs.sh 应用到 B 工程
EOF

echo "=== 导出完成 ==="
cat "${OUTPUT_DIR}/export_summary_${TIMESTAMP}.txt"
```

#### 2. 应用配置到 B 工程

```bash
#!/bin/bash
# apply_bucket_configs.sh - 应用配置到 B 工程

set -e

# 配置变量
PROJECT_B="your-project-b-id"
INPUT_DIR="./bucket_configs"
LOG_FILE="./apply_log_$(date +%Y%m%d_%H%M%S).txt"

# 设置当前工程
gcloud config set project "${PROJECT_B}"

echo "=== 开始应用配置到 ${PROJECT_B} ===" | tee -a "${LOG_FILE}"

# 检查输入目录
if [ ! -d "${INPUT_DIR}/lifecycle" ]; then
    echo "错误: 找不到 lifecycle 配置目录" | tee -a "${LOG_FILE}"
    exit 1
fi

# 列出 B 工程的 Buckets
BUCKETS_B=$(gsutil ls | sed 's|gs://||g' | sed 's|/||g')

echo "B 工程现有 Buckets:" | tee -a "${LOG_FILE}"
echo "${BUCKETS_B}" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

# 交互式选择模式
read -p "选择应用模式 [1=全部应用, 2=选择性应用]: " MODE

if [ "${MODE}" = "1" ]; then
    # 全部应用模式
    for BUCKET_NAME in ${BUCKETS_B}; do
        echo "处理 Bucket: ${BUCKET_NAME}" | tee -a "${LOG_FILE}"
        
        LIFECYCLE_FILE="${INPUT_DIR}/lifecycle/${BUCKET_NAME}_lifecycle.json"
        
        if [ -f "${LIFECYCLE_FILE}" ]; then
            # 检查是否有有效的 lifecycle 配置
            if [ $(cat "${LIFECYCLE_FILE}" | jq '. | length') -gt 0 ]; then
                echo "  - 应用 Lifecycle 配置..." | tee -a "${LOG_FILE}"
                if gsutil lifecycle set "${LIFECYCLE_FILE}" "gs://${BUCKET_NAME}"; then
                    echo "    ✓ Lifecycle 配置已应用" | tee -a "${LOG_FILE}"
                else
                    echo "    ✗ Lifecycle 配置应用失败" | tee -a "${LOG_FILE}"
                fi
            else
                echo "  - 跳过: 无 Lifecycle 配置" | tee -a "${LOG_FILE}"
            fi
        else
            echo "  - 警告: 未找到对应的 Lifecycle 配置文件" | tee -a "${LOG_FILE}"
        fi
        
        echo "" | tee -a "${LOG_FILE}"
    done
else
    # 选择性应用模式
    echo "可用的 Lifecycle 配置文件:"
    ls -1 "${INPUT_DIR}/lifecycle/"
    echo ""
    
    for BUCKET_NAME in ${BUCKETS_B}; do
        read -p "是否应用配置到 ${BUCKET_NAME}? [y/N]: " APPLY
        
        if [ "${APPLY}" = "y" ] || [ "${APPLY}" = "Y" ]; then
            LIFECYCLE_FILE="${INPUT_DIR}/lifecycle/${BUCKET_NAME}_lifecycle.json"
            
            if [ -f "${LIFECYCLE_FILE}" ]; then
                echo "  - 应用 Lifecycle 配置..." | tee -a "${LOG_FILE}"
                gsutil lifecycle set "${LIFECYCLE_FILE}" "gs://${BUCKET_NAME}" | tee -a "${LOG_FILE}"
            else
                echo "  - 错误: 未找到配置文件" | tee -a "${LOG_FILE}"
            fi
        fi
        echo "" | tee -a "${LOG_FILE}"
    done
fi

echo "=== 应用完成 ===" | tee -a "${LOG_FILE}"
echo "日志已保存到: ${LOG_FILE}"
```

#### 3. IAM Policy 批量应用脚本（可选）

```bash
#!/bin/bash
# apply_iam_template.sh - 使用模板应用 IAM Policy

set -e

PROJECT_B="your-project-b-id"
SERVICE_ACCOUNT_B="your-service-account@${PROJECT_B}.iam.gserviceaccount.com"

# 设置当前工程
gcloud config set project "${PROJECT_B}"

# 创建 IAM Policy 模板
create_iam_template() {
    local BUCKET_NAME=$1
    local TEMPLATE_FILE="./iam_template_${BUCKET_NAME}.json"
    
    cat > "${TEMPLATE_FILE}" <<EOF
{
  "bindings": [
    {
      "role": "roles/storage.objectViewer",
      "members": [
        "serviceAccount:${SERVICE_ACCOUNT_B}"
      ]
    },
    {
      "role": "roles/storage.objectCreator",
      "members": [
        "serviceAccount:${SERVICE_ACCOUNT_B}"
      ]
    }
  ]
}
EOF
    
    echo "${TEMPLATE_FILE}"
}

# 应用 IAM Policy
apply_iam_policy() {
    local BUCKET_NAME=$1
    local TEMPLATE_FILE=$2
    
    echo "应用 IAM Policy 到: gs://${BUCKET_NAME}"
    gsutil iam set "${TEMPLATE_FILE}" "gs://${BUCKET_NAME}"
}

# 主流程
read -p "输入 Bucket 名称（留空处理所有 Buckets）: " TARGET_BUCKET

if [ -z "${TARGET_BUCKET}" ]; then
    # 处理所有 Buckets
    BUCKETS=$(gsutil ls | sed 's|gs://||g' | sed 's|/||g')
    for BUCKET in ${BUCKETS}; do
        TEMPLATE=$(create_iam_template "${BUCKET}")
        apply_iam_policy "${BUCKET}" "${TEMPLATE}"
        rm -f "${TEMPLATE}"
    done
else
    # 处理指定 Bucket
    TEMPLATE=$(create_iam_template "${TARGET_BUCKET}")
    apply_iam_policy "${TARGET_BUCKET}" "${TEMPLATE}"
    rm -f "${TEMPLATE}"
fi

echo "✓ IAM Policy 应用完成"
```

### 配置文件示例

#### Lifecycle 配置示例

```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 90,
          "matchesPrefix": ["logs/", "temp/"]
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 30,
          "matchesPrefix": ["archive/"]
        }
      }
    ]
  }
}
```

#### IAM Policy 参考文档格式

```
Bucket: my-bucket-name
导出时间: 20250117_143000
工程: project-a

=== IAM Policy 绑定 ===
角色: roles/storage.objectAdmin
成员: serviceAccount:sa-admin@project-a.iam.gserviceaccount.com

角色: roles/storage.objectViewer
成员: serviceAccount:sa-reader@project-a.iam.gserviceaccount.com, user:viewer@example.com

角色: roles/storage.legacyBucketOwner
成员: projectEditor:project-a, projectOwner:project-a
```

## 使用流程

### 步骤说明

```mermaid
graph LR
    A[修改脚本变量] --> B[执行导出脚本]
    B --> C[检查导出文件]
    C --> D[调整 IAM 参考]
    D --> E[执行应用脚本]
    E --> F[验证配置]
```

### 详细操作

1. **准备阶段**
    
    ```bash
    # 安装必要工具
    sudo apt-get install jq  # Debian/Ubuntu
    # 或
    brew install jq  # macOS
    
    # 验证 gcloud 认证
    gcloud auth list
    gcloud auth application-default login
    ```
    
2. **修改脚本变量**
    
    ```bash
    # 在 export_bucket_configs.sh 中修改
    PROJECT_A="your-actual-project-a-id"
    
    # 在 apply_bucket_configs.sh 中修改
    PROJECT_B="your-actual-project-b-id"
    ```
    
3. **执行导出**
    
    ```bash
    chmod +x export_bucket_configs.sh
    ./export_bucket_configs.sh
    ```
    
4. **检查导出结果**
    
    ```bash
    # 查看目录结构
    tree bucket_configs/
    
    # 检查 Lifecycle 配置
    cat bucket_configs/lifecycle/my-bucket_lifecycle.json
    
    # 查看 IAM 参考文档
    cat bucket_configs/iam/my-bucket_iam_reference.txt
    ```
    
5. **应用配置到 B 工程**
    
    ```bash
    chmod +x apply_bucket_configs.sh
    ./apply_bucket_configs.sh
    ```
    
6. **手动配置 IAM（如需要）**
    
    ```bash
    # 根据参考文档手动设置
    gsutil iam ch \
      serviceAccount:sa-b@project-b.iam.gserviceaccount.com:objectAdmin \
      gs://my-bucket-in-project-b
    ```
    

## 验证配置

### 验证脚本

```bash
#!/bin/bash
# verify_bucket_configs.sh - 验证配置应用结果

set -e

PROJECT_B="your-project-b-id"
gcloud config set project "${PROJECT_B}"

echo "=== 验证 Bucket 配置 ==="

BUCKETS=$(gsutil ls | sed 's|gs://||g' | sed 's|/||g')

for BUCKET in ${BUCKETS}; do
    echo ""
    echo "Bucket: ${BUCKET}"
    echo "----------------------------------------"
    
    # 检查 Lifecycle
    echo "Lifecycle 规则:"
    gsutil lifecycle get "gs://${BUCKET}" 2>/dev/null || echo "  无配置"
    
    # 检查 IAM
    echo ""
    echo "IAM 绑定:"
    gsutil iam get "gs://${BUCKET}" | jq -r '.bindings[] | "  \(.role): \(.members | join(", "))"'
    
    echo "----------------------------------------"
done
```

## 注意事项

### ⚠️ 重要提醒

1. **权限要求**
    
    - 需要 A 工程的 `storage.buckets.getIamPolicy` 权限
    - 需要 B 工程的 `storage.buckets.setIamPolicy` 权限
    - 建议使用 `Storage Admin` 角色
2. **IAM Policy 调整**
    
    - Service Account 名称需要手动替换
    - Project Editor/Owner 绑定需要更新为 B 工程
    - 检查是否有跨工程的成员绑定
3. **Lifecycle 兼容性**
    
    - 确认 B 工程 Buckets 的存储类别支持
    - 验证文件前缀匹配规则是否适用
    - 测试规则不会误删重要数据
4. **执行建议**
    
    - 先在测试 Bucket 上验证
    - 使用 `--dry-run` 模式（如工具支持）
    - 保留导出的配置文件作为备份
    - 记录所有配置变更

### 最佳实践

|实践项|说明|
|---|---|
|备份原配置|应用前导出 B 工程现有配置|
|分批执行|不要一次性处理所有 Buckets|
|监控日志|观察应用后的访问日志|
|定期审计|定期检查 IAM 绑定的合理性|
|文档化|记录配置标准和变更历史|

### 故障排除

```bash
# 如果导出失败
# 1. 检查权限
gcloud projects get-iam-policy ${PROJECT_A} \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"

# 2. 检查 gsutil 配置
gsutil version -l

# 3. 测试单个 Bucket 访问
gsutil ls -L gs://specific-bucket

# 如果应用失败
# 1. 验证 JSON 格式
jq . bucket_configs/lifecycle/my-bucket_lifecycle.json

# 2. 检查 Bucket 是否存在
gsutil ls gs://target-bucket

# 3. 手动测试应用
gsutil lifecycle set test-lifecycle.json gs://test-bucket
```

---

以上脚本和配置均为 Markdown 源码格式，可直接保存为 `.sh` 或 `.json` 文件使用。建议在正式环境执行前，先在测试环境验证整个流程。