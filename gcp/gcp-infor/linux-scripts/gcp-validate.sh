#!/usr/bin/env bash
#===============================================================================
# gcp-validate.sh - Validate GCP scripts for Linux environment
#
# This script validates that all shell scripts in the project are:
# 1. Valid bash syntax
# 2. Have proper shebang
# 3. Are executable (or can be made executable)
# 4. Have no obvious issues
#
# Usage:
#   ./linux-scripts/gcp-validate.sh [--fix]
#
# Options:
#   --fix    Automatically fix common issues (add executable bit)
#   --help   Show this help
#-------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_scripts=0
valid_scripts=0
issues_found=0

# Options
auto_fix=false

show_help() {
    cat <<EOF
gcp-validate.sh - Validate GCP scripts for Linux environment

Usage:
    $0 [OPTIONS]

Options:
    --fix    Automatically fix common issues (add executable bit)
    --help   Show this help

Examples:
    $0                  # Run validation
    $0 --fix            # Run validation and fix issues

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix) auto_fix=true ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# Check if bash is available
check_bash() {
    echo -e "${BLUE}=== Checking Bash ===${NC}"
    if command -v bash >/dev/null 2>&1; then
        local version
        version=$(bash --version | head -n1)
        echo -e "${GREEN}[OK]${NC} Bash available: $version"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Bash not found"
        return 1
    fi
}

# Validate a single script
validate_script() {
    local script="$1"
    local relative="${script#$ROOT_DIR/}"
    local status=0
    
    ((total_scripts++))
    
    echo -e "\n${YELLOW}Checking:${NC} $relative"
    
    # Check if file exists
    if [[ ! -f "$script" ]]; then
        echo -e "${RED}[ERROR]${NC} File not found"
        ((issues_found++))
        return 1
    fi
    
    # Check shebang
    local shebang
    shebang=$(head -n1 "$script")
    if [[ ! "$shebang" =~ ^\#\! ]]; then
        echo -e "${RED}[ERROR]${NC} Missing shebang"
        ((issues_found++))
        status=1
    elif [[ "$shebang" == "#!/bin/sh" || "$shebang" == "#!/bin/dash" ]]; then
        echo -e "${YELLOW}[WARN]${NC} Uses POSIX sh instead of bash: $shebang"
    else
        echo -e "${GREEN}[OK]${NC} Shebang: $shebang"
    fi
    
    # Check syntax with bash -n
    if bash -n "$script" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Syntax valid"
    else
        echo -e "${RED}[ERROR]${NC} Syntax error"
        bash -n "$script" 2>&1 | head -n5
        ((issues_found++))
        status=1
    fi
    
    # Check for common issues
    if grep -q 'set -euo pipefail' "$script"; then
        echo -e "${GREEN}[OK]${NC} Uses strict error handling"
    fi
    
    # Check if executable
    if [[ -x "$script" ]]; then
        echo -e "${GREEN}[OK]${NC} Executable bit set"
    else
        echo -e "${YELLOW}[WARN]${NC} Not executable"
        if $auto_fix; then
            chmod +x "$script"
            echo -e "${GREEN}[FIXED]${NC} Added executable bit"
        fi
    fi
    
    return $status
}

# Find and validate all shell scripts
find_scripts() {
    echo -e "${BLUE}=== Finding Shell Scripts ===${NC}"
    
    local scripts=()
    
    # Find bash scripts
    while IFS= read -r -d '' script; do
        scripts+=("$script")
    done < <(find "$ROOT_DIR" -maxdepth 2 -type f -name "*.sh" -print0)
    
    # Find executable files without extension (common for gcpfetch)
    while IFS= read -r -d '' script; do
        # Skip if already found as .sh
        local found=false
        for s in "${scripts[@]:-}"; do
            if [[ "$s" == "$script" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            # Check if it's a shell script by reading first line
            if [[ -f "$script" ]] && head -n1 "$script" | grep -q '^#!'; then
                scripts+=("$script")
            fi
        fi
    done < <(find "$ROOT_DIR" -maxdepth 2 -type f -executable -print0)
    
    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[WARN]${NC} No shell scripts found"
        return
    fi
    
    echo "Found ${#scripts[@]} script(s)"
    
    for script in "${scripts[@]}"; do
        if validate_script "$script"; then
            ((valid_scripts++))
        fi
    done
}

# Check required commands
check_commands() {
    echo -e "\n${BLUE}=== Checking Required Commands ===${NC}"
    
    local required_cmds=("gcloud")
    local optional_cmds=("kubectl" "gsutil" "bq")
    
    for cmd in "${required_cmds[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}[OK]${NC} $cmd found"
        else
            echo -e "${YELLOW}[WARN]${NC} $cmd not found (required for full functionality)"
            ((issues_found++))
        fi
    done
    
    for cmd in "${optional_cmds[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}[OK]${NC} $cmd found"
        else
            echo -e "${YELLOW}[INFO]${NC} $cmd not found (optional)"
        fi
    done
}

# Check gcloud configuration
check_gcloud_config() {
    echo -e "\n${BLUE}=== Checking gcloud Configuration ===${NC}"
    
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${YELLOW}[SKIP]${NC} gcloud not installed"
        return
    fi
    
    # Check for active account
    local account
    account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)
    if [[ -n "$account" ]]; then
        echo -e "${GREEN}[OK]${NC} Active account: $account"
    else
        echo -e "${YELLOW}[WARN]${NC} No active account (run: gcloud auth login)"
        ((issues_found++))
    fi
    
    # Check for active project
    local project
    project=$(gcloud config get-value project 2>/dev/null || true)
    if [[ -n "$project" ]]; then
        echo -e "${GREEN}[OK]${NC} Active project: $project"
    else
        echo -e "${YELLOW}[WARN]${NC} No active project (run: gcloud config set project PROJECT_ID)"
        ((issues_found++))
    fi
}

# Summary
print_summary() {
    echo -e "\n${BLUE}=== Summary ===${NC}"
    echo "Total scripts checked: $total_scripts"
    echo "Valid scripts: $valid_scripts"
    
    if [[ $issues_found -gt 0 ]]; then
        echo -e "${YELLOW}Issues found: $issues_found${NC}"
        if $auto_fix; then
            echo -e "${GREEN}Some issues were automatically fixed${NC}"
        else
            echo -e "${YELLOW}Run with --fix to attempt automatic fixes${NC}"
        fi
    else
        echo -e "${GREEN}No critical issues found!${NC}"
    fi
    
    echo ""
    echo "Next steps:"
    echo "  1. Run preflight check:  ./assistant/gcp-preflight.sh"
    echo "  2. Run safe fetch:       ./assistant/gcpfetch-safe"
    echo "  3. Run full exploration: ./gcp-explore.sh"
}

# Main
main() {
    echo "GCP Scripts Validation for Linux"
    echo "================================="
    echo ""
    
    check_bash
    find_scripts
    check_commands
    check_gcloud_config
    print_summary
}

main "$@"
