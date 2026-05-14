#!/bin/bash
# 本地测试脚本
# 模拟平台环境进行本地测试

set -e

echo "=== Setting up local test environment ==="

# 创建测试目录
mkdir -p /tmp/mycoat-test-nodejs/config
mkdir -p /tmp/mycoat-test-nodejs/keystore

# 生成测试配置文件
cat > /tmp/mycoat-test-nodejs/config/server-conf.properties <<EOF
# 测试配置
server.port=8443
server.ssl.enabled=true
server.ssl.cert-path=/tmp/mycoat-test-nodejs/keystore/tls.crt
server.ssl.key-path=/tmp/mycoat-test-nodejs/keystore/tls.key
server.context-path=/\${apiName}/v\${minorVersion}
EOF

echo "✓ Created test config file"

# 生成测试证书（PEM 格式）
if [ ! -f /tmp/mycoat-test-nodejs/keystore/tls.crt ]; then
    echo "Generating test certificates..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout /tmp/mycoat-test-nodejs/keystore/tls.key \
        -out /tmp/mycoat-test-nodejs/keystore/tls.crt \
        -days 365 -nodes \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=MyCoat/CN=localhost"
    echo "✓ Generated test certificates"
fi

# 设置环境变量
export PLATFORM_CONFIG_PATH="/tmp/mycoat-test-nodejs/config/server-conf.properties"
export apiName="user-service"
export minorVersion="1"

echo "✓ Set environment variables"
echo ""
echo "=== Environment ==="
echo "PLATFORM_CONFIG_PATH=$PLATFORM_CONFIG_PATH"
echo "apiName=$apiName"
echo "minorVersion=$minorVersion"
echo ""

# 安装依赖
echo "=== Installing dependencies ==="
npm install
echo "✓ Dependencies installed"
echo ""

# 启动应用
echo "=== Starting application ==="
echo "Application will start on https://localhost:8443/$apiName/v$minorVersion"
echo ""
echo "Test endpoints:"
echo "  curl -k https://localhost:8443/$apiName/v$minorVersion/health"
echo "  curl -k https://localhost:8443/$apiName/v$minorVersion/ready"
echo "  curl -k https://localhost:8443/$apiName/v$minorVersion/hello"
echo ""
echo "Press Ctrl+C to stop"
echo ""

node server.js
