#!/usr/bin/env bash
#===============================================================================
# gcp-linux-env.sh - Linux-specific GCP environment checker
#
# This script provides Linux-specific checks and configurations for GCP scripts.
# It verifies the Linux environment, installs necessary components, and provides
# diagnostic information.
#
# Usage:
#   ./linux-scripts/gcp-linux-env.sh [OPTIONS]
#
# Options:
#   --check       Run environment checks only
#   --install     Show installation instructions
#   --diagnose    Run full diagnostics
#   --help        Show this help
#-------------------------------------------------------------------------------

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# OS Detection
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$NAME $VERSION"
    elif [[ -f /etc/centos-release ]]; then
        cat /etc/centos-release
    elif [[ -f /etc/redhat-release ]]; then
        cat /etc/redhat-release
    elif [[ -f /etc/debian_version ]]; then
        echo "Debian $(cat /etc/debian_version)"
    else
        echo "Unknown Linux"
    fi
}

# Architecture
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "x86_64 (amd64)" ;;
        aarch64|arm64) echo "aarch64 (arm64)" ;;
        i386|i686) echo "i386 (x86)" ;;
        *) echo "$arch" ;;
    esac
}

show_help() {
    cat <<EOF
gcp-linux-env.sh - Linux-specific GCP environment checker

Usage:
    $0 [OPTIONS]

Options:
    --check       Run environment checks only (default)
    --install     Show installation instructions for current OS
    --diagnose    Run full diagnostics
    --help        Show this help

Examples:
    $0                  # Run checks
    $0 --install        # Show install instructions
    $0 --diagnose       # Full diagnostics

EOF
}

# Check basic environment
check_environment() {
    echo -e "${BLUE}=== Linux Environment ===${NC}"
    echo "OS: $(detect_os)"
    echo "Architecture: $(detect_arch)"
    echo "Kernel: $(uname -r)"
    echo "Shell: $SHELL ($BASH_VERSION)"
    echo ""
}

# Check required tools
check_tools() {
    echo -e "${BLUE}=== Required Tools ===${NC}"
    
    local tools=("gcloud" "git" "curl")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            version=$("$tool" --version 2>&1 | head -n1 || echo "installed")
            echo -e "${GREEN}[OK]${NC} $tool: $version"
        else
            echo -e "${RED}[MISSING]${NC} $tool"
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Missing tools: ${missing[*]}${NC}"
        echo "Run with --install to see installation instructions"
    fi
    echo ""
}

# Check optional tools
check_optional_tools() {
    echo -e "${BLUE}=== Optional Tools ===${NC}"
    
    local tools=("kubectl" "gsutil" "bq" "terraform" "ansible")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            version=$("$tool" version 2>&1 | head -n1 || echo "installed")
            echo -e "${GREEN}[OK]${NC} $tool: $version"
        else
            echo -e "${YELLOW}[NOT FOUND]${NC} $tool (optional)"
        fi
    done
    echo ""
}

# Check gcloud installation
check_gcloud() {
    echo -e "${BLUE}=== Google Cloud SDK ===${NC}"
    
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} gcloud not found"
        return 1
    fi
    
    # Check version
    local version
    version=$(gcloud --version 2>&1 | head -n1)
    echo -e "${GREEN}[OK]${NC} $version"
    
    # Check components
    echo ""
    echo "Installed components:"
    gcloud components list --format='table(name,version,state)' 2>/dev/null || echo "  (run 'gcloud components list' for details)"
    
    # Check for gke-gcloud-auth-plugin
    echo ""
    if gcloud components list 2>/dev/null | grep -q 'gke-gcloud-auth-plugin.*Installed'; then
        echo -e "${GREEN}[OK]${NC} gke-gcloud-auth-plugin installed"
    else
        echo -e "${YELLOW}[WARN]${NC} gke-gcloud-auth-plugin not installed (needed for kubectl)"
    fi
    echo ""
}

# Check gcloud configuration
check_gcloud_config() {
    echo -e "${BLUE}=== gcloud Configuration ===${NC}"
    
    # Account
    local account
    account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)
    if [[ -n "$account" ]]; then
        echo -e "${GREEN}[OK]${NC} Active account: $account"
    else
        echo -e "${RED}[ERROR]${NC} No active account"
        echo "Run: gcloud auth login"
    fi
    
    # Project
    local project
    project=$(gcloud config get-value project 2>/dev/null || true)
    if [[ -n "$project" ]]; then
        echo -e "${GREEN}[OK]${NC} Active project: $project"
    else
        echo -e "${RED}[ERROR]${NC} No active project"
        echo "Run: gcloud config set project PROJECT_ID"
    fi
    
    # Region/Zone
    local region zone
    region=$(gcloud config get-value compute/region 2>/dev/null || true)
    zone=$(gcloud config get-value compute/zone 2>/dev/null || true)
    
    if [[ -n "$region" ]]; then
        echo -e "${GREEN}[OK]${NC} Default region: $region"
    else
        echo -e "${YELLOW}[WARN]${NC} No default region set"
    fi
    
    if [[ -n "$zone" ]]; then
        echo -e "${GREEN}[OK]${NC} Default zone: $zone"
    else
        echo -e "${YELLOW}[WARN]${NC} No default zone set"
    fi
    echo ""
}

# Show installation instructions
show_install_instructions() {
    local os
    os=$(detect_os)
    
    echo -e "${BLUE}=== Installation Instructions for $os ===${NC}"
    echo ""
    
    case "$os" in
        *Ubuntu*|*Debian*)
            cat << 'EOF'
# Install Google Cloud SDK on Debian/Ubuntu

1. Add Cloud SDK distribution URI
   echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk-main" | \
       sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

2. Install the Cloud SDK
   sudo apt-get update
   sudo apt-get install google-cloud-sdk

3. Initialize
   gcloud init

# Optional components
   gcloud components install kubectl gsutil
   gcloud components install gke-gcloud-auth-plugin
EOF
            ;;
        *CentOS*|*Red*|*Fedora*)
            cat << 'EOF'
# Install Google Cloud SDK on CentOS/RHEL/Fedora

1. Create the repository file
   sudo tee /etc/yum.repos.d/google-cloud-sdk.repo << 'REPO'
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
REPO

2. Install the Cloud SDK
   sudo dnf install google-cloud-sdk

3. Initialize
   gcloud init
EOF
            ;;
        *Amazon*|*Alma*)
            cat << 'EOF'
# Install Google Cloud SDK on Amazon Linux 2 / AlmaLinux

1. Create the repository file
   sudo tee /etc/yum.repos.d/google-cloud-sdk.repo << 'REPO'
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
REPO

2. Install the Cloud SDK
   sudo yum install google-cloud-sdk

3. Initialize
   gcloud init
EOF
            ;;
        *)
            cat << 'EOF'
# Generic installation (works on most Linux distributions)

1. Download and extract the Cloud SDK
   curl https://sdk.cloud.google.com | bash

2. Source the initialization script
   source ~/.bashrc

3. Initialize
   gcloud init

# Or install to a custom location
   export CLOUDSDK_PYTHON=/usr/bin/python3
   curl https://sdk.cloud.google.com | bash
EOF
            ;;
    esac
    
    echo ""
    echo "After installation, authenticate with:"
    echo "  gcloud auth login"
    echo ""
    echo "Or use a service account:"
    echo "  gcloud auth activate-service-account --key-file=/path/to/key.json"
    echo ""
    echo "Set your project:"
    echo "  gcloud config set project YOUR_PROJECT_ID"
}

# Run diagnostics
run_diagnostics() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}     GCP Environment Diagnostics     ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
    
    check_environment
    check_tools
    check_optional_tools
    
    if command -v gcloud >/dev/null 2>&1; then
        check_gcloud
        check_gcloud_config
        
        echo -e "${BLUE}=== Testing API Access ===${NC}"
        
        # Test basic API access
        if gcloud projects list --format='value(projectId)' 2>/dev/null | head -n1 >/dev/null; then
            echo -e "${GREEN}[OK]${NC} Can list projects"
        else
            echo -e "${RED}[ERROR]${NC} Cannot list projects (permission issue)"
        fi
        
        # Test compute API
        local project
        project=$(gcloud config get-value project 2>/dev/null | head -n1 || true)
        if [[ -n "$project" ]]; then
            if gcloud compute instances list --format='value(name)' --limit=1 2>/dev/null >/dev/null; then
                echo -e "${GREEN}[OK]${NC} Can access Compute Engine API"
            else
                echo -e "${YELLOW}[WARN]${NC} Cannot access Compute Engine API (may be disabled or no permission)"
            fi
        fi
        
        # Test container API
        if gcloud container clusters list --format='value(name)' --limit=1 2>/dev/null >/dev/null; then
            echo -e "${GREEN}[OK]${NC} Can access GKE API"
        else
            echo -e "${YELLOW}[WARN]${NC} Cannot access GKE API (may be disabled or no permission)"
        fi
    else
        echo -e "${RED}[ERROR]${NC} gcloud not installed - cannot test API access"
    fi
    
    echo ""
    echo -e "${CYAN}======================================${NC}"
    echo "Diagnostics complete"
}

# Main
main() {
    local mode="check"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) mode="check" ;;
            --install) mode="install" ;;
            --diagnose) mode="diagnose" ;;
            --help|-h) show_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
        shift
    done
    
    case "$mode" in
        check)
            check_environment
            check_tools
            if command -v gcloud >/dev/null 2>&1; then
                check_gcloud
                check_gcloud_config
            fi
            ;;
        install)
            show_install_instructions
            ;;
        diagnose)
            run_diagnostics
            ;;
    esac
}

main "$@"
