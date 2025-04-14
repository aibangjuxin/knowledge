# CA证书Onboarding流程

```mermaid
graph TD
    A[用户上传CA证书] --> B[提取证书指纹SHA-256]
    B --> C{检查Trust Config}
    C -->|已存在| D[返回已存在提示]
    C -->|不存在| E[从GCS下载Trust Config YAML]
    E --> F[追加新证书到YAML]
    F --> G[更新Trust Config YAML]
    G --> H[上传到GCS Bucket]
    H --> I[记录变更日志]
    
    subgraph 环境隔离
    H -->|Dev| J[dev-bucket/trust_config.yaml]
    H -->|Staging| K[staging-bucket/trust_config.yaml]
    H -->|Prod| L[prod-bucket/trust_config.yaml]
    end
    
    subgraph 证书验证
    B --> M[验证证书格式]
    B --> N[提取Subject/Issuer]
    end
    
    subgraph 安全审计
    I --> O[记录操作人]
    I --> P[记录时间戳]
    I --> Q[记录环境信息]
    end
```

## 流程说明

1. **证书上传与验证**
   - 用户上传CA证书（Root/Intermediate）
   - 系统验证证书格式并提取指纹

2. **重复性检查**
   - 使用SHA-256指纹检查是否已存在
   - 避免重复添加相同证书

3. **配置更新**
   - 从对应环境的GCS Bucket获取配置
   - 追加新证书到YAML配置
   - 上传更新后的配置

4. **环境管理**
   - 支持多环境配置（Dev/Staging/Prod）
   - 通过不同Bucket隔离环境

5. **审计日志**
   - 记录所有配置变更
   - 包含操作人、时间、环境信息