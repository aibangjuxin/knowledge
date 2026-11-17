# **DigiCert EKU 证书检查工具**

> **重要**: 2025年10月1日起，DigiCert 将不再在新证书中包含 Client Authentication EKU

## **工具说明**

### **1. check_eku.sh - 单证书检查工具**
检查单个证书的 EKU 信息，并识别是否为 DigiCert 签发

### **2. digicert_impact_assessment.sh - 批量评估工具**
批量检查多个证书，生成详细的影响评估报告

---

## **快速开始**

### **检查单个证书**
```bash
# 检查在线证书
./check_eku.sh example.com:443

# 检查本地证书文件
./check_eku.sh certificate.crt

# 详细模式
./check_eku.sh -v example.com:443
```

### **批量评估**
```bash
# 检查多个域名
./digicert_impact_assessment.sh domain1.com domain2.com api.domain3.com

# 从文件读取域名列表
echo -e "domain1.com\ndomain2.com\napi.domain3.com" > domains.txt
./digicert_impact_assessment.sh -f domains.txt

# 静默模式（只显示摘要）
./digicert_impact_assessment.sh -q -f domains.txt
```

---

## **部署和使用**

### **方式1: 保持文件在同一目录**
```bash
# 将两个脚本放在同一目录
ls -la
# -rwxr-xr-x check_eku.sh
# -rwxr-xr-x digicert_impact_assessment.sh

./digicert_impact_assessment.sh example.com
```

### **方式2: 指定 check_eku.sh 路径**
```bash
# 脚本可以在不同位置
./digicert_impact_assessment.sh -c /path/to/check_eku.sh example.com
```

### **方式3: 添加到系统 PATH**
```bash
# 复制到系统路径
sudo cp check_eku.sh /usr/local/bin/
sudo cp digicert_impact_assessment.sh /usr/local/bin/

# 现在可以在任何地方使用
digicert_impact_assessment.sh example.com
```

---

## **输出解读**

### **🚨 需要立即行动**
```
🚨 CRITICAL: DigiCert certificate with Client Authentication EKU 