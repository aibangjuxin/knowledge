#!/bin/bash

# Script Name: domain_intel.sh
# Description: A comprehensive domain reconnaissance script based on the workflow from kali.md
#              and inspired by the structure of explorer-domain-claude.sh.
# Usage: ./domain_intel.sh <domain.com>

# --- Configuration ---
set -o pipefail

# --- Color Codes for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_header() {
    echo -e "\n${BLUE}\
============================================================${NC}"
    echo -e "${PURPLE}>> $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Required command not found: $1. Please install it.${NC}"
        exit 1
    fi
}

# --- Argument Check ---
if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 <domain>${NC}"
    echo -e "${YELLOW}Example: $0 example.com${NC}"
    exit 1
fi

# --- Variables ---
DOMAIN=$(echo "$1" | sed -e 's|^https\?://||' -e 's|/.*||')
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="/Users/lex/git/knowledge/safe/report_${DOMAIN}_${TIMESTAMP}.txt"
GOBUSTER_WORDLIST="/usr/share/wordlists/dirb/common.txt"

# --- Prerequisite Check ---
REQUIRED_CMDS=("whois" "dig" "nmap" "whatweb" "sslscan" "gobuster" "tee")
for cmd in "${REQUIRED_CMDS[@]}"; do
    check_command "$cmd"
done

# --- Main Execution ---
echo -e "${GREEN}[+] Starting Comprehensive Domain Intel Script for: ${DOMAIN}${NC}"
echo -e "${GREEN}[+] Report will be saved to: ${OUTPUT_FILE}${NC}"
sleep 2


# Redirect all subsequent output to both console and the report file
exec &> >(tee -a "$OUTPUT_FILE")


echo "Domain Intelligence Report for: $DOMAIN"
echo "Generated on: $(date)"
echo "-------------------------------------------------"

# 1. WHOIS Lookup
print_header "Phase 1: WHOIS Information"
whois "$DOMAIN"
echo -e "${GREEN}[SUCCESS] WHOIS lookup complete.${NC}"

# 2. DNS Record Analysis
print_header "Phase 2: DNS Record Analysis (dig)"
{
    echo -e "\n--- A Records (IPv4) ---"
    dig "$DOMAIN" A +short
    echo -e "\n--- AAAA Records (IPv6) ---"
    dig "$DOMAIN" AAAA +short
    echo -e "\n--- MX Records (Mail Exchange) ---"
    dig "$DOMAIN" MX +short
    echo -e "\n--- NS Records (Name Servers) ---"
    dig "$DOMAIN" NS +short
    echo -e "\n--- TXT Records (SPF, DMARC, etc.) ---"
    dig "$DOMAIN" TXT
    echo -e "\n--- SOA Record (Start of Authority) ---"
    dig "$DOMAIN" SOA
} 
echo -e "${GREEN}[SUCCESS] DNS analysis complete.${NC}"

# 3. Port & Service Scanning
print_header "Phase 3: Port & Service Scanning (Nmap)"
echo "Scanning top 1000 ports and detecting service versions..."
nmap -sV -T4 "$DOMAIN"
echo -e "${GREEN}[SUCCESS] Nmap scan complete.${NC}"

# 4. Web Technology Stack Identification
print_header "Phase 4: Web Technology Stack (WhatWeb)"
whatweb "$DOMAIN"
echo -e "${GREEN}[SUCCESS] WhatWeb scan complete.${NC}"

# 5. SSL/TLS Configuration Scan
print_header "Phase 5: SSL/TLS Configuration (sslscan)"
sslscan "$DOMAIN"
echo -e "${GREEN}[SUCCESS] SSL/TLS scan complete.${NC}"

# 6. Hidden Directory & File Discovery
print_header "Phase 6: Directory Discovery (Gobuster)"
if [ ! -f "$GOBUSTER_WORDLIST" ]; then
    echo -e "${YELLOW}[WARNING] Gobuster wordlist not found at $GOBUSTER_WORDLIST. Skipping directory discovery.${NC}"
else
    echo "Starting Gobuster scan on http://${DOMAIN}. This may take a while..."
    gobuster dir -u "http://${DOMAIN}" -w "$GOBUSTER_WORDLIST" -t 30 -q --no-error
    echo "Starting Gobuster scan on https://${DOMAIN}. This may take a while..."
    gobuster dir -u "https://${DOMAIN}" -w "$GOBUSTER_WORDLIST" -t 30 -q --no-error -k
    echo -e "${GREEN}[SUCCESS] Gobuster scan complete.${NC}"
fi


# --- Final Message ---
print_header "Reconnaissance Complete"
echo "Domain analysis for $DOMAIN has finished."
echo "Full report saved to: $OUTPUT_FILE"
