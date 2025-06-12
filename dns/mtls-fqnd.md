```bash
#!/opt/homebrew/bin/bash

# Domain mapping configuration
declare -A DOMAIN_MAP=(
  ["ppd-uk"]="api-platform-pprd.business.hsbc.co.uk"
  ["ppd-hk"]="api-platform-pprd.business.hsbc.com.hk"
  ["ppd-in"]="api-platform.business.hsbc.co.in"
  ["dev-hk"]="api-platform-dev.business.hsbc.com.hk"
  ["sit-hk"]="api-platform-sit.business.hsbc.com.hk"
  ["uat-hk"]="api-platform-uat.business.hsbc.com.hk"
  ["prd-hk"]="api-platform.business.hsbc.com.hk"
  ["prd-uk"]="api-platform.business.hsbc.co.uk"
  ["prd-in"]="api-platform.business.hsbc.co.in"
)

# Usage function
show_usage() {
  echo "Usage: $0 <environment>"
  echo "Available environments:"
  for env in "${!DOMAIN_MAP[@]}"; do
    echo "  $env -> ${DOMAIN_MAP[$env]}"
  done
  exit 1
}

# Check parameters
if [[ $# -eq 0 ]]; then
  echo "Error: No environment specified."
  show_usage
fi

ENV_KEY="$1"
DOMAIN="${DOMAIN_MAP[$ENV_KEY]}"

# Validate environment parameter
if [[ -z "$DOMAIN" ]]; then
  echo "Error: Unknown environment '$ENV_KEY'"
  show_usage
fi

# Create log file
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="${ENV_KEY}_${TIMESTAMP}.log"
touch "$LOG_FILE"

# Define log function, output to both screen and log file
log() {
  echo "$1"
  echo "$1" >>"$LOG_FILE"
}

log "Starting DNS monitoring for environment: $ENV_KEY"
log "Domain: $DOMAIN"
log "Log file: $LOG_FILE"
log "========================================================"

# Get NS records for the domain
log "Fetching NS records for domain: $DOMAIN"
TRACE_RESULT=$(/opt/homebrew/bin/dig @119.29.29.29 $DOMAIN +trace)

# Extract the main domain part
# For example: extract hsbc.co.uk from api-platform-pprd.business.hsbc.co.uk
MAIN_DOMAIN=$(echo "$DOMAIN" | grep -o '[^.]*\.[^.]*\.[^.]*$')
log "Main domain for NS lookup: $MAIN_DOMAIN"

# Extract NS records
DNS_SERVERS=()
log "Extracted NS servers:"

# Extract the last part of NS records from trace results
# First find the A record line, then extract NS records after it
A_RECORD_FOUND=false
while IFS= read -r line; do
  # Check if A record line is found
  if [[ "$A_RECORD_FOUND" == "false" && "$line" =~ $DOMAIN.*IN[[:space:]]+A[[:space:]] ]]; then
    A_RECORD_FOUND=true
    continue
  fi
  
  # If A record line is found, start extracting NS records
  if [[ "$A_RECORD_FOUND" == "true" && "$line" =~ $MAIN_DOMAIN.*IN[[:space:]]+NS[[:space:]] ]]; then
    NS_SERVER=$(echo "$line" | awk '{print $NF}' | sed 's/\.$//')
    DNS_SERVERS+=("$NS_SERVER")
    log "  - $NS_SERVER"
  fi
  
  # If Received line is encountered, NS record section ends
  if [[ "$A_RECORD_FOUND" == "true" && "$line" =~ \;\;[[:space:]]Received ]]; then
    break
  fi
done < <(echo "$TRACE_RESULT")

# If no NS records found, use default DNS servers
if [[ ${#DNS_SERVERS[@]} -eq 0 ]]; then
  log "No NS records found for $MAIN_DOMAIN, using default DNS servers"
  DNS_SERVERS=(
    "119.29.29.29"
    "114.114.114.114"
    "8.8.8.8"
  )
  for DNS in "${DNS_SERVERS[@]}"; do
    log "  - $DNS"
  done
fi

log "========================================================"

# Main loop
while true; do
  CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  log "==================== $CURRENT_TIME ===================="
  for DNS in "${DNS_SERVERS[@]}"; do
    # Query section
    log "Querying DNS: $DNS for domain: $DOMAIN (A record)"
    RESULT=$(/opt/homebrew/bin/dig @$DNS $DOMAIN A +short)
    NOCACHE_RESULT=$(dig @$DNS $DOMAIN A +short)

    log "Standard query result:"
    if [[ -z "$RESULT" ]]; then
      log "No response or empty result."
    else
      log "$RESULT"
    fi

    log "No-cache query result:"
    if [[ -z "$NOCACHE_RESULT" ]]; then
      log "No response or empty result."
    else
      log "$NOCACHE_RESULT"
    fi
    log "--------------------------------------------------"
  done
  sleep 5 # Control query frequency
done
```
