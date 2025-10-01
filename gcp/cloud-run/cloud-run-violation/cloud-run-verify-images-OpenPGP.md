# Claude
```bash
#!/bin/bash

# Cloud Run Binary Authorization with OpenPGP Signing Script
# Author: Kiro AI Assistant
# Purpose: Sign and deploy Cloud Run images using OpenPGP keys

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables - modify according to your actual situation
PROJECT_ID="${PROJECT_ID:-your-project-id}"
ATTESTOR="${ATTESTOR:-attestor-cloud-run}"
NOTE_NAME="${NOTE_NAME:-note-cloud-run}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGION="${REGION:-us-central1}"
REPO_NAME="${REPO_NAME:-your-repo}"
IMAGE_NAME="${IMAGE_NAME:-your-app}"
GPG_USER_ID="${GPG_USER_ID:-attestor-cloud-run <admin@example.com>}"

# GPG related files
GPG_PUBLIC_KEY_FILE="public.gpg"
GPG_PRIVATE_KEY_FILE="private.gpg"
SIGNATURE_FILE="signature.pgp"

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Display configuration information
show_config() {
    print_header "Current Configuration"
    echo "PROJECT_ID: $PROJECT_ID"
    echo "ATTESTOR: $ATTESTOR"
    echo "NOTE_NAME: $NOTE_NAME"
    echo "IMAGE_TAG: $IMAGE_TAG"
    echo "REGION: $REGION"
    echo "REPO_NAME: $REPO_NAME"
    echo "IMAGE_NAME: $IMAGE_NAME"
    echo "GPG_USER_ID: $GPG_USER_ID"
    echo "Full Image Path: $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"
    echo
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check gpg
    if ! command -v gpg &> /dev/null; then
        print_error "GPG is not installed, please install GnuPG first"
        exit 1
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "Please run 'gcloud auth login' to authenticate first"
        exit 1
    fi
    
    # Set default project
    gcloud config set project $PROJECT_ID
    
    print_success "Prerequisites check passed"
}

# Generate GPG key pair
generate_gpg_keys() {
    print_header "Generating GPG Key Pair"
    
    # Check if key already exists
    if gpg --list-secret-keys "$GPG_USER_ID" &>/dev/null; then
        print_warning "GPG key already exists: $GPG_USER_ID"
        echo -n "Do you want to delete existing key and regenerate? (y/N): "
        read recreate_choice
        if [[ "$recreate_choice" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing GPG key..."
            gpg --batch --yes --delete-secret-keys "$GPG_USER_ID" 2>/dev/null || true
            gpg --batch --yes --delete-keys "$GPG_USER_ID" 2>/dev/null || true
        else
            print_info "Using existing GPG key"
            return
        fi
    fi
    
    print_info "Generating new GPG key: $GPG_USER_ID"
    
    # Generate GPG key (using RSA 4096 bits, more secure)
    gpg --batch --quick-generate-key "$GPG_USER_ID" rsa4096 sign 1y
    
    print_success "GPG key generation completed"
}

# Show GPG key fingerprint
show_gpg_fingerprint() {
    print_header "GPG Key Information"
    
    # Get key fingerprint
    GPG_FINGERPRINT=$(gpg --with-colons --fingerprint "$GPG_USER_ID" | grep fpr | head -n1 | cut -d: -f10)
    
    if [ -z "$GPG_FINGERPRINT" ]; then
        print_error "Unable to get GPG key fingerprint"
        exit 1
    fi
    
    print_info "GPG Key Fingerprint: $GPG_FINGERPRINT"
    
    # Show key details
    gpg --list-keys "$GPG_USER_ID"
    
    print_success "GPG key fingerprint retrieved successfully"
}

# Export GPG public key
export_gpg_public_key() {
    print_header "Exporting GPG Public Key"
    
    print_info "Exporting public key to file: $GPG_PUBLIC_KEY_FILE"
    gpg --armor --export "$GPG_USER_ID" > "$GPG_PUBLIC_KEY_FILE"
    
    print_info "Exporting private key to file: $GPG_PRIVATE_KEY_FILE (please store securely)"
    gpg --armor --export-secret-keys "$GPG_USER_ID" > "$GPG_PRIVATE_KEY_FILE"
    chmod 600 "$GPG_PRIVATE_KEY_FILE"
    
    print_success "GPG key export completed"
    print_warning "Please keep the private key file secure: $GPG_PRIVATE_KEY_FILE"
}

# Create Container Analysis Note
create_note() {
    print_header "Creating Container Analysis Note"
    
    # Check if Note already exists
    if gcloud container analysis notes describe $NOTE_NAME --project=$PROJECT_ID &>/dev/null; then
        print_warning "Note $NOTE_NAME already exists, skipping creation"
        return
    fi
    
    print_info "Creating Container Analysis Note: $NOTE_NAME"
    
    # Create temporary JSON file
    NOTE_JSON=$(mktemp)
    cat > "$NOTE_JSON" << EOF
{
  "name": "projects/$PROJECT_ID/notes/$NOTE_NAME",
  "attestationAuthority": {
    "hint": {
      "humanReadableName": "OpenPGP Attestor Note for $PROJECT_ID"
    }
  }
}
EOF
    
    # Create Note using REST API
    curl -s -X POST \
        "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes?noteId=$NOTE_NAME" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"$NOTE_JSON" > /dev/null
    
    rm "$NOTE_JSON"
    
    # Verify creation success
    if gcloud container analysis notes describe $NOTE_NAME --project=$PROJECT_ID &>/dev/null; then
        print_success "Container Analysis Note created successfully"
    else
        print_error "Container Analysis Note creation failed"
        exit 1
    fi
}

# Create Attestor
create_attestor() {
    print_header "Creating Binary Authorization Attestor"
    
    # Check if Attestor already exists
    if gcloud container binauthz attestors describe $ATTESTOR --project=$PROJECT_ID &>/dev/null; then
        print_warning "Attestor $ATTESTOR already exists"
        echo -n "Do you want to delete and recreate? (y/N): "
        read recreate_choice
        if [[ "$recreate_choice" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing Attestor..."
            gcloud container binauthz attestors delete $ATTESTOR --project=$PROJECT_ID --quiet
        else
            print_info "Using existing Attestor"
            return
        fi
    fi
    
    print_info "Creating Attestor: $ATTESTOR"
    gcloud container binauthz attestors create $ATTESTOR \
        --attestation-authority-note=$NOTE_NAME \
        --attestation-authority-note-project=$PROJECT_ID \
        --project=$PROJECT_ID \
        --quiet
    
    print_success "Attestor created successfully"
}

# Add OpenPGP public key to Attestor
add_pgp_key_to_attestor() {
    print_header "Adding OpenPGP Public Key to Attestor"
    
    if [ ! -f "$GPG_PUBLIC_KEY_FILE" ]; then
        print_error "Public key file does not exist: $GPG_PUBLIC_KEY_FILE"
        exit 1
    fi
    
    print_info "Adding GPG public key to Attestor: $ATTESTOR"
    gcloud container binauthz attestors public-keys add \
        --attestor=$ATTESTOR \
        --pgp-public-key-file=$GPG_PUBLIC_KEY_FILE \
        --project=$PROJECT_ID \
        --quiet
    
    print_success "OpenPGP public key added successfully"
}

# Verify public key mounting
verify_attestor_keys() {
    print_header "Verifying Attestor Public Key Configuration"
    
    print_info "Attestor details:"
    gcloud container binauthz attestors describe $ATTESTOR --project=$PROJECT_ID
    
    print_success "Attestor public key verification completed"
}

# Get image digest
get_image_digest() {
    print_header "Getting Image Digest"
    
    IMAGE_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"
    print_info "Getting image digest: $IMAGE_URL"
    
    IMAGE_DIGEST=$(gcloud container images describe "$IMAGE_URL" \
        --format='value(image_summary.digest)' 2>/dev/null)
    
    if [ -z "$IMAGE_DIGEST" ]; then
        print_error "Unable to get image digest, please confirm image exists: $IMAGE_URL"
        exit 1
    fi
    
    ARTIFACT_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST"
    print_success "Image Digest: $IMAGE_DIGEST"
    print_info "Full Image URL: $ARTIFACT_URL"
}

# Sign and upload attestation
sign_and_upload_attestation() {
    print_header "Signing Image and Uploading Attestation"
    
    print_info "Creating signature content..."
    
    # Create content to be signed (using image digest)
    SIGN_CONTENT="Binary Authorization attestation for $ARTIFACT_URL"
    echo "$SIGN_CONTENT" | gpg --armor --detach-sign --local-user "$GPG_FINGERPRINT" > "$SIGNATURE_FILE"
    
    if [ ! -f "$SIGNATURE_FILE" ]; then
        print_error "Signature file creation failed"
        exit 1
    fi
    
    print_info "Creating Binary Authorization attestation..."
    gcloud container binauthz attestations create \
        --artifact-url="$ARTIFACT_URL" \
        --attestor=$ATTESTOR \
        --pgp-key-fingerprint="$GPG_FINGERPRINT" \
        --signature-file="$SIGNATURE_FILE" \
        --project=$PROJECT_ID \
        --quiet
    
    # Clean up signature file
    rm -f "$SIGNATURE_FILE"
    
    print_success "Image signing and attestation upload completed"
}

# Verify attestation
verify_attestation() {
    print_header "Verifying Attestation"
    
    print_info "Listing all attestations:"
    gcloud container binauthz attestations list \
        --attestor=$ATTESTOR \
        --project=$PROJECT_ID
    
    print_info "Verifying attestation for specific image:"
    gcloud container binauthz attestations list \
        --attestor=$ATTESTOR \
        --artifact-url="$ARTIFACT_URL" \
        --project=$PROJECT_ID
    
    print_success "Attestation verification completed"
}

# Check Binary Authorization policy
check_binauthz_policy() {
    print_header "Checking Binary Authorization Policy"
    
    print_info "Exporting current policy:"
    gcloud binauthz policy export
    
    print_info "Testing policy evaluation:"
    gcloud binauthz policy evaluate \
        --image-url="$ARTIFACT_URL" \
        --project=$PROJECT_ID || true
    
    print_success "Policy check completed"
}

# Update Cloud Run service
update_cloud_run() {
    print_header "Updating Cloud Run Service"
    
    print_info "Deploying to Cloud Run: $IMAGE_NAME"
    print_info "Using image: $ARTIFACT_URL"
    
    # Check if service already exists
    if gcloud run services describe $IMAGE_NAME --region=$REGION --project=$PROJECT_ID &>/dev/null; then
        print_info "Updating existing Cloud Run service..."
        ACTION="updated"
    else
        print_info "Creating new Cloud Run service..."
        ACTION="created"
    fi
    
    gcloud run deploy $IMAGE_NAME \
        --image="$ARTIFACT_URL" \
        --region=$REGION \
        --platform=managed \
        --project=$PROJECT_ID \
        --allow-unauthenticated \
        --quiet
    
    print_success "Cloud Run service $ACTION successfully"
    
    # Get service URL
    SERVICE_URL=$(gcloud run services describe $IMAGE_NAME \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    print_info "Service URL: $SERVICE_URL"
}

# Clean up temporary files
cleanup() {
    print_header "Cleaning Up Temporary Files"
    
    # Ask whether to keep key files
    echo -n "Do you want to keep GPG key files? (Y/n): "
    read keep_keys
    if [[ ! "$keep_keys" =~ ^[Nn]$ ]]; then
        print_info "Keeping GPG key files: $GPG_PUBLIC_KEY_FILE, $GPG_PRIVATE_KEY_FILE"
    else
        rm -f "$GPG_PUBLIC_KEY_FILE" "$GPG_PRIVATE_KEY_FILE"
        print_info "Deleted GPG key files"
    fi
    
    # Clean up other temporary files
    rm -f "$SIGNATURE_FILE"
    
    print_success "Cleanup completed"
}

# Show usage help
show_help() {
    cat << EOF
Cloud Run Binary Authorization with OpenPGP Signing Script

Usage: $0 [options]

Environment Variables:
  PROJECT_ID    GCP Project ID (default: your-project-id)
  ATTESTOR      Attestor name (default: attestor-cloud-run)
  NOTE_NAME     Container Analysis Note name (default: note-cloud-run)
  IMAGE_TAG     Image tag (default: latest)
  REGION        GCP region (default: us-central1)
  REPO_NAME     Artifact Registry repository name (default: your-repo)
  IMAGE_NAME    Image name (default: your-app)
  GPG_USER_ID   GPG user ID (default: attestor-cloud-run <admin@example.com>)

Options:
  -h, --help    Show this help information
  --config      Show configuration information only
  --keys-only   Generate GPG keys only
  --sign-only   Sign image only (requires existing attestor and keys)
  --deploy-only Deploy to Cloud Run only (requires signed image)

Examples:
  # Full workflow
  PROJECT_ID=my-project REPO_NAME=my-repo IMAGE_NAME=my-app $0
  
  # Generate keys only
  $0 --keys-only
  
  # Sign only
  $0 --sign-only
  
  # Deploy only
  $0 --deploy-only

EOF
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        --config)
            show_config
            exit 0
            ;;
        --keys-only)
            print_header "OpenPGP Key Generation Mode"
            check_prerequisites
            show_config
            generate_gpg_keys
            show_gpg_fingerprint
            export_gpg_public_key
            print_success "GPG key generation completed!"
            exit 0
            ;;
        --sign-only)
            print_header "Image Signing Mode"
            check_prerequisites
            show_config
            show_gpg_fingerprint
            get_image_digest
            sign_and_upload_attestation
            verify_attestation
            print_success "Image signing completed!"
            exit 0
            ;;
        --deploy-only)
            print_header "Cloud Run Deployment Mode"
            check_prerequisites
            show_config
            get_image_digest
            update_cloud_run
            print_success "Cloud Run deployment completed!"
            exit 0
            ;;
        "")
            # Full workflow
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    print_header "Cloud Run Binary Authorization Full Workflow"
    
    # Execute full workflow
    check_prerequisites
    show_config
    
    # Confirm execution
    echo -n "Do you want to continue with the full workflow? (Y/n): "
    read confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    # Execute all steps
    generate_gpg_keys
    show_gpg_fingerprint
    export_gpg_public_key
    create_note
    create_attestor
    add_pgp_key_to_attestor
    verify_attestor_keys
    get_image_digest
    sign_and_upload_attestation
    verify_attestation
    check_binauthz_policy
    update_cloud_run
    cleanup
    
    print_success "All steps completed! Cloud Run service has been successfully deployed and verified through Binary Authorization."
}

# Execute main function
main "$@"
```


# ChatGPT  
👌 你整理的步骤基本正确，已经覆盖了 **OpenPGP 公钥方式签名镜像** 的完整流程，我帮你再优化一下细节，避免踩坑：

---

## **完整流程（OpenPGP + Binary Authorization）**

  

### **1. 生成 GPG 密钥对**

```
# 生成一对 GPG 密钥（2048位 RSA，仅用于签名，有效期1年）
gpg --quick-generate-key "attestor-cloud-run <admin@example.com>" rsa2048 sign 1y

# 导出公钥 (用于配置 attestor)
gpg --armor --export admin@example.com > public.gpg

# 导出私钥 (一定要安全存储，不要上传到 Git 或共享存储)
gpg --armor --export-secret-keys admin@example.com > private.gpg
```

✅ 建议：

- 公钥（public.gpg）可以放心公开。
    
- 私钥（private.gpg）要安全存放（比如 CI/CD 系统的 Secret Manager）。
    

---

### **2. 将 OpenPGP 公钥添加到 Attestor**

```
gcloud container binauthz attestors public-keys add \
  --attestor=attestor-cloud-run \
  --pgp-public-key-file=public.gpg \
  --project=$PROJECT_ID
```

⚠️ 注意：

- 一个 attestor 可以绑定多个公钥，支持多人/多系统签名。
    
- 这里绑定后，Binary Authorization 会用这个公钥去验证签名。
    

---

### **3. 使用 GPG 私钥签名镜像**

  

#### **获取镜像 Digest**

```
gcloud container images describe \
  $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:tag \
  --format='value(image_summary.digest)'
```

假设结果：

```
sha256:abcd1234ef5678...
```

---

#### **获取 GPG 密钥指纹**

```
GPG_FINGERPRINT=$(gpg --with-colons --fingerprint admin@example.com \
  | grep fpr | head -n1 | cut -d: -f10)
```

---

#### **创建签名文件**

```
echo -n "sha256:abcd1234ef5678..." \
  | gpg --armor --detach-sign --local-user $GPG_FINGERPRINT \
  > signature.pgp
```

这里一定要签 **镜像的 digest**（sha256:...），而不是 tag，否则校验会失败。

---

### **4. 创建 Attestation**

```
gcloud container binauthz attestations create \
  --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@sha256:abcd1234ef5678... \
  --attestor=attestor-cloud-run \
  --pgp-key-fingerprint=$GPG_FINGERPRINT \
  --signature-file=signature.pgp \
  --project=$PROJECT_ID
```

这一步会把签名写入 **Container Analysis API**，Cloud Run 部署时就能验证。

---

### **5. 验证 Attestation**

```
gcloud container binauthz attestations list \
  --attestor=attestor-cloud-run \
  --project=$PROJECT_ID
```

你应该能看到该 digest 对应的签名。

---

## **对比：OpenPGP vs Cloud KMS 签名**

|**签名方式**|**优势**|**缺点**|**适用场景**|
|---|---|---|---|
|**OpenPGP (GPG)**|通用、独立于云厂商、可脱机使用|私钥管理风险较大，需要自己保存/分发|多云/混合云，已有 PGP 基础设施|
|**Cloud KMS**|私钥托管在 GCP，权限控制、审计清晰，无需管理密钥文件|仅限 GCP，无法离线使用|只跑在 GCP，追求运维简化和安全性|

---

✅ 总结：

- 你写的步骤完全正确，只要确保签名内容是 **镜像 digest** 就没问题。
    
- OpenPGP 好处是跨平台，但在 CI/CD 里维护私钥可能麻烦；如果完全跑在 GCP，建议直接用 **Cloud KMS**。
    

---

要不要我帮你写一份 **对比流程图**（OpenPGP vs Cloud KMS 签名在 Binary Authorization 里的流程）？这样你一眼就能看到签名/验证的差别。