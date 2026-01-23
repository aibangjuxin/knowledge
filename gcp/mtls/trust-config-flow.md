# GCP Trust Config 证书验证流程详解

## 概述

本文档详细说明 GCP Certificate Manager Trust Config 在 GLB mTLS 认证中的作用，以及当用户更新客户端证书时，Trust Config 需要如何调整。

## 核心概念

### Trust Config 的作用

Trust Config 是 GCP Certificate Manager 中用于定义**受信任的 CA (Certificate Authority)** 的配置资源。在 mTLS 场景下，GLB 使用 Trust Config 来验证客户端证书的有效性。

```mermaid
graph LR
    A["客户端证书"] --> B["由某个 CA 签发"]
    C["Trust Config"] --> D["定义受信任的 CA 列表"]
    B -.->|"是否在"| D
    D -->|"是"| E["GLB 信任此证书"]
    D -->|"否"| F["GLB 拒绝连接"]
    
    style C fill:#e1f5fe,stroke:#01579b
    style E fill:#e8f5e9,stroke:#2e7d32
    style F fill:#ffebee,stroke:#c62828
```

### Trust Config 组成部分

```mermaid
graph TD
    A["Trust Config"] --> B["Trust Stores"]
    B --> C["Trust Anchors\n(根 CA)"]
    B --> D["Intermediate CAs\n(中间 CA)"]
    B --> E["Allowlisted Certificates\n(允许的特定证书)"]
    
    C --> C1["用于验证证书链的根"]
    D --> D1["可选：中间层级的 CA"]
    E --> E1["可选：直接信任的客户端证书"]
    
    style A fill:#fff3e0,stroke:#e65100
    style C fill:#e8f5e9,stroke:#2e7d32
    style D fill:#e1f5fe,stroke:#01579b
    style E fill:#f3e5f5,stroke:#6a1b9a
```

## 完整 mTLS 验证流程

### 流程图

```mermaid
sequenceDiagram
    participant Client as 客户端
    participant GLB as GCP GLB
    participant TC as Trust Config
    participant Backend as 后端服务
    
    Note over Client,Backend: TLS 握手开始
    
    Client->>GLB: 1. Client Hello (发起 HTTPS 连接)
    GLB->>Client: 2. Server Hello + 服务器证书
    GLB->>Client: 3. Certificate Request (要求客户端证书)
    
    Note over Client: 客户端准备证书
    Client->>GLB: 4. Client Certificate + Certificate Chain
    
    Note over GLB,TC: 证书验证阶段
    GLB->>TC: 5. 获取 Trust Anchors 和 Intermediate CAs
    TC-->>GLB: 6. 返回受信任的 CA 列表
    
    GLB->>GLB: 7. 验证证书链
    Note over GLB: a) 证书格式是否正确<br/>b) 证书是否在有效期内<br/>c) 证书链是否完整<br/>d) 签名是否有效
    
    GLB->>TC: 8. 检查签发者 CA
    TC-->>GLB: 9. CA 是否在 Trust Anchors 中
    
    alt 证书验证成功
        GLB->>GLB: 10. 验证通过
        Note over GLB: TLS 握手完成
        GLB->>Backend: 11. 转发请求到后端
        Backend-->>GLB: 12. 返回响应
        GLB-->>Client: 13. 返回响应
    else 证书验证失败
        GLB->>GLB: 10. 验证失败
        GLB-->>Client: 11. 拒绝连接 (403/401)
        Note over Client: 连接被拒绝
    end
    
    Note over Client,Backend: 连接建立或被拒绝
```

### 详细验证步骤

```mermaid
graph TD
    Start["客户端发送证书"] --> Step1["提取证书链"]
    Step1 --> Step2["验证证书格式"]
    
    Step2 --> Check1{"格式是否有效?"}
    Check1 -->|否| Reject1["拒绝连接"]
    Check1 -->|是| Step3["检查有效期"]
    
    Step3 --> Check2{"是否在有效期内?"}
    Check2 -->|否| Reject2["拒绝连接\n(证书过期)"]
    Check2 -->|是| Step4["验证证书链完整性"]
    
    Step4 --> Check3{"证书链是否完整?"}
    Check3 -->|否| Reject3["拒绝连接\n(证书链不完整)"]
    Check3 -->|是| Step5["验证签名"]
    
    Step5 --> Check4{"签名是否有效?"}
    Check4 -->|否| Reject4["拒绝连接\n(签名无效)"]
    Check4 -->|是| Step6["检查 Trust Config"]
    
    Step6 --> TC["Trust Config<br/>Trust Anchors"]
    TC --> Check5{"签发 CA 是否<br/>在 Trust Anchors?"}
    
    Check5 -->|否| Reject5["拒绝连接\n(不受信任的 CA)"]
    Check5 -->|是| Check6{"证书是否在<br/>Allowlist?"}
    
    Check6 -->|配置了 Allowlist<br/>但不在其中| Reject6["拒绝连接\n(不在白名单)"]
    Check6 -->|在 Allowlist 或<br/>未配置 Allowlist| Accept["接受连接"]
    
    style Start fill:#e3f2fd,stroke:#1976d2
    style Accept fill:#e8f5e9,stroke:#2e7d32
    style Reject1 fill:#ffebee,stroke:#c62828
    style Reject2 fill:#ffebee,stroke:#c62828
    style Reject3 fill:#ffebee,stroke:#c62828
    style Reject4 fill:#ffebee,stroke:#c62828
    style Reject5 fill:#ffebee,stroke:#c62828
    style Reject6 fill:#ffebee,stroke:#c62828
    style TC fill:#fff3e0,stroke:#e65100
```

## 证书更新场景

### 场景 1: 客户端证书续期（CA 不变）

当客户端证书到期需要续期，但仍由**相同的 CA** 签发新证书时：

```mermaid
graph LR
    subgraph "更新前"
        A1["客户端旧证书"] --> A2["由 CA-1 签发"]
        A3["Trust Config"] --> A4["Trust Anchors: CA-1"]
    end
    
    subgraph "更新后"
        B1["客户端新证书"] --> B2["仍由 CA-1 签发"]
        B3["Trust Config"] --> B4["Trust Anchors: CA-1<br/>(无需修改)"]
    end
    
    A2 -.->|"CA 相同"| B2
    
    style B4 fill:#e8f5e9,stroke:#2e7d32
```

> [!NOTE]
> **结论**: Trust Config **无需修改**，只需客户端更新证书即可。

### 场景 2: 客户端证书迁移到新 CA

当客户端证书需要由**新的 CA** 签发时：

```mermaid
sequenceDiagram
    participant Admin as 管理员
    participant TC as Trust Config
    participant GLB as GLB
    participant OldClient as 旧客户端<br/>(CA-1 证书)
    participant NewClient as 新客户端<br/>(CA-2 证书)
    
    Note over Admin,NewClient: 准备阶段
    Admin->>TC: 1. 添加新 CA-2 到 Trust Anchors
    Note over TC: Trust Anchors: [CA-1, CA-2]
    TC-->>Admin: 2. 更新完成
    
    Note over Admin,NewClient: 过渡期（双 CA 并存）
    OldClient->>GLB: 3. 使用旧证书连接
    GLB->>TC: 4. 验证证书
    TC-->>GLB: 5. CA-1 在 Trust Anchors ✓
    GLB-->>OldClient: 6. 连接成功
    
    NewClient->>GLB: 7. 使用新证书连接
    GLB->>TC: 8. 验证证书
    TC-->>GLB: 9. CA-2 在 Trust Anchors ✓
    GLB-->>NewClient: 10. 连接成功
    
    Note over Admin,NewClient: 迁移完成后
    Admin->>Admin: 11. 确认所有客户端已迁移
    Admin->>TC: 12. 移除旧 CA-1
    Note over TC: Trust Anchors: [CA-2]
    TC-->>Admin: 13. 清理完成
```

#### 详细步骤

```mermaid
graph TD
    Start["开始迁移"] --> Step1["评估迁移影响"]
    
    Step1 --> Step2["准备新 CA 证书"]
    Step2 --> Step3["将新 CA 添加到 Trust Config"]
    
    Step3 --> Import["执行 gcloud 命令<br/>添加新 CA-2"]
    Import --> Verify1["验证 Trust Config<br/>包含 CA-1 和 CA-2"]
    
    Verify1 --> Step4["通知用户更新证书"]
    Step4 --> Step5["逐步迁移客户端"]
    
    Step5 --> Monitor["监控连接状态"]
    Monitor --> Check1{"是否有<br/>客户端使用旧证书?"}
    
    Check1 -->|是| Wait["继续等待"]
    Wait --> Monitor
    
    Check1 -->|否| Step6["所有客户端已迁移"]
    Step6 --> Step7["从 Trust Config<br/>移除旧 CA-1"]
    
    Step7 --> Verify2["验证 Trust Config<br/>只包含 CA-2"]
    Verify2 --> End["迁移完成"]
    
    style Start fill:#e3f2fd,stroke:#1976d2
    style Import fill:#fff3e0,stroke:#e65100
    style Monitor fill:#f3e5f5,stroke:#6a1b9a
    style End fill:#e8f5e9,stroke:#2e7d32
```

### 场景 3: CA 证书本身过期或更新

当 CA 根证书需要更新时：

```mermaid
graph TD
    Problem["CA 根证书即将过期"] --> Solution1["方案选择"]
    
    Solution1 --> Plan1["方案 1: CA 自签新根证书"]
    Solution1 --> Plan2["方案 2: 迁移到新 CA"]
    
    Plan1 --> P1S1["获取新的根证书"]
    P1S1 --> P1S2["添加新根证书到 Trust Config"]
    P1S2 --> P1S3["保留旧根证书\n(双根并存)"]
    P1S3 --> P1S4["客户端证书<br/>由新根重新签发"]
    P1S4 --> P1S5["验证新证书可用"]
    P1S5 --> P1S6["移除旧根证书"]
    
    Plan2 --> P2S1["选择新 CA 提供商"]
    P2S1 --> P2S2["获取新 CA 根证书"]
    P2S2 --> P2S3["添加到 Trust Config"]
    P2S3 --> P2S4["同场景 2 迁移流程"]
    
    style Problem fill:#ffebee,stroke:#c62828
    style P1S3 fill:#fff9c4,stroke:#f57f17
    style P1S6 fill:#e8f5e9,stroke:#2e7d32
```

## Trust Config 操作指南

### 查看当前 Trust Config

```bash
# 列出所有 Trust Configs
gcloud certificate-manager trust-configs list \
    --location=global

# 查看详细信息
gcloud certificate-manager trust-configs describe TRUST_CONFIG_NAME \
    --location=global \
    --format=yaml

# 使用验证脚本
./verify-trust-configs.sh
```

### 添加新的 CA 证书

```bash
# 方法 1: 创建新的 Trust Config（首次创建）
gcloud certificate-manager trust-configs import my-trust-config \
    --location=global \
    --trust-anchor=file=root-ca.pem,pem-certificate \
    --description="Trust config for client authentication"

# 方法 2: 更新现有 Trust Config（添加新 CA）
# 注意: import 命令会覆盖现有配置，需要包含所有 CA
gcloud certificate-manager trust-configs import my-trust-config \
    --location=global \
    --trust-anchor=file=old-ca.pem,pem-certificate \
    --trust-anchor=file=new-ca.pem,pem-certificate \
    --description="Updated trust config with new CA"
```

> [!WARNING]
> `gcloud certificate-manager trust-configs import` 命令会**完全替换**现有配置。
> 
> 更新时必须包含所有需要保留的旧 CA 证书！

### 添加中间 CA

```bash
gcloud certificate-manager trust-configs import my-trust-config \
    --location=global \
    --trust-anchor=file=root-ca.pem,pem-certificate \
    --intermediate-ca=file=intermediate-ca.pem,pem-certificate \
    --description="Trust config with intermediate CA"
```

### 完整更新流程示例

```mermaid
graph LR
    A["1. 准备工作"] --> B["2. 备份配置"]
    B --> C["3. 测试新证书"]
    C --> D["4. 更新 Trust Config"]
    D --> E["5. 验证配置"]
    E --> F["6. 监控连接"]
    
    style A fill:#e3f2fd,stroke:#1976d2
    style D fill:#fff3e0,stroke:#e65100
    style F fill:#f3e5f5,stroke:#6a1b9a
```

#### 步骤 1: 准备工作

```bash
# 检查当前配置
./verify-trust-configs.sh > current-config-backup.txt

# 确认当前包含哪些 CA
gcloud certificate-manager trust-configs describe my-trust-config \
    --location=global \
    --format=yaml > trust-config-backup.yaml
```

#### 步骤 2: 准备 CA 证书文件

```bash
# 假设你有以下文件
ls -la *.pem

# 输出示例:
# old-root-ca.pem          (现有的 CA)
# new-root-ca.pem          (新添加的 CA)
# intermediate-ca.pem      (可选的中间 CA)
```

#### 步骤 3: 验证证书文件

```bash
# 验证证书格式
openssl x509 -in old-root-ca.pem -text -noout
openssl x509 -in new-root-ca.pem -text -noout

# 检查证书有效期
openssl x509 -in new-root-ca.pem -noout -dates

# 输出示例:
# notBefore=Jan  1 00:00:00 2024 GMT
# notAfter=Dec 31 23:59:59 2034 GMT
```

#### 步骤 4: 更新 Trust Config

```bash
# 更新配置（包含新旧 CA）
gcloud certificate-manager trust-configs import my-trust-config \
    --location=global \
    --trust-anchor=file=old-root-ca.pem,pem-certificate \
    --trust-anchor=file=new-root-ca.pem,pem-certificate \
    --description="Updated: Added new CA for migration"

# 等待配置生效（通常几秒钟）
sleep 5
```

#### 步骤 5: 验证更新

```bash
# 重新运行验证脚本
./verify-trust-configs.sh

# 确认输出中包含两个 Trust Anchors
# Trust Anchor #1: old-root-ca
# Trust Anchor #2: new-root-ca
```

#### 步骤 6: 测试连接

```bash
# 使用旧证书测试（应该成功）
curl -v --cert old-client.crt --key old-client.key https://your-api.example.com

# 使用新证书测试（应该成功）
curl -v --cert new-client.crt --key new-client.key https://your-api.example.com
```

## 证书更新决策树

```mermaid
graph TD
    Start{"需要更新证书"} --> Q1{"证书类型?"}
    
    Q1 -->|客户端证书| Q2{"签发 CA 是否改变?"}
    Q1 -->|CA 证书本身| Q5{"CA 根证书过期?"}
    
    Q2 -->|否| Action1["只需更新客户端证书<br/>Trust Config 无需修改"]
    Q2 -->|是| Q3{"是否需要平滑迁移?"}
    
    Q3 -->|是| Action2["1. 添加新 CA 到 Trust Config<br/>2. 逐步迁移客户端<br/>3. 移除旧 CA"]
    Q3 -->|否| Action3["直接替换 Trust Config 中的 CA<br/>(会导致旧证书立即失效)"]
    
    Q5 -->|是| Action4["1. 添加新根 CA<br/>2. 客户端重新签发证书<br/>3. 移除旧根 CA"]
    Q5 -->|否| Action5["定期续期 CA 证书"]
    
    Action1 --> End1["完成"]
    Action2 --> End2["完成"]
    Action3 --> Warning["⚠️ 可能中断服务"]
    Action4 --> End3["完成"]
    Action5 --> End4["完成"]
    
    Warning --> End5["完成"]
    
    style Start fill:#e3f2fd,stroke:#1976d2
    style Action1 fill:#e8f5e9,stroke:#2e7d32
    style Action2 fill:#fff9c4,stroke:#f57f17
    style Action3 fill:#ffebee,stroke:#c62828
    style Warning fill:#ffebee,stroke:#c62828
```

## 常见问题与排查

### 问题 1: 客户端连接被拒绝

```mermaid
graph TD
    Problem["客户端连接失败<br/>403/401 错误"] --> Check1["检查客户端证书"]
    
    Check1 --> C1{"证书是否过期?"}
    C1 -->|是| Fix1["续期证书"]
    C1 -->|否| Check2["检查证书链"]
    
    Check2 --> C2{"证书链是否完整?"}
    C2 -->|否| Fix2["补充中间证书"]
    C2 -->|是| Check3["检查 Trust Config"]
    
    Check3 --> C3{"签发 CA 是否在<br/>Trust Anchors?"}
    C3 -->|否| Fix3["添加 CA 到 Trust Config"]
    C3 -->|是| Check4["检查 Allowlist"]
    
    Check4 --> C4{"配置了 Allowlist?"}
    C4 -->|是| C5{"证书在 Allowlist?"}
    C5 -->|否| Fix4["添加证书到 Allowlist<br/>或移除 Allowlist 限制"]
    C5 -->|是| Check5["检查其他配置"]
    
    C4 -->|否| Check5
    Check5 --> Fix5["查看 GLB 日志<br/>检查其他安全策略"]
    
    style Problem fill:#ffebee,stroke:#c62828
    style Fix1 fill:#e8f5e9,stroke:#2e7d32
    style Fix2 fill:#e8f5e9,stroke:#2e7d32
    style Fix3 fill:#fff3e0,stroke:#e65100
    style Fix4 fill:#fff3e0,stroke:#e65100
```

### 排查步骤

```bash
# 1. 验证客户端证书
openssl x509 -in client.crt -text -noout | grep -E "(Issuer|Not Before|Not After)"

# 2. 验证证书链
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem client.crt

# 3. 检查 Trust Config
./verify-trust-configs.sh

# 4. 提取证书签发者信息
openssl x509 -in client.crt -noout -issuer

# 5. 对比 Trust Config 中的 CA
# 查看验证脚本输出的 Trust Anchors，确认 Issuer 是否匹配
```

### 问题 2: 更新 Trust Config 后旧证书无法连接

**原因**: 使用 `import` 命令替换配置时，遗漏了旧的 CA。

**解决方案**:

```bash
# 1. 从备份中恢复旧 CA 信息
cat trust-config-backup.yaml

# 2. 重新导入，包含所有 CA
gcloud certificate-manager trust-configs import my-trust-config \
    --location=global \
    --trust-anchor=file=old-ca.pem,pem-certificate \
    --trust-anchor=file=new-ca.pem,pem-certificate

# 3. 验证
./verify-trust-configs.sh
```

### 问题 3: 如何知道证书何时过期？

```bash
# 使用验证脚本
./verify-trust-configs.sh

# 输出会显示:
# Days Remaining: 285 (OK)           - 正常
# Days Remaining: 45 (WARNING)       - 需要关注 (< 90天)
# Days Remaining: 15 (EXPIRING SOON!) - 紧急 (< 30天)
# Days Remaining: -5 (EXPIRED!)      - 已过期
```

## 最佳实践

### 1. 证书生命周期管理

```mermaid
gantt
    title 证书生命周期管理时间线
    dateFormat YYYY-MM-DD
    section CA 根证书
    有效期 10年           :2024-01-01, 3650d
    监控期 (90天预警)    :milestone, 2033-10-03, 0d
    更新准备期          :crit, 2033-10-03, 60d
    执行更新            :crit, 2033-12-02, 30d
    
    section 客户端证书
    有效期 1年           :2024-01-01, 365d
    监控期 (90天预警)    :milestone, 2024-10-03, 0d
    更新准备期          :crit, 2024-10-03, 60d
    执行更新            :crit, 2024-12-02, 30d
```

### 2. 定期监控

```bash
# 设置 cron 定期检查（每周一次）
0 9 * * 1 /path/to/verify-trust-configs.sh > /var/log/trust-config-weekly.log 2>&1

# 设置告警脚本
#!/bin/bash
OUTPUT=$(./verify-trust-configs.sh 2>&1)

if echo "$OUTPUT" | grep -E "(EXPIRING SOON|EXPIRED)"; then
    # 发送告警邮件或通知
    echo "$OUTPUT" | mail -s "Trust Config Certificate Alert" admin@example.com
fi
```

### 3. 版本控制

```bash
# 定期导出并提交到版本控制
./verify-trust-configs.sh
git add trust-configs-export/*.yaml
git commit -m "Trust config snapshot - $(date +%Y-%m-%d)"
git push
```

### 4. 文档记录

维护一个变更日志：

```markdown
## Trust Config 变更记录

### 2026-01-23
- **操作**: 添加新 CA (CA-2) 到 Trust Config
- **原因**: 为证书迁移做准备
- **影响**: 无，双 CA 并存
- **执行人**: Admin
- **验证**: ✓ 通过

### 2026-02-15
- **操作**: 移除旧 CA (CA-1)
- **原因**: 所有客户端已迁移完成
- **影响**: 使用旧 CA-1 证书的客户端将无法连接
- **执行人**: Admin
- **验证**: ✓ 通过
```

### 5. 测试环境先行

```mermaid
graph LR
    A["开发环境测试"] --> B["测试环境验证"]
    B --> C["预生产环境验证"]
    C --> D["生产环境部署"]
    
    A --> A1["验证新 CA 配置"]
    B --> B1["验证客户端迁移"]
    C --> C1["验证完整流程"]
    D --> D1["监控生产环境"]
    
    style A fill:#e8f5e9,stroke:#2e7d32
    style B fill:#e1f5fe,stroke:#01579b
    style C fill:#fff9c4,stroke:#f57f17
    style D fill:#ffebee,stroke:#c62828
```

## 总结

### Trust Config 更新场景对照表

| 场景 | Trust Config 是否需要更新 | 更新内容 | 影响 |
|------|-------------------------|---------|------|
| 客户端证书续期（同一 CA） | ❌ 否 | - | 无影响 |
| 客户端证书迁移到新 CA | ✅ 是 | 添加新 CA | 需平滑迁移 |
| CA 根证书更新 | ✅ 是 | 添加新根证书，后移除旧根证书 | 需重新签发客户端证书 |
| 添加新客户端（同一 CA） | ❌ 否 | - | 无影响 |
| 添加新客户端（新 CA） | ✅ 是 | 添加新 CA | 可能需要审批 |

### 关键要点

> [!IMPORTANT]
> 1. **Trust Config 定义了 GLB 信任的 CA 列表**，不是客户端证书本身
> 2. **客户端证书续期（CA 不变）不需要更新 Trust Config**
> 3. **更新 Trust Config 时要包含所有需要保留的 CA**（`import` 是覆盖操作）
> 4. **平滑迁移策略**：先添加新 CA，客户端逐步迁移，确认后移除旧 CA
> 5. **定期监控证书过期时间**，建议提前 90 天开始准备

### 快速参考命令

```bash
# 查看 Trust Config
gcloud certificate-manager trust-configs list --location=global

# 详细信息
gcloud certificate-manager trust-configs describe CONFIG_NAME --location=global

# 验证证书和过期时间
./verify-trust-configs.sh

# 添加新 CA（保留旧 CA）
gcloud certificate-manager trust-configs import CONFIG_NAME \
    --location=global \
    --trust-anchor=file=old-ca.pem,pem-certificate \
    --trust-anchor=file=new-ca.pem,pem-certificate

# 验证证书链
openssl verify -CAfile root-ca.pem client.crt
```

## 相关资源

- [GCP Certificate Manager 官方文档](https://cloud.google.com/certificate-manager/docs)
- [Trust Configs 配置指南](https://cloud.google.com/certificate-manager/docs/trust-configs)
- [GLB mTLS 配置](https://cloud.google.com/load-balancing/docs/mtls)
- [验证脚本使用指南](verify-trust-configs-guide.md)


```mermaid
flowchart TB
    classDef clientStyle fill:#f9f7f7,stroke:#333,stroke-width:2px,color:#333,font-weight:bold
    classDef lbStyle fill:#e8f0fe,stroke:#4285f4,stroke-width:2px,color:#174ea6,font-weight:bold
    classDef policyStyle fill:#f0f7ff,stroke:#4285f4,stroke-width:1px,color:#0b5394
    classDef trustStyle fill:#e6f2ff,stroke:#4285f4,stroke-width:1px,color:#0b5394
    classDef backendStyle fill:#e6f4ea,stroke:#34a853,stroke-width:1px,color:#137333

    subgraph Client
        client[Client System]
    end

    subgraph GoogleCloud[Google Cloud]
        subgraph LoadBalancer[Cloud Load Balancing]
            lb[Load Balancer]
        end
        subgraph SecurityConfig[Security Configuration]
            subgraph TrustConfig[Trust Config]
                trustStore[Trust Store]
                rootCert[Root CA Certificate]
                interCert[Intermediate CA Certificate]
                trustStore --> rootCert
                trustStore --> interCert
            end
            subgraph Policies[Security Policies]
                clientAuth[Client Authentication]
                tlsPolicy[Server TLS Policy]
                clientAuth --> tlsPolicy
            end
            trustStore --> clientAuth
            tlsPolicy --> lb
        end
    end

    subgraph Backend
        nginx[Nginx Reverse Proxy]
        internal[Internal Services]
        nginx --> internal
    end

    client --> |1 Initiate HTTPS Request| lb
    lb --> |2 Apply TLS Configuration| tlsPolicy
    tlsPolicy --> |3 Enforce mTLS if Configured| clientAuth
    clientAuth --> |4 Validate Client Certificate| trustStore
    trustStore --> |5 Return Validation Result| clientAuth
    clientAuth --> |6 Allow or Deny Request| tlsPolicy
    tlsPolicy --> |7 Forward Validated Request| lb
    lb --> |8 Route to Backend| nginx

    class client clientStyle
    class lb lbStyle
    class clientAuth,tlsPolicy policyStyle
    class trustStore,rootCert,interCert trustStyle
    class nginx,internal backendStyle
```
