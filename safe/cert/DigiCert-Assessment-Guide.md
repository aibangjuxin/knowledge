# **DigiCert EKU 影响评估指南**

> **重要提醒**: 2025年10月1日起，DigiCert 将不再在新证书中包含 Client Authentication EKU

---

## **工具概览**

我们提供了两个增强的工具来帮助你评估 DigiCert EKU 变更的影响：

1. **`check_eku.sh`** - 单个证书检查工具（已增强 DigiCert 检测）
2. **`digicert_impact_assessment.sh`** - 批量评估工具

---

## **1. 单个证书检查**

### **基本用法**

```bash
# 检查在线证书
./safe/cert/check_eku.sh your-domain.com:443

# 检查本地证书文件
./safe/cert/check_eku.sh /path/to/certificate.crt

# 详细模式
./safe/cert/check_eku.sh -v your-domain.com:443

# 调试模式（显示原始 OpenSSL 输出）
./safe/cert/check_eku.sh -d your-domain.com:443
```

### **输出解读**

#### **🚨 需要立即行动的情况**
```
🚨 CRITICAL: DigiCert certificate with Client Authentication EKU detected!
   Action Required: This certificate will be affected by the October 1st, 2025 change
   Impact: Client Authentication EKU will be removed from new/renewed certificates
   Recommendation: Plan for separate client authentication certificates
```

#### **✅ 已经合规的 DigiCert 证书**
```
✅ DigiCert certificate without Client Authentication EKU
   Status: Already compliant with post-October 2025 standards
```

#### **✅ 非 DigiCert 证书**
```
✅ Non-DigiCert certificate
   Status: Not affected by DigiCert EKU change
```

---

## **2. 批量影响评估**

### **基本用法**

```bash
# 检查多个域名
./safe/cert/digicert_impact_assessment.sh domain1.com domain2.com api.domain3.com

# 从文件读取域名列表
echo -e "domain1.com\ndomain2.com:8443\napi.domain3.com" > domains.txt
./safe/cert/digicert_impact_assessment.sh -f domains.txt

# 检查证书文件
./safe/cert/digicert_impact_assessment.sh /path/to/certs/*.crt

# 混合检查（域名 + 文件）
./safe/cert/digicert_impact_assessment.sh domain.com /path/to/cert.crt

# 指定输出文件
./safe/cert/digicert_impact_assessment.sh -o my_assessment.txt domain1.com domain2.com
```

### **评估报告**

工具会生成两个文件：
- **主报告**: `digicert_impact_report_YYYYMMDD_HHMMSS.txt`
- **受影响证书列表**: `affected_certificates.txt`（仅在有受影响证书时生成）

---

## **3. 实际使用场景**

### **场景 A: 评估你的生产环境**

```bash
# 创建域名列表
cat > production_domains.txt << EOF
api.yourcompany.com:443
app.yourcompany.com:443
admin.yourcompany.com:443
gateway.yourcompany.com:8443
EOF

# 运行评估
./safe/cert/digicert_impact_assessment.sh -f production_domains.txt -o prod_assessment.txt
```

### **场景 B: 检查 Kubernetes 集群中的证书**

```bash
# 导出所有 TLS secrets 中的证书
kubectl get secrets -A -o json | jq -r '.items[] | select(.type=="kubernetes.io/tls") | "\(.metadata.namespace)/\(.metadata.name)"' > k8s_tls_secrets.txt

# 提取证书文件并检查
mkdir -p temp_certs
while read secret; do
    namespace=$(echo $secret | cut -d'/' -f1)
    name=$(echo $secret | cut -d'/' -f2)
    kubectl get secret $name -n $namespace -o jsonpath='{.data.tls\.crt}' | base64 -d > temp_certs/${namespace}_${name}.crt
done < k8s_tls_secrets.txt

# 批量检查
./safe/cert/digicert_impact_assessment.sh temp_certs/*.crt
```

### **场景 C: 检查 Kong Gateway 证书**

```bash
# 检查 Kong Gateway 使用的证书
kubectl get plugins -A -o yaml | grep -A 10 -B 5 "mtls-auth" > kong_mtls_config.yaml

# 从配置中提取证书并检查
# (需要根据你的具体配置调整)
```

---

## **4. DigiCert 检测逻辑**

工具会检查证书颁发者（Issuer）中是否包含以下模式：

- **DigiCert** - 主要品牌
- **Symantec** - DigiCert 收购的品牌
- **GeoTrust** - DigiCert 收购的品牌  
- **Thawte** - DigiCert 收购的品牌
- **RapidSSL** - DigiCert 收购的品牌

### **示例颁发者匹配**

```bash
# 这些都会被识别为 DigiCert 系列
CN=DigiCert TLS RSA SHA256 2020 CA1
CN=Symantec Class 3 Secure Server CA
CN=GeoTrust RSA CA 2018
CN=Thawte TLS RSA CA G1
CN=RapidSSL TLS DV RSA Mixed SHA256 2020 CA-1