# Trust Config for GCP Certificate Manager
# Format follows GCP Certificate Manager schema
# https://cloud.google.com/load-balancing/docs/https/setting-up-mtls-ccm?hl=zh-cn#global
# https://cloud.google.com/certificate-manager/docs/trust-configs?hl=zh-cn#gcloud

cat << EOF > trust_config.yaml
trustStores:
- trustAnchors:
  - pemCertificate: "${ROOT_CERT?}"
  intermediateCas:
  - pemCertificate: "${INTERMEDIATE_CERT?}"
EOF
我最终能成功导入的格式是这样的 trust_config.yaml
我最终能成功导入的TrustConfig CA 支持多个CA
格式是这样的 trust_config.yaml
```yaml
trustStores:
- trustAnchors:
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      ${ROOT_CERT?}
      -----END CERTIFICATE-----
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      ${INTERMEDIATE_CERT?}
      -----END CERTIFICATE-----
  intermediateCas:
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      ${INTERMEDIATE_CERT?}
      -----END CERTIFICATE-----
  - pemCertificate: |
      -----BEGIN CERTIFICATE-----
      ${INTERMEDIATE_CERT?}
      -----END CERTIFICATE-----
```


- 1 [Using script to get cert fingerprint](./get_cert_fingerprint.md)
```bash
#!/bin/bash

# Function: Display usage instructions for the script
# This function is called when incorrect number of arguments is provided
show_usage() {
    echo "Usage: $0 <root_certificate_path> <intermediate_certificate_path>"
    echo "Example: $0 root.pem intermediate.pem"
    exit 1
}

# Function: Calculate and display certificate fingerprint
# Parameters:
#   $1 - Path to the certificate file
#   $2 - Certificate type (root or intermediate)
# Returns:
#   Prints certificate type and SHA-256 fingerprint in YAML format
get_fingerprint() {
    local cert_file=$1
    local cert_type=$2

    # Check if certificate file exists
    if [ ! -f "$cert_file" ]; then
        echo "Error: Certificate file '$cert_file' does not exist"
        exit 1
    fi

    # Validate if the file is a valid PEM format certificate
    # Redirect stderr to /dev/null to suppress OpenSSL error messages
    if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        echo "Error: '$cert_file' is not a valid PEM format certificate"
        exit 1
    fi

    # Calculate SHA-256 fingerprint using OpenSSL
    # Cut the output to only get the fingerprint value after the '=' character
    local fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d'=' -f2)
    
    # Output in YAML format for easy parsing
    echo "Certificate Type: $cert_type"
    echo "Fingerprint: SHA256:$fingerprint"
    echo "---"
}

# Validate number of command line arguments
if [ $# -ne 2 ]; then
    show_usage
fi

# Process and display certificate fingerprints
echo "Certificate Fingerprint Information:"
echo "---"
get_fingerprint "$1" "Root Certificate"
get_fingerprint "$2" "Intermediate Certificate"
```
```
- 2 if the CA's fingerprint is not the same, you need to import the CA's certificate to the trust config.
- 3 if the CA's fingerprint is the same, Maybe will throw an error. 
  - `description: "duplicate certificate submitted as a trust anchor"`
  - `description: "duplicate certificate submitted as an intermediate CA"`
- 4 如果使用update命令,那么为了确保服务可用,必须是全量的更新,也就是新增加的CA.里面需要包含所有的CA. 也就是已经导入过的CA.
- 5 具体命令如下
- 6 如下是一个例子
- gcloud command
```
gcloud certificate-manager trust-configs update ${TRUST_CONFIG_NAME?} \
  --description="Trust config for ${TRUST_CONFIG_NAME?}" \
  --location=global \
  --project=${PROJECT_ID?} \
  --trust-store=trust-anchors="a-root.pem;b-root.pem",intermediate-cas="a-int.pem,b-int.pem"
```