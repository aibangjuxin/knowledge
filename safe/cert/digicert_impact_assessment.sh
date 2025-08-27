#!/bin/bash

# digicert_impact_assessment.sh - Comprehensive DigiCert EKU Impact Assessment
# This script helps identify certificates that will be affected by DigiCert's 
# October 1st, 2025 Client Authentication EKU removal
#
# Version: 2.0
# Dependencies: check_eku.sh (automatically located)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
REPORT_FILE="digicert_impact_report_$(date +%Y%m%d_%H%M%S).txt"
AFFECTED_CERTS_FILE="affected_certificates.txt"

# Help
show_help() {
    echo "DigiCert EKU Impact Assessment Tool v2.0"
    echo ""
    echo "Usage: $0 [options] [domains_or_files...]"
    echo ""
    echo "Options:"
    echo "  -f, --file FILE        Read domains/files from file (one per line)"
    echo "  -o, --output FILE      Output report file (default: auto-generated)"
    echo "  -c, --checker PATH     Path to check_eku.sh script (auto-detected if not specified)"
    echo "  -v, --verbose          Verbose output"
    echo "  -q, --quiet            Quiet mode (only show summary)"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 example.com api.example.com"
    echo "  $0 -f domains.txt"
    echo "  $0 /path/to/certs/*.crt"
    echo "  $0 example.com:443 /path/to/cert.crt"
    echo "  $0 -c /custom/path/check_eku.sh example.com"
    echo ""
    echo "The script will automatically locate check_eku.sh in common locations:"
    echo "  - Same directory as this script"
    echo "  - Current working directory"
    echo "  - ./safe/cert/ directory"
    echo "  - System PATH"
    echo ""
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
DigiCert Client Authentication EKU Impact Assessment Report
Generated: $(date)
========================================================

SUMMARY:
- DigiCert will remove Client Authentication EKU from new certificates starting October 1st, 2025
- This assessment identifies certificates that will be affected
- Action is required for DigiCert certificates with Client Authentication EKU

ASSESSMENT RESULTS:
EOF
}

# Add to report
add_to_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Check single target
check_target() {
    local target="$1"
    local verbose="$2"
    local eku_checker="$3"
    
    echo -e "${BLUE}Checking: $target${NC}"
    
    # Run the enhanced EKU checker and capture output
    local check_output
    if check_output=$("$eku_checker" "$target" 2>&1); then
        echo "$check_output"
        
        # Parse results for summary
        if echo "$check_output" | grep -q "CRITICAL.*DigiCert.*Client Authentication"; then
            echo "$target - CRITICAL: DigiCert with Client Auth EKU" >> "$AFFECTED_CERTS_FILE"
            return 2  # Critical
        elif echo "$check_output" | grep -q "DigiCert.*without Client Authentication"; then
            return 1  # DigiCert but compliant
        else
            return 0  # Not DigiCert or not affected
        fi
    else
        echo -e "${RED}Error checking $target${NC}"
        return 3  # Error
    fi
}

# Main assessment
main() {
    local verbose=false
    local quiet=false
    local input_file=""
    local custom_checker=""
    local targets=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--file)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                REPORT_FILE="$2"
                shift 2
                ;;
            -c|--checker)
                custom_checker="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    
    # Find the EKU checker script
    local eku_checker=""
    
    if [ -n "$custom_checker" ]; then
        # Use custom checker path
        if [ -f "$custom_checker" ]; then
            if [ -x "$custom_checker" ]; then
                eku_checker="$custom_checker"
            else
                chmod +x "$custom_checker"
                eku_checker="$custom_checker"
            fi
        else
            echo -e "${RED}Error: Custom checker '$custom_checker' not found${NC}"
            exit 1
        fi
    else
        # Auto-detect checker location
        local possible_locations=(
            "$(dirname "$0")/check_eku.sh"           # Same directory as this script
            "./check_eku.sh"                         # Current directory
            "./safe/cert/check_eku.sh"               # Original location
            "$(which check_eku.sh 2>/dev/null)"      # In PATH
        )
        
        for location in "${possible_locations[@]}"; do
            if [ -n "$location" ] && [ -f "$location" ]; then
                if [ -x "$location" ]; then
                    eku_checker="$location"
                    break
                else
                    chmod +x "$location" 2>/dev/null && eku_checker="$location" && break
                fi
            fi
        done
        
        if [ -z "$eku_checker" ]; then
            echo -e "${RED}Error: check_eku.sh not found${NC}"
            echo "Searched in the following locations:"
            for location in "${possible_locations[@]}"; do
                [ -n "$location" ] && echo "  - $location"
            done
            echo ""
            echo "Please:"
            echo "  1. Ensure check_eku.sh is available in one of these locations, or"
            echo "  2. Use -c option to specify custom path: $0 -c /path/to/check_eku.sh"
            exit 1
        fi
    fi
    
    if [ "$quiet" != true ]; then
        echo -e "${BLUE}Using EKU checker: $eku_checker${NC}"
    fi
    
    # Read from file if specified
    if [ -n "$input_file" ]; then
        if [ -f "$input_file" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] && targets+=("$line")
            done < "$input_file"
        else
            echo -e "${RED}Error: Input file '$input_file' not found${NC}"
            exit 1
        fi
    fi
    
    # Check if we have targets
    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "${RED}Error: No targets specified${NC}"
        show_help
        exit 1
    fi
    
    # Initialize files
    init_report
    > "$AFFECTED_CERTS_FILE"
    
    echo -e "${BOLD}DigiCert EKU Impact Assessment${NC}"
    echo -e "${BOLD}==============================${NC}"
    echo ""
    
    # Counters
    local total=0
    local critical=0
    local digicert_compliant=0
    local non_digicert=0
    local errors=0
    
    # Process each target
    for target in "${targets[@]}"; do
        echo "" | tee -a "$REPORT_FILE"
        echo "----------------------------------------" | tee -a "$REPORT_FILE"
        
        total=$((total + 1))
        
        if check_output=$(check_target "$target" "$verbose" "$eku_checker" 2>&1); then
            echo "$check_output" | tee -a "$REPORT_FILE"
            
            case $? in
                2) critical=$((critical + 1)) ;;
                1) digicert_compliant=$((digicert_compliant + 1)) ;;
                0) non_digicert=$((non_digicert + 1)) ;;
                3) errors=$((errors + 1)) ;;
            esac
        else
            echo "Error checking $target" | tee -a "$REPORT_FILE"
            errors=$((errors + 1))
        fi
        
        echo "" | tee -a "$REPORT_FILE"
    done
    
    # Generate summary
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${BOLD}ASSESSMENT SUMMARY${NC}" | tee -a "$REPORT_FILE"
    echo "==================" | tee -a "$REPORT_FILE"
    echo "Total certificates checked: $total" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    if [ $critical -gt 0 ]; then
        echo -e "${RED}🚨 CRITICAL - Action Required: $critical certificates${NC}" | tee -a "$REPORT_FILE"
        echo "   DigiCert certificates with Client Authentication EKU" | tee -a "$REPORT_FILE"
        echo "   These will be affected by the October 1st, 2025 change" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
    
    if [ $digicert_compliant -gt 0 ]; then
        echo -e "${GREEN}✅ DigiCert Compliant: $digicert_compliant certificates${NC}" | tee -a "$REPORT_FILE"
        echo "   DigiCert certificates already compliant (Server Auth only)" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
    
    if [ $non_digicert -gt 0 ]; then
        echo -e "${GREEN}✅ Non-DigiCert: $non_digicert certificates${NC}" | tee -a "$REPORT_FILE"
        echo "   Not affected by DigiCert EKU change" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
    
    if [ $errors -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Errors: $errors certificates${NC}" | tee -a "$REPORT_FILE"
        echo "   Could not be checked (connection issues, file not found, etc.)" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
    
    # Action items
    if [ $critical -gt 0 ]; then
        echo -e "${BOLD}IMMEDIATE ACTION REQUIRED${NC}" | tee -a "$REPORT_FILE"
        echo "=========================" | tee -a "$REPORT_FILE"
        echo "1. Review affected certificates listed in: $AFFECTED_CERTS_FILE" | tee -a "$REPORT_FILE"
        echo "2. Identify applications using mTLS with these certificates" | tee -a "$REPORT_FILE"
        echo "3. Plan for separate client authentication certificates" | tee -a "$REPORT_FILE"
        echo "4. Test new certificate configurations before renewal" | tee -a "$REPORT_FILE"
        echo "5. Update certificate renewal procedures" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
        
        echo -e "${BOLD}TIMELINE${NC}" | tee -a "$REPORT_FILE"
        echo "========" | tee -a "$REPORT_FILE"
        echo "- Before certificate renewal: Complete migration to separate certificates" | tee -a "$REPORT_FILE"
        echo "- October 1st, 2025: DigiCert stops including Client Auth EKU in new certificates" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    else
        echo -e "${GREEN}✅ No immediate action required${NC}" | tee -a "$REPORT_FILE"
        echo "All certificates are either non-DigiCert or already compliant" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
    
    echo "Full report saved to: $REPORT_FILE"
    if [ $critical -gt 0 ]; then
        echo "Affected certificates list: $AFFECTED_CERTS_FILE"
    fi
    
    # Exit code indicates severity
    if [ $critical -gt 0 ]; then
        exit 2  # Critical issues found
    elif [ $errors -gt 0 ]; then
        exit 1  # Some errors occurred
    else
        exit 0  # All good
    fi
}

# Run main function
main "$@"