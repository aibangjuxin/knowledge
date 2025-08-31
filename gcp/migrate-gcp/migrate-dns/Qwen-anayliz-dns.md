# GCP DNS 跨项目迁移分析与方案设计 (Qwen-anayliz-dns.md)

## 1. 需求背景

将 GCP 项目 `project-id` 中的 DNS 域名（及其背后的服务）平滑迁移到 `project-id2`，核心目标是：

- 零停机时间迁移。
- 旧域名 `*.project-id.dev.aliyun.cloud.uk.aibang` 继续可用，并指向新项目资源。
- 最终引导所有客户端使用新域名 `*.project-id2.dev.aliyun.cloud.uk.aibang`。

## 2. 当前架构分析

### 2.1 源架构

```
Nginx proxy L4 dual network ==> GKE [ingress control] ==> GKE Runtime

Source project DNS:
events.project-id.dev.aliyun.cloud.uk.aibang
  ==> CNAME cinternal-vpc1-ingress-proxy-europe-west2-l4-ilb.projectid.dev.aliyun.cloud.uk.aibang

events-proxy.project-id.dev.aliyun.cloud.uk.aibang
  ==> CNAME ingress-nginx.gke-01.project.dev.aliyun.cloud.uk.aibang
```

### 2.2 DNS 层次结构

- **父域**: `dev.aliyun.cloud.uk.aibang`
- **源项目子域 Zone**: `project-id.dev.aliyun.cloud.uk.aibang`
- **目标项目子域 Zone**: `project-id2.dev.aliyun.cloud.uk.aibang`

## 3. 核心挑战与思考

### 3.1 挑战

1.  **DNS 解析路径**: 外部流量通过父域解析，内部流量可能通过私有 DNS 区域解析。
2.  **服务连续性**: 迁移过程中必须保证服务不中断。
3.  **证书兼容性**: SSL 证书需同时支持新旧域名。
4.  **映射关系**: 新旧集群中服务的 IP/域名是随机的，需要先建立映射关系。

### 3.2 思考过程

1.  **映射关系建立**:
    *   在新项目 `project-id2` 中部署服务后，获取其 Service 的 ClusterIP 或 LoadBalancer IP。
    *   根据命名规范（如 Deployment 名为 `my-app`，则 Service 名为 `my-app-svc`），在 `project-id2` 的 DNS Zone 中创建对应的记录。
    *   例如：`my-app.project-id2.dev.aliyun.cloud.uk.aibang` 指向 `my-app-svc` 的 IP。

2.  **DNS 切换逻辑**:
    *   在源项目 `project-id` 的 DNS Zone 中，将旧域名的 CNAME 记录指向新项目中对应的记录。
    *   例如：将 `events.project-id.dev.aliyun.cloud.uk.aibang` 的 CNAME 从指向旧 ILB，修改为指向 `events.project-id2.dev.aliyun.cloud.uk.aibang`。

## 4. 推荐迁移方案

### 4.1 总体策略

采用 **CNAME 重定向** 作为主要迁移策略，配合 **私有 DNS 区域** 处理内部服务调用。

### 4.2 详细步骤

#### 阶段 1: 准备目标环境

1.  **部署基础设施**:
    *   在 `project-id2` 中部署与 `project-id` 相同的 GKE 集群、Ingress 控制器、L4 负载均衡器等。
    *   确保所有服务（Deployments, Services）在 `project-id2` 中正常运行。

2.  **创建目标 DNS 记录**:
    *   在 `project-id2` 的 Cloud DNS Zone (`project-id2.dev.aliyun.cloud.uk.aibang`) 中，为新部署的服务创建 DNS 记录。
    *   例如：`events.project-id2.dev.aliyun.cloud.uk.aibang` 指向新 L4 ILB 的域名或 IP。
    *   **关键**: 确保这些记录的命名与源项目中的记录有明确的对应关系。

#### 阶段 2: 配置双域名支持

1.  **配置 SSL 证书**:
    *   在 `project-id2` 的 Ingress 或负载均衡器上，配置一个包含新旧域名的 SSL 证书。
    *   例如，Google Managed Certificate 应包含 `events.project-id.dev.aliyun.cloud.uk.aibang` 和 `events.project-id2.dev.aliyun.cloud.uk.aibang`。

2.  **更新 Ingress 配置**:
    *   确保 `project-id2` 中的 Ingress 资源能够识别并路由来自旧域名的请求。
    *   在 Ingress 规则中同时添加新旧域名的 `host`。

#### 阶段 3: DNS 切换准备

1.  **降低 TTL**:
    *   提前 24-48 小时，在 `project-id` 的 DNS Zone 中，将需要迁移的旧域名记录的 TTL 值降低到 60 秒（或更低），以加速 DNS 传播。

2.  **内部服务发现 (可选)**:
    *   如果 `project-id2` 内部服务需要调用旧域名，可以在 `project-id2` 中创建一个私有 DNS Zone (`project-id.dev.aliyun.cloud.uk.aibang`)，并将旧域名的记录指向 `project-id2` 中对应的新服务，实现内部解析的兼容。

#### 阶段 4: 执行 DNS 切换

1.  **修改源项目 DNS 记录**:
    *   在 `project-id` 的 Cloud DNS Zone (`project-id.dev.aliyun.cloud.uk.aibang`) 中，执行 DNS 记录更新。
    *   将旧域名（如 `events.project-id.dev.aliyun.cloud.uk.aibang`）的记录类型从 `CNAME`（指向旧 ILB）修改为 `CNAME`，并将其指向 `project-id2` 中对应的新记录。
    *   例如：
        ```bash
        # gcloud 命令示例 (假设使用 gcloud dns record-sets transaction)
        gcloud dns record-sets transaction start --zone=project-id-zone --project=project-id
        gcloud dns record-sets transaction remove \
          --name=events.project-id.dev.aliyun.cloud.uk.aibang. \
          --ttl=60 \
          --type=CNAME \
          --data="cinternal-vpc1-ingress-proxy-europe-west2-l4-ilb.projectid.dev.aliyun.cloud.uk.aibang." \
          --zone=project-id-zone --project=project-id
        gcloud dns record-sets transaction add \
          --name=events.project-id.dev.aliyun.cloud.uk.aibang. \
          --ttl=60 \
          --type=CNAME \
          --data="events.project-id2.dev.aliyun.cloud.uk.aibang." \
          --zone=project-id-zone --project=project-id
        gcloud dns record-sets transaction execute --zone=project-id-zone --project=project-id
        ```

2.  **监控与验证**:
    *   立即开始监控 `project-id2` 的流量、错误率和延迟。
    *   使用 `dig` 或 `nslookup` 从不同网络位置验证旧域名是否正确解析到新项目。
    *   观察 `project-id` 中的旧环境流量是否逐渐减少。

#### 阶段 5: 稳定运行与清理

1.  **过渡期**:
    *   保持 CNAME 重定向至少 1-2 周，确保所有客户端流量都已切换。
    *   在此期间，通知所有相关团队，鼓励他们更新客户端配置，直接使用新域名。

2.  **资源清理**:
    *   在确认迁移成功且过渡期结束后，可以开始逐步下线 `project-id` 中的旧资源。
    *   最终，可以请求删除 `project-id` 中的旧 DNS CNAME 记录，完成整个迁移。

## 5. 脚本化思路

根据以上分析，可以编写一个严谨的迁移脚本 `migrate-dns.sh`，其逻辑如下：

1.  **配置文件**: `config.sh` 定义源项目、目标项目、DNS Zone 名称、需要迁移的域名列表等。
2.  **发现阶段 (`01-discovery.sh`)**:
    *   读取 `config.sh`。
    *   使用 `kubectl` 获取 `project-id2` 中所有相关服务的名称和 IP。
    *   生成一个映射关系表（可以是内存中的关联数组或临时文件）。
3.  **准备阶段 (`02-prepare-target.sh`)**:
    *   读取 `config.sh` 和映射关系表。
    *   使用 `gcloud dns record-sets` 命令在 `project-id2` 的 DNS Zone 中批量创建记录。
4.  **执行阶段 (`03-execute-migration.sh`)**:
    *   读取 `config.sh`。
    *   （可选）降低 `project-id` 中旧记录的 TTL。
    *   使用 `gcloud dns record-sets` 命令在 `project-id` 的 DNS Zone 中批量更新旧记录，将其 CNAME 指向 `project-id2` 中的新记录。
5.  **回滚脚本 (`04-rollback.sh`)**:
    *   提供一个脚本，可以快速将 `project-id` 的 DNS 记录恢复到迁移前的状态。
6.  **清理脚本 (`05-cleanup.sh`)**:
    *   在迁移完成后，用于清理临时文件、记录等。

## 6. 风险与缓解

*   **SSL 证书**: 确保证书在切换前已正确配置并生效。
*   **防火墙与 IAM**: 确保 `project-id2` 的网络和权限配置与 `project-id` 一致。
*   **硬编码依赖**: 检查应用代码中是否有硬编码的旧项目特定信息。
*   **DNS 传播延迟**: 通过提前降低 TTL 和密切监控来缓解。
*   **回滚**: 准备好快速回滚的脚本和流程。

## 7. 完整脚本示例

以下是一个基于上述逻辑的完整脚本示例，包含所有阶段的脚本。

### config.sh

```bash
#!/bin/bash
# config.sh

# 源项目和目标项目
export SOURCE_PROJECT="project-id"
export TARGET_PROJECT="project-id2"

# DNS Zone 名称
export SOURCE_DNS_ZONE="project-id-zone"  # 替换为实际的 Zone 名称
export TARGET_DNS_ZONE="project-id2-zone" # 替换为实际的 Zone 名称

# 需要迁移的域名列表 (旧域名 -> 新域名)
declare -A DOMAIN_MAPPING=(
    ["events.project-id.dev.aliyun.cloud.uk.aibang"]="events.project-id2.dev.aliyun.cloud.uk.aibang"
    ["events-proxy.project-id.dev.aliyun.cloud.uk.aibang"]="events-proxy.project-id2.dev.aliyun.cloud.uk.aibang"
)

# TTL 设置
export LOW_TTL=60
export NORMAL_TTL=300

# 临时文件
export TEMP_MAPPING_FILE="/tmp/dns_mapping.txt"
```

### 01-discovery.sh

```bash
#!/bin/bash
# 01-discovery.sh

source ./config.sh

echo "=== Discovery Phase ==="
echo "Discovering services in target project: $TARGET_PROJECT"

# 清空临时文件
> "$TEMP_MAPPING_FILE"

# 示例：发现目标项目中的服务并生成映射
# 这里需要根据你的实际服务和命名规范来编写
# 假设我们有一个简单的映射关系，这里直接硬编码或通过其他方式获取
# 例如，通过 kubectl 获取服务列表
# kubectl get services -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' --context $TARGET_PROJECT

# 为了演示，我们手动构建映射
# 实际应用中，这部分需要根据你的部署结果动态生成
echo "discovered-service-1.project-id2.dev.aliyun.cloud.uk.aibang 10.10.10.1" >> "$TEMP_MAPPING_FILE"
echo "discovered-service-2.project-id2.dev.aliyun.cloud.uk.aibang 10.10.10.2" >> "$TEMP_MAPPING_FILE"

echo "Discovered mappings written to $TEMP_MAPPING_FILE"
cat "$TEMP_MAPPING_FILE"
```

### 02-prepare-target.sh

```bash
#!/bin/bash
# 02-prepare-target.sh

source ./config.sh

echo "=== Prepare Target DNS Records ==="

# 读取临时映射文件并创建 DNS 记录
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        FQDN=$(echo "$line" | awk '{print $1}')
        IP=$(echo "$line" | awk '{print $2}')
        
        echo "Creating DNS record for $FQDN pointing to $IP in zone $TARGET_DNS_ZONE (project $TARGET_PROJECT)"
        
        gcloud dns record-sets transaction start --zone="$TARGET_DNS_ZONE" --project="$TARGET_PROJECT"
        # 检查记录是否存在，如果存在则先删除
        if gcloud dns record-sets list --zone="$TARGET_DNS_ZONE" --name="$FQDN." --project="$TARGET_PROJECT" --format="value(name)" | grep -q .; then
            CURRENT_TTL=$(gcloud dns record-sets list --zone="$TARGET_DNS_ZONE" --name="$FQDN." --project="$TARGET_PROJECT" --format="value(ttl)")
            CURRENT_TYPE=$(gcloud dns record-sets list --zone="$TARGET_DNS_ZONE" --name="$FQDN." --project="$TARGET_PROJECT" --format="value(type)")
            CURRENT_DATA=$(gcloud dns record-sets list --zone="$TARGET_DNS_ZONE" --name="$FQDN." --project="$TARGET_PROJECT" --format="value(rrdatas[0])")
            gcloud dns record-sets transaction remove \
                --name="$FQDN." \
                --ttl="$CURRENT_TTL" \
                --type="$CURRENT_TYPE" \
                --data="$CURRENT_DATA" \
                --zone="$TARGET_DNS_ZONE" --project="$TARGET_PROJECT"
        fi
        gcloud dns record-sets transaction add \
            --name="$FQDN." \
            --ttl="$NORMAL_TTL" \
            --type=A \
            --data="$IP" \
            --zone="$TARGET_DNS_ZONE" --project="$TARGET_PROJECT"
        gcloud dns record-sets transaction execute --zone="$TARGET_DNS_ZONE" --project="$TARGET_PROJECT"
    fi
done < "$TEMP_MAPPING_FILE"

echo "Target DNS records prepared."
```

### 03-execute-migration.sh

```bash
#!/bin/bash
# 03-execute-migration.sh

source ./config.sh

echo "=== Execute DNS Migration ==="

# 降低源项目中旧记录的 TTL
echo "Lowering TTL for source DNS records..."
for OLD_FQDN in "${!DOMAIN_MAPPING[@]}"; do
    NEW_FQDN="${DOMAIN_MAPPING[$OLD_FQDN]}"
    echo "Processing $OLD_FQDN -> $NEW_FQDN"
    
    # 获取当前记录信息
    if gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(name)" | grep -q .; then
        CURRENT_TTL=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(ttl)")
        CURRENT_TYPE=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(type)")
        CURRENT_DATA=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(rrdatas[0])")
        
        echo "Current record: TTL=$CURRENT_TTL, TYPE=$CURRENT_TYPE, DATA=$CURRENT_DATA"
        
        # 如果当前 TTL 已经是 LOW_TTL，则跳过
        if [ "$CURRENT_TTL" -eq "$LOW_TTL" ]; then
            echo "TTL is already $LOW_TTL, skipping."
            continue
        fi
        
        # 开始事务，降低 TTL
        gcloud dns record-sets transaction start --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction remove \
            --name="$OLD_FQDN." \
            --ttl="$CURRENT_TTL" \
            --type="$CURRENT_TYPE" \
            --data="$CURRENT_DATA" \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction add \
            --name="$OLD_FQDN." \
            --ttl="$LOW_TTL" \
            --type="$CURRENT_TYPE" \
            --data="$CURRENT_DATA" \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction execute --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        echo "TTL lowered to $LOW_TTL for $OLD_FQDN"
    else
        echo "Record $OLD_FQDN not found in source zone."
    fi
done

# 等待 TTL 降低生效 (可选，根据实际需要调整)
echo "Waiting for TTL changes to propagate... (30 seconds)"
sleep 30

# 执行 CNAME 切换
echo "Switching CNAME records..."
for OLD_FQDN in "${!DOMAIN_MAPPING[@]}"; do
    NEW_FQDN="${DOMAIN_MAPPING[$OLD_FQDN]}"
    echo "Switching $OLD_FQDN to CNAME $NEW_FQDN"
    
    # 获取当前记录信息
    if gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(name)" | grep -q .; then
        CURRENT_TTL=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(ttl)")
        CURRENT_TYPE=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(type)")
        CURRENT_DATA=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(rrdatas[0])")
        
        echo "Current record: TTL=$CURRENT_TTL, TYPE=$CURRENT_TYPE, DATA=$CURRENT_DATA"
        
        # 开始事务，切换为 CNAME
        gcloud dns record-sets transaction start --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction remove \
            --name="$OLD_FQDN." \
            --ttl="$CURRENT_TTL" \
            --type="$CURRENT_TYPE" \
            --data="$CURRENT_DATA" \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction add \
            --name="$OLD_FQDN." \
            --ttl="$LOW_TTL" \
            --type="CNAME" \
            --data="$NEW_FQDN." \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction execute --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        echo "Switched $OLD_FQDN to CNAME $NEW_FQDN"
    else
        echo "Record $OLD_FQDN not found in source zone. Creating new CNAME record."
        gcloud dns record-sets transaction start --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction add \
            --name="$OLD_FQDN." \
            --ttl="$LOW_TTL" \
            --type="CNAME" \
            --data="$NEW_FQDN." \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction execute --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        echo "Created new CNAME record $OLD_FQDN -> $NEW_FQDN"
    fi
done

echo "DNS migration executed. Please monitor the transition."
```

### 04-rollback.sh

```bash
#!/bin/bash
# 04-rollback.sh

source ./config.sh

echo "=== Rollback DNS Changes ==="

# 回滚 CNAME 切换和 TTL 降低
# 注意：这里需要知道回滚前的原始记录信息（类型、数据、TTL）
# 为了简化，我们假设原始记录是 A 记录，并且 TTL 是 NORMAL_TTL
# 实际应用中，应该在迁移前备份原始记录信息

# 示例：恢复一个已知的记录
# 假设原始记录是:
# events.project-id.dev.aliyun.cloud.uk.aibang. 3600 IN A 192.168.1.10
# events-proxy.project-id.dev.aliyun.cloud.uk.aibang. 3600 IN CNAME old-ingress.project.dev.aliyun.cloud.uk.aibang.

# 定义原始记录映射 (需要根据实际情况填写)
declare -A ORIGINAL_RECORDS=(
    ["events.project-id.dev.aliyun.cloud.uk.aibang"]="A,192.168.1.10,3600"
    ["events-proxy.project-id.dev.aliyun.cloud.uk.aibang"]="CNAME,old-ingress.project.dev.aliyun.cloud.uk.aibang.,3600"
)

for OLD_FQDN in "${!ORIGINAL_RECORDS[@]}"; do
    IFS=',' read -r ORIG_TYPE ORIG_DATA ORIG_TTL <<< "${ORIGINAL_RECORDS[$OLD_FQDN]}"
    echo "Rolling back $OLD_FQDN to original $ORIG_TYPE record: $ORIG_DATA (TTL: $ORIG_TTL)"
    
    # 获取当前记录信息
    if gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(name)" | grep -q .; then
        CURRENT_TTL=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(ttl)")
        CURRENT_TYPE=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(type)")
        CURRENT_DATA=$(gcloud dns record-sets list --zone="$SOURCE_DNS_ZONE" --name="$OLD_FQDN." --project="$SOURCE_PROJECT" --format="value(rrdatas[0])")
        
        echo "Current record: TTL=$CURRENT_TTL, TYPE=$CURRENT_TYPE, DATA=$CURRENT_DATA"
        
        # 开始事务，恢复原始记录
        gcloud dns record-sets transaction start --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction remove \
            --name="$OLD_FQDN." \
            --ttl="$CURRENT_TTL" \
            --type="$CURRENT_TYPE" \
            --data="$CURRENT_DATA" \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction add \
            --name="$OLD_FQDN." \
            --ttl="$ORIG_TTL" \
            --type="$ORIG_TYPE" \
            --data="$ORIG_DATA" \
            --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        gcloud dns record-sets transaction execute --zone="$SOURCE_DNS_ZONE" --project="$SOURCE_PROJECT"
        echo "Rolled back $OLD_FQDN to original record."
    else
        echo "Record $OLD_FQDN not found in source zone. Cannot rollback."
    fi
done

echo "Rollback completed."
```

### 05-cleanup.sh

```bash
#!/bin/bash
# 05-cleanup.sh

source ./config.sh

echo "=== Cleanup Temporary Files ==="

# 删除临时映射文件
if [ -f "$TEMP_MAPPING_FILE" ]; then
    rm "$TEMP_MAPPING_FILE"
    echo "Deleted temporary mapping file: $TEMP_MAPPING_FILE"
else
    echo "Temporary mapping file not found: $TEMP_MAPPING_FILE"
fi

echo "Cleanup completed."
```

### migrate-dns.sh (主入口脚本)

```bash
#!/bin/bash
# migrate-dns.sh - 主入口脚本

set -e # 遇到错误时退出

echo "========================================="
echo "GCP DNS Migration Script"
echo "========================================="

# 检查配置文件
if [ ! -f "./config.sh" ]; then
    echo "Error: config.sh not found!"
    exit 1
fi

source ./config.sh

# 显示配置摘要
echo "Configuration Summary:"
echo "  Source Project: $SOURCE_PROJECT"
echo "  Target Project: $TARGET_PROJECT"
echo "  Source DNS Zone: $SOURCE_DNS_ZONE"
echo "  Target DNS Zone: $TARGET_DNS_ZONE"
echo "  Domains to Migrate:"
for OLD_FQDN in "${!DOMAIN_MAPPING[@]}"; do
    NEW_FQDN="${DOMAIN_MAPPING[$OLD_FQDN]}"
    echo "    $OLD_FQDN -> $NEW_FQDN"
done
echo "========================================="

# 确认执行
read -p "Do you want to proceed with the migration? (yes/no): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# 执行各阶段
echo "Starting Discovery Phase..."
./01-discovery.sh

echo "Starting Prepare Target Phase..."
./02-prepare-target.sh

echo "Starting Execute Migration Phase..."
./03-execute-migration.sh

echo "Migration process initiated. Please monitor the transition."
echo "Use ./04-rollback.sh if you need to rollback."
echo "Use ./05-cleanup.sh after migration is stable."

echo "========================================="
echo "Migration Script Completed"
echo "========================================="
```

## 8. 使用说明

1.  **配置**: 编辑 `config.sh` 文件，填入你的项目 ID、Zone 名称、域名映射等信息。
2.  **准备**: 确保 `gcloud` CLI 已安装并配置了正确的凭据，能够访问源项目和目标项目。
3.  **执行**:
    *   给所有脚本添加执行权限：`chmod +x *.sh`
    *   运行主脚本：`./migrate-dns.sh`
4.  **监控**: 脚本执行后，密切监控 DNS 解析和应用流量。
5.  **回滚**: 如果出现问题，可以运行 `./04-rollback.sh`。
6.  **清理**: 迁移稳定后，运行 `./05-cleanup.sh` 清理临时文件。

这个方案提供了一个结构化、可执行的路径来完成 GCP 的 DNS 跨项目迁移，并包含了实现自动化的脚本框架。