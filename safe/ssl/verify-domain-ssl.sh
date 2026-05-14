#!/bin/bash

DOMAIN=$1
PORT=${2:-443}
CA_FILE=$3

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain-fqdn> [port] [ca-file-path]"
    echo "Example (Ubuntu CA default): $0 my-domain-fqdn.com 443 /etc/ssl/certs/ca-certificates.crt"
    exit 1
fi

echo "=================================================="
echo "🔍 探测 SSL 证书链状态: $DOMAIN:$PORT"
if [ -n "$CA_FILE" ]; then
    if [ -f "$CA_FILE" ]; then
        echo "📁 使用指定的 CA 证书文件: $CA_FILE"
        CA_OPT="-CAfile $CA_FILE"
    else
        echo "❌ 错误: 指定的 CA 文件不存在或不可读 ($CA_FILE)"
        exit 1
    fi
else
    echo "📁 使用系统默认 CA 证书库"
    CA_OPT=""
fi
echo "=================================================="

# 1. 抓取证书链
echo "[1] 拉取服务器返回的证书..."
# 将整个证书链抓取到一个临时文件中
openssl s_client -connect "$DOMAIN":"$PORT" -servername "$DOMAIN" -showcerts </dev/null 2>/dev/null > "/tmp/ssl_probe_$$.txt"

# 计算 BEGIN CERTIFICATE 的数量
CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "/tmp/ssl_probe_$$.txt")
echo ">> 服务器共返回了 $CERT_COUNT 段证书"

if [ "$CERT_COUNT" -eq 0 ]; then
    echo "❌ 错误: 未获取到任何证书，请检查域名和网络连通性。"
    rm -f "/tmp/ssl_probe_$$.txt"
    exit 1
elif [ "$CERT_COUNT" -eq 1 ]; then
    echo "⚠️ 警告: 仅捕获到 1 段证书。服务器缺少中间证书(Intermediate CA)，客户端可能无法自动建立信任链！"
else
    echo "✅ 正常: 捕获到多段证书，证书链似乎包含在内。"
fi

echo ""
echo "[2] 解析证书颁发关系 (Subject vs Issuer)..."
# 使用 awk 分割多个证书并分别使用 openssl 解析
awk -v cmd="openssl x509 -noout -subject -issuer" '
    /BEGIN CERTIFICATE/{cert=""}
    {cert=cert $0 "\n"}
    /END CERTIFICATE/{
        printf "\n--- Certificate ---\n"
        print cert | cmd
        close(cmd)
    }
' "/tmp/ssl_probe_$$.txt"

echo ""
echo "[3] 环境的信任校验结果..."
# 检查默认或指定的 verify return code
openssl s_client -connect "$DOMAIN":"$PORT" -servername "$DOMAIN" $CA_OPT </dev/null 2>/dev/null | grep "Verify return code"

rm -f "/tmp/ssl_probe_$$.txt"

echo "=================================================="
echo "💡 排查指南:"
echo "- 证书数 == 1 且报错 '21 (unable to verify the first certificate)' -> 服务器自身配置缺陷，没有把中间证书捆绑返回。"
echo "- 证书数 >= 2 且报错 '20 (unable to get local issuer certificate)' -> 服务器链条完整，你正使用的 CA 证书库中缺失根证书(Root CA)。"
echo "- 状态显示 '0 (ok)' -> 证书链完好且所使用的 CA 库已正确信任根证书。"
echo "=================================================="
