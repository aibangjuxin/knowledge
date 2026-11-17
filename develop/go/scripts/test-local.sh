#!/bin/bash
# 本地测试脚本
# 模拟平台环境进行本地测试

set -e

echo "=== Setting up local test environment ==="

# 创建测试目录
mkdir -p /tmp/mycoat-test/config
mkdir -p /tmp/mycoat-test/keystore

# 生成测试配置文件
cat > /tmp/mycoat-test/config/server-conf.properties <<EOF
# 测试配置
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=/tmp/mycoat-test/keystore/mycoat-sbrt.p12
server.ssl.key-store-type=PKCS12
server.ssl.key-store-password=\${KEY_STORE_PWD}
server.servlet.context-path=/\${apiName}/v\${minorVersion}
EOF

echo "✓ Created test config file"

# 生成测试证书（PEM 格式）
if [ ! -f /tmp/mycoat-test/keystore/tls.crt ]; then
    echo "Generating test certificates..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout /tmp/mycoat-test/keystore/tls.key \
        -out /tmp/mycoat-test/keystore/tls.crt \
        -days 365 -nodes \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=MyCoat/CN=localhost"
    echo "✓ Generated test certificates"
fi

# 设置环境变量
export PLATFORM_CONFIG_PATH="/tmp/mycoat-test/config/server-conf.properties"
export TLS_CERT_PATH="/tmp/mycoat-test/keystore/tls.crt"
export TLS_KEY_PATH="/tmp/mycoat-test/keystore/tls.key"
export KEY_STORE_PWD="test123"
export apiName="user-service"
export minorVersion="1"

echo "✓ Set environment variables"
echo ""
echo "=== Environment ==="
echo "PLATFORM_CONFIG_PATH=$PLATFORM_CONFIG_PATH"
echo "TLS_CERT_PATH=$TLS_CERT_PATH"
echo "TLS_KEY_PATH=$TLS_KEY_PATH"
echo "apiName=$apiName"
echo "minorVersion=$minorVersion"
echo ""

# 构建应用
echo "=== Building application ==="
go build -o /tmp/mycoat-test/app main.go
echo "✓ Build completed"
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

/tmp/mycoat-test/app
