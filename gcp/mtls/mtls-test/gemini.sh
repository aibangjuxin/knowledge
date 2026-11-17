#!/bin/bash

# 检查输入参数
if [ "$#" -ne 1 ]; then
  echo "使用方法: $0 <证书文件>"
  echo "例如: $0 mycert.pem"
  exit 1
fi

cert_file="$1"

# 检查证书文件是否存在
if [ ! -f "$cert_file" ]; then
  echo "错误: 证书文件 '$cert_file' 不存在。"
  exit 1
fi

echo "正在分析证书: $cert_file"
echo "----------------------------------------"

# 提取证书的主题和颁发者信息
subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null)
issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null)

if [ -z "$subject" ] || [ -z "$issuer" ]; then
  echo "错误: 无法从证书中提取主题或颁发者信息。请检查证书文件是否有效。"
  exit 1
fi

echo "主题 (Subject): $subject"
echo "颁发者 (Issuer): $issuer"

# 比较主题和颁发者
if [ "$subject" = "$issuer" ]; then
  echo "----------------------------------------"
  echo "这个证书是自签名的，很可能是一个 根证书 (Root Certificate)。"
else
  # 进一步检查 Basic Constraints 扩展，确认是否是 CA 证书
  basic_constraints=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Basic Constraints:")

  if [[ "$basic_constraints" == *"CA:TRUE"* ]]; then
    echo "----------------------------------------"
    echo "这个证书的颁发者和主题不同，且是 CA 证书，因此它是一个 中间证书 (Intermediate Certificate)。"

    # 检查 pathlen
    if [[ "$basic_constraints" == *"pathlen:"* ]]; then
      pathlen=$(echo "$basic_constraints" | sed -n 's/.*pathlen:\([0-9]*\).*/\1/p')
      echo "它的 pathlen 限制为: $pathlen"
      if [ "$pathlen" -eq 0 ]; then
        echo "此中间证书不能再签发其他证书。"
      fi
    fi
  else
    echo "----------------------------------------"
    echo "这个证书的颁发者和主题不同，且不是 CA 证书，因此它是一个 终端实体证书 (End-Entity Certificate)。"
  fi
fi

echo "----------------------------------------"
