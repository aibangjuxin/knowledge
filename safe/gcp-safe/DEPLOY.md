# 部署指南

## 快速部署到 Linux 服务器

### 1. 上传文件

```bash
# 方式 1: 使用 scp
scp verify-kms-enhanced.sh user@server:/path/to/scripts/
scp debug-test.sh user@server:/path/to/scripts/
scp quick-test.sh user@server:/path/to/scripts/
scp test-permissions.sh user@server:/path/to/scripts/

# 方式 2: 使用 rsync
rsync -av *.sh user@server:/path/to/scripts/

# 方式 3: 使用 git
git clone <repo> /path/to/scripts/
cd /path/to/scripts/safe/gcp-safe/
```

### 2. 设置执行权限

```bash
chmod +x verify-kms-enhanced.sh
chmod +x debug-test.sh
chmod +x quick-test.sh
chmod +x test-permissions.sh
```

### 3. 安装依赖

```bash
# 检查 gcloud
if ! command -v gcloud &> /dev/null; then
    echo "需要安装 Google Cloud SDK"
    echo "https://cloud.google.com/sdk/docs/install"
fi

# 安装 jq
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# CentOS/RHEL
sudo yum install -y jq

# 验证安装
gcloud version
jq --version
```

### 4. 配置认证

```bash
# 方式 1: 用户账号
gcloud auth login

# 方式 2: 服务账号（推荐用于自动化）
gcloud auth activate-service-account \
  --key-file=/path/to/service-account-key.json

# 验证认证
gcloud auth list
```

### 5. 运行诊断

```bash
# 环境诊断
./debug-test.sh

# 功能测试
./quick-test.sh

# 权限测试（可选）
./test-permissions.sh \
  YOUR_KMS_PROJECT \
  global \
  YOUR_KEYRING \
  YOUR_KEY
```

### 6. 首次运行

```bash
# 查看帮助
./verify-kms-enhanced.sh --help

# 实际运行
./verify-kms-enhanced.sh \
  --kms-project YOUR_KMS_PROJECT \
  --business-project YOUR_BIZ_PROJECT \
  --keyring YOUR_KEYRING \
  --key YOUR_KEY \
  --location global \
  --service-accounts "sa1@project.iam,sa2@project.iam" \
  --verbose
```

---

## 自动化部署脚本

创建 `deploy.sh`:

```bash
#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "KMS 验证脚本部署"
echo "=========================================="
echo ""

# 配置
INSTALL_DIR="/opt/kms-validator"
SERVICE_ACCOUNT_KEY="/etc/gcp/kms-validator-key.json"

# 1. 创建目录
echo "1. 创建安装目录..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

# 2. 复制文件
echo "2. 复制脚本文件..."
cp verify-kms-enhanced.sh "$INSTALL_DIR/"
cp debug-test.sh "$INSTALL_DIR/"
cp quick-test.sh "$INSTALL_DIR/"
cp test-permissions.sh "$INSTALL_DIR/"

# 3. 设置权限
echo "3. 设置执行权限..."
chmod +x "$INSTALL_DIR"/*.sh

# 4. 安装依赖
echo "4. 检查依赖..."
if ! command -v jq &> /dev/null; then
    echo "安装 jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    else
        echo "请手动安装 jq"
        exit 1
    fi
fi

# 5. 配置认证
echo "5. 配置 gcloud 认证..."
if [[ -f "$SERVICE_ACCOUNT_KEY" ]]; then
    gcloud auth activate-service-account \
      --key-file="$SERVICE_ACCOUNT_KEY"
    echo "✓ 服务账号认证成功"
else
    echo "⚠ 未找到服务账号密钥: $SERVICE_ACCOUNT_KEY"
    echo "请手动运行: gcloud auth login"
fi

# 6. 运行诊断
echo "6. 运行诊断测试..."
cd "$INSTALL_DIR"
./debug-test.sh

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="
echo ""
echo "安装位置: $INSTALL_DIR"
echo ""
echo "下一步:"
echo "1. 配置认证（如果尚未配置）"
echo "2. 运行: cd $INSTALL_DIR && ./verify-kms-enhanced.sh --help"
echo "3. 查看文档: cat README.md"
```

---

## 定时任务配置

### 使用 cron

```bash
# 编辑 crontab
crontab -e

# 每周一早上 8 点运行
0 8 * * 1 /opt/kms-validator/verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --output-format json \
  > /var/log/kms-validator/report-$(date +\%Y\%m\%d).log 2>&1

# 创建日志目录
sudo mkdir -p /var/log/kms-validator
sudo chown $USER:$USER /var/log/kms-validator
```

### 使用 systemd timer

创建 `/etc/systemd/system/kms-validator.service`:

```ini
[Unit]
Description=KMS Validator
After=network.target

[Service]
Type=oneshot
User=kms-validator
WorkingDirectory=/opt/kms-validator
ExecStart=/opt/kms-validator/verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --output-format json
StandardOutput=append:/var/log/kms-validator/validator.log
StandardError=append:/var/log/kms-validator/validator.log

[Install]
WantedBy=multi-user.target
```

创建 `/etc/systemd/system/kms-validator.timer`:

```ini
[Unit]
Description=KMS Validator Timer
Requires=kms-validator.service

[Timer]
OnCalendar=Mon *-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kms-validator.timer
sudo systemctl start kms-validator.timer

# 查看状态
sudo systemctl status kms-validator.timer
sudo systemctl list-timers
```

---

## CI/CD 集成

### GitLab CI

`.gitlab-ci.yml`:

```yaml
stages:
  - validate

kms_validation:
  stage: validate
  image: google/cloud-sdk:alpine
  before_script:
    - apk add --no-cache jq bash
    - echo $GCP_SERVICE_ACCOUNT_KEY | base64 -d > /tmp/key.json
    - gcloud auth activate-service-account --key-file=/tmp/key.json
  script:
    - chmod +x verify-kms-enhanced.sh
    - |
      ./verify-kms-enhanced.sh \
        --kms-project ${KMS_PROJECT} \
        --business-project ${BUSINESS_PROJECT} \
        --keyring ${KEYRING} \
        --key ${CRYPTO_KEY} \
        --location ${LOCATION} \
        --service-accounts ${SERVICE_ACCOUNTS} \
        --output-format json
  artifacts:
    reports:
      - kms-validation-report-*.json
    expire_in: 30 days
  only:
    - schedules
    - main
```

### GitHub Actions

`.github/workflows/kms-validation.yml`:

```yaml
name: KMS Validation

on:
  schedule:
    - cron: '0 8 * * 1'  # 每周一早上 8 点
  workflow_dispatch:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Setup Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      
      - name: Run Validation
        run: |
          chmod +x verify-kms-enhanced.sh
          ./verify-kms-enhanced.sh \
            --kms-project ${{ secrets.KMS_PROJECT }} \
            --business-project ${{ secrets.BUSINESS_PROJECT }} \
            --keyring ${{ secrets.KEYRING }} \
            --key ${{ secrets.CRYPTO_KEY }} \
            --location global \
            --service-accounts "${{ secrets.SERVICE_ACCOUNTS }}" \
            --output-format json
      
      - name: Upload Report
        uses: actions/upload-artifact@v3
        with:
          name: kms-validation-report
          path: kms-validation-report-*.json
          retention-days: 30
```

---

## Docker 部署

### Dockerfile

```dockerfile
FROM google/cloud-sdk:alpine

# 安装依赖
RUN apk add --no-cache bash jq

# 创建工作目录
WORKDIR /app

# 复制脚本
COPY verify-kms-enhanced.sh .
COPY debug-test.sh .
COPY quick-test.sh .
COPY test-permissions.sh .

# 设置权限
RUN chmod +x *.sh

# 入口点
ENTRYPOINT ["/app/verify-kms-enhanced.sh"]
```

### 构建和运行

```bash
# 构建镜像
docker build -t kms-validator:latest .

# 运行
docker run --rm \
  -v /path/to/service-account-key.json:/key.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/key.json \
  kms-validator:latest \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2"
```

---

## 监控和告警

### 配置告警

```bash
# 创建告警脚本
cat > /opt/kms-validator/alert.sh << 'EOF'
#!/bin/bash

REPORT_FILE="$1"
STATUS=$(jq -r '.summary.status' "$REPORT_FILE")

if [[ "$STATUS" != "passed" ]]; then
    # 发送告警邮件
    echo "KMS 验证失败！" | mail -s "KMS Validation Alert" admin@example.com
    
    # 或发送到 Slack
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"KMS 验证失败！查看报告: $REPORT_FILE\"}" \
      $SLACK_WEBHOOK_URL
fi
EOF

chmod +x /opt/kms-validator/alert.sh
```

### 集成到验证流程

```bash
# 运行验证并告警
./verify-kms-enhanced.sh [参数] --output-format json
./alert.sh kms-validation-report-*.json
```

---

## 卸载

```bash
# 停止定时任务
sudo systemctl stop kms-validator.timer
sudo systemctl disable kms-validator.timer

# 删除文件
sudo rm -rf /opt/kms-validator
sudo rm -f /etc/systemd/system/kms-validator.*
sudo rm -rf /var/log/kms-validator

# 删除 crontab 条目
crontab -e  # 手动删除相关行

# 撤销 gcloud 认证
gcloud auth revoke
```

---

## 故障排查

### 部署后无法运行

1. **检查权限**
   ```bash
   ls -la verify-kms-enhanced.sh
   # 应该显示 -rwxr-xr-x
   ```

2. **检查依赖**
   ```bash
   ./debug-test.sh
   ```

3. **检查认证**
   ```bash
   gcloud auth list
   ```

### 定时任务不执行

1. **检查 cron 日志**
   ```bash
   sudo tail -f /var/log/syslog | grep CRON
   ```

2. **检查 systemd timer**
   ```bash
   sudo systemctl status kms-validator.timer
   sudo journalctl -u kms-validator.service
   ```

---

**版本**: v2.0.2  
**最后更新**: 2025-11-10
