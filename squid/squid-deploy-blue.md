### 问题分析

你希望：

1. 保持现有的 Helm 部署方式不变
2. 在 squid.conf 中增加 `{{HOST}}` 和 `{{PORT}}` 变量
3. 通过 values.yaml 支持两种默认配置：
    - **local 模式**（原有）：使用 `{{ENV}}-proxy.aliyun.cloud.{{REGION}}.local:3128`
    - **Blue 模式**（新增）：使用自定义的 `{{HOST}}:{{PORT}}`

### 解决方案

#### 1. 修改 squid.conf 模板

```bash
# squid.conf (在你的镜像中或 ConfigMap 中)
http_port 3128

acl app_proxy dstdomain {{TARGET_FQDN}}

# 使用新的变量替代硬编码
cache_peer {{HOST}} parent {{PORT}} 0
cache_peer_access {{HOST}} allow app_proxy

http_access allow app_proxy
http_access deny all

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
```

#### 2. 增强 values.yaml 配置

```yaml
# values.yaml
proxy:
  name: "default-proxy"
  mode: "local"  # 可选值: "local", "blue"

  # 原有变量保持不变
  env: "prd"
  region: "us-central1"
  targetFQDN: "example.com"

  # 新增：预定义配置模式
  modes:
    local:
      host: "{{ENV}}-proxy.aliyun.cloud.{{REGION}}.local"
      port: "3128"
    blue:
      host: "my_local.proxy.aibang"
      port: "8080"

  # 可选：完全自定义模式
  custom:
    host: ""
    port: ""

# 向后兼容
targetFQDN:
  name: "example.com"
```

#### 3. 修改 Deployment Template

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.proxy.name }}
spec:
  template:
    spec:
      containers:
        - name: squid
          image: {{ .Values.proxy.image.repository }}:{{ .Values.proxy.image.tag }}
          env:
            # 原有变量
            - name: TARGET_FQDN
              value: "{{ .Values.targetFQDN.name }}"
            - name: ENV
              value: "{{ .Values.proxy.env }}"
            - name: REGION
              value: "{{ .Values.proxy.region }}"

            # 新增变量 - 根据模式动态设置
            {{- if eq .Values.proxy.mode "local" }}
            - name: HOST
              value: "{{ .Values.proxy.env }}-proxy.aliyun.cloud.{{ .Values.proxy.region }}.local"
            - name: PORT
              value: "{{ .Values.proxy.modes.local.port }}"
            {{- else if eq .Values.proxy.mode "blue" }}
            - name: HOST
              value: "{{ .Values.proxy.modes.blue.host }}"
            - name: PORT
              value: "{{ .Values.proxy.modes.blue.port }}"
            {{- else if eq .Values.proxy.mode "custom" }}
            - name: HOST
              value: "{{ .Values.proxy.custom.host }}"
            - name: PORT
              value: "{{ .Values.proxy.custom.port }}"
            {{- end }}
```

### 部署使用方式

#### 方式 1：通过 values 文件

**values-local.yaml** (原有 GCP 模式):

```yaml
proxy:
  mode: "local"
  env: "prd"
  region: "us-central1"
targetFQDN:
  name: "example.com"
```

**values-blue.yaml** (新的 Blue 模式):

```yaml
proxy:
  mode: "blue"
targetFQDN:
  name: "example.com"
```

#### 方式 2：通过命令行参数

```bash
# Local 模式部署（原有方式）
helm upgrade --install $namespace-${e%-*}-${proxy_code} ./charts \
  -f $proxy_value_yaml_path \
  --set proxy.name=${proxy_code} \
  --set targetFQDN.name="target_fqdn" \
  --set proxy.mode="local" \
  --set proxy.env="prd" \
  --set proxy.region="us-central1"

# Blue 模式部署（新需求）
helm upgrade --install $namespace-${e%-*}-${proxy_code} ./charts \
  -f $proxy_value_yaml_path \
  --set proxy.name=${proxy_code} \
  --set targetFQDN.name="target_fqdn" \
  --set proxy.mode="blue"

# 完全自定义模式
helm upgrade --install $namespace-${e%-*}-${proxy_code} ./charts \
  -f $proxy_value_yaml_path \
  --set proxy.name=${proxy_code} \
  --set targetFQDN.name="target_fqdn" \
  --set proxy.mode="custom" \
  --set proxy.custom.host="custom.proxy.example.com" \
  --set proxy.custom.port="9090"
```

### 配置验证

部署后可以通过以下方式验证配置：

```bash
# 查看环境变量
kubectl exec deployment/${proxy_code} -- env | grep -E "(HOST|PORT|TARGET_FQDN)"

# 查看生成的 squid.conf（如果你的镜像支持变量替换）
kubectl exec deployment/${proxy_code} -- cat /etc/squid/squid.conf
```

### 预期的 squid.conf 生成结果

**Local 模式**:

```bash
cache_peer prd-proxy.aliyun.cloud.us-central1.local parent 3128 0
cache_peer_access prd-proxy.aliyun.cloud.us-central1.local allow app_proxy
```

**Blue 模式**:

```bash
cache_peer my_local.proxy.aibang parent 8080 0
cache_peer_access my_local.proxy.aibang allow app_proxy
```

### 部署脚本示例

```bash
#!/bin/bash

NAMESPACE=$1
ENV=$2
PROXY_CODE=$3
MODE=${4:-"local"}  # 默认使用 local 模式

case $MODE in
  "local")
    helm upgrade --install $NAMESPACE-${ENV%-*}-${PROXY_CODE} ./charts \
      -f values.yaml \
      --set proxy.name=${PROXY_CODE} \
      --set targetFQDN.name="target_fqdn" \
      --set proxy.mode="local" \
      --set proxy.env=${ENV} \
      --set proxy.region="us-central1"
    ;;
  "blue")
    helm upgrade --install $NAMESPACE-${ENV%-*}-${PROXY_CODE} ./charts \
      -f values.yaml \
      --set proxy.name=${PROXY_CODE} \
      --set targetFQDN.name="target_fqdn" \
      --set proxy.mode="blue"
    ;;
  *)
    echo "不支持的模式: $MODE (支持: local, blue)"
    exit 1
    ;;
esac

echo "部署完成 - 模式: $MODE"
```

### 优势

1. **最小改动** - 只需在 squid.conf 中增加两个变量
2. **保持兼容** - 现有的部署命令结构完全不变
3. **简单直观** - 通过一个 `mode` 参数就能切换配置
4. **易于扩展** - 未来添加新模式只需在 values.yaml 中增加配置

这个方案是最轻量级的，只需要修改 squid.conf 模板和 values.yaml，就能满足你的两种配置需求。

关键改动

1. squid.conf 中的 cache_peer 配置

```squid.conf
# 原来可能是硬编码或部分变量
cache_peer {{ENV}}-proxy.aliyun.cloud.{{REGION}}.local parent 3128 0
# 改为完全变量化
cache_peer {{HOST}} parent {{PORT}} 0
cache_peer_access {{HOST}} allow app_proxy
```

2. values.yaml 中定义两种默认模式

```yaml
proxy:
  mode: "local"  # 或 "blue"
  modes:
    local:
      # 会生成: prd-proxy.aliyun.cloud.us-central1.local:3128
      host: "{{ENV}}-proxy.aliyun.cloud.{{REGION}}.local"
      port: "3128"
    blue:
      # 会生成: my_local.proxy.aibang:8080
      host: "my_local.proxy.aibang"
      port: "8080"
```

部署方式
你的现有命令只需要加一个参数：

```bash
# Local 模式（原有）
helm upgrade --install $namespace-${e%-*}-${proxy_code} ./charts \
  -f $proxy_value_yaml_path \
  --set proxy.name=${proxy_code} \
  --set targetFQDN.name="target_fqdn" \
  --set proxy.mode="local"
```

```bash
Blue 模式（新需求）
helm upgrade --install $namespace-${e%-*}-${proxy_code} ./charts \
  -f $proxy_value_yaml_path \
  --set proxy.name=${proxy_code} \
  --set targetFQDN.name="target_fqdn" \
  --set proxy.mode="blue"
```

这样你就能用最小的改动，通过一个简单的 mode 参数在两种配置间切换，完全满足你的需求！
