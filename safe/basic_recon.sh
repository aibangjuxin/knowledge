#!/bin/bash

# A simple shell script for basic domain reconnaissance based on the kali.md document.

# --- Color Codes for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Check for Input ---
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <domain.com>${NC}"
    exit 1
fi

# --- Variables ---
DOMAIN=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Use an absolute path for the output directory to be safe
OUTPUT_DIR="/Users/lex/git/knowledge/safe/recon_${DOMAIN}_${TIMESTAMP}"

# --- Start Script ---
echo -e "${GREEN}[+] Starting basic reconnaissance for: ${DOMAIN}${NC}"
echo -e "${GREEN}[+] Output will be saved in: ${OUTPUT_DIR}${NC}"

# --- Create Output Directory ---
mkdir -p ${OUTPUT_DIR}

# --- 1. WHOIS Lookup ---
echo -e "\n${YELLOW}[*] Performing WHOIS lookup...${NC}"
whois ${DOMAIN} > ${OUTPUT_DIR}/whois.txt
echo -e "${GREEN}[+] WHOIS lookup complete.${NC}"

# --- 2. DNS Enumeration (dig) ---
echo -e "\n${YELLOW}[*] Performing DNS record analysis with dig...${NC}"
{
    echo "--- A Records (IP Address) ---"
    dig ${DOMAIN} A +short
    echo -e "\n--- MX Records (Mail Servers) ---"
    dig ${DOMAIN} MX +short
    echo -e "\n--- NS Records (Name Servers) ---"
    dig ${DOMAIN} NS +short
    echo -e "\n--- TXT Records (SPF, etc.) ---"
    dig ${DOMAIN} TXT
} > ${OUTPUT_DIR}/dns_records.txt
echo -e "${GREEN}[+] DNS analysis complete.${NC}"

# --- 3. Subdomain Enumeration (dnsrecon) ---
echo -e "\n${YELLOW}[*] Enumerating subdomains with dnsrecon (standard scan)...${NC}"
dnsrecon -d ${DOMAIN} -t std > ${OUTPUT_DIR}/dnsrecon.txt
echo -e "${GREEN}[+] Subdomain enumeration complete.${NC}"

# --- 4. Port Scanning (nmap) ---
echo -e "\n${YELLOW}[*] Scanning for open ports and services with Nmap (top 1000 ports)...${NC}"
nmap -sV -T4 ${DOMAIN} > ${OUTPUT_DIR}/nmap_scan.txt
echo -e "${GREEN}[+] Nmap scan complete.${NC}"

# --- 5. Web Technology Identification (whatweb) ---
echo -e "\n${YELLOW}[*] Identifying web technologies with WhatWeb...${NC}"
whatweb ${DOMAIN} > ${OUTPUT_DIR}/whatweb.txt
echo -e "${GREEN}[+] WhatWeb scan complete.${NC}"

# --- 6. SSL/TLS Scan (sslscan) ---
echo -e "\n${YELLOW}[*] Scanning SSL/TLS configuration with sslscan...${NC}"
sslscan ${DOMAIN} > ${OUTPUT_DIR}/ssl_scan.txt
echo -e "${GREEN}[+] SSL/TLS scan complete.${NC}"

# --- Final Message ---
echo -e "\n${GREEN}[+] Basic reconnaissance script finished.${NC}"
echo -e "${GREEN}[+] All results are saved in the '${OUTPUT_DIR}' directory.${NC}"
