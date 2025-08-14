#!/bin/bash

# Configuration-based Load Testing Script
# Usage: ./config-based-test.sh [config.yaml]

set -e

CONFIG_FILE="${1:-load-test-config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Simple YAML parser (basic implementation)
parse_yaml() {
    local file="$1"
    local prefix="$2"
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Handle key-value pairs
        if [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            echo "${prefix}${key}=${value}"
        fi
    done < "$file"
}

# Load configuration
load_config() {
    print_status "Loading configuration from $CONFIG_FILE"
    
    # Parse YAML and set variables
    while IFS='=' read -r key value; do
        case "$key" in
            target_url) TARGET_URL="$value" ;;
            test_name) TEST_NAME="$value" ;;
        esac
    done < <(parse_yaml "$CONFIG_FILE")
    
    # Set defaults if not specified
    TARGET_URL="${TARGET_URL:-https://example.com}"
    TEST_NAME="${TEST_NAME:-Load Test}"
    
    print_success "Configuration loaded: $TEST_NAME"
    print_status "Target URL: $TARGET_URL"
}

# Extract scenarios from config
extract_scenarios() {
    local in_scenarios=false
    local scenario_name=""
    local scenario_duration=""
    local scenario_connections=""
    local scenario_rps=""
    
    while IFS= read -r line; do
        # Check if we're in scenarios section
        if [[ "$line" =~ ^scenarios: ]]; then
            in_scenarios=true
            continue
        fi
        
        # Exit scenarios section if we hit another top-level key
        if [[ "$in_scenarios" == true ]] && [[ "$line" =~ ^[a-zA-Z] ]]; then
            in_scenarios=false
        fi
        
        if [[ "$in_scenarios" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"?([^\"]+)\"? ]]; then
                scenario_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*duration:[[:space:]]*([0-9]+) ]]; then
                scenario_duration="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*connections:[[:space:]]*([0-9]+) ]]; then
                scenario_connections="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*rps:[[:space:]]*([0-9]+) ]]; then
                scenario_rps="${BASH_REMATCH[1]}"
                
                # We have a complete scenario
                if [[ -n "$scenario_name" && -n "$scenario_duration" && -n "$scenario_connections" && -n "$scenario_rps" ]]; then
                    echo "$scenario_name|$scenario_duration|$scenario_connections|$scenario_rps"
                    scenario_name=""
                    scenario_duration=""
                    scenario_connections=""
                    scenario_rps=""
                fi
            fi
        fi
    done < "$CONFIG_FILE"
}

# Run a single scenario
run_scenario() {
    local name="$1"
    local duration="$2"
    local connections="$3"
    local rps="$4"
    
    print_status "Running scenario: $name"
    print_status "Duration: ${duration}s, Connections: $connections, RPS: $rps"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_dir="./test-results/${name// /_}_$timestamp"
    mkdir -p "$output_dir"
    
    # Run with wrk if available
    if command -v wrk &> /dev/null; then
        print_status "Running wrk test..."
        wrk -c "$connections" -d "${duration}s" -t 4 "$TARGET_URL" > "$output_dir/wrk_results.txt" 2>&1
    fi
    
    # Run with hey if available
    if command -v hey &> /dev/null; then
        print_status "Running hey test..."
        local total_requests=$((rps * duration))
        hey -n "$total_requests" -c "$connections" -q "$rps" "$TARGET_URL" > "$output_dir/hey_results.txt" 2>&1
    fi
    
    # Generate scenario summary
    cat > "$output_dir/scenario_summary.md" << EOF
# Scenario: $name

**Configuration:**
- Duration: ${duration}s
- Connections: $connections
- Target RPS: $rps
- URL: $TARGET_URL
- Timestamp: $(date)

## Results

EOF
    
    if [[ -f "$output_dir/wrk_results.txt" ]]; then
        echo "### wrk Results" >> "$output_dir/scenario_summary.md"
        echo '```' >> "$output_dir/scenario_summary.md"
        cat "$output_dir/wrk_results.txt" >> "$output_dir/scenario_summary.md"
        echo '```' >> "$output_dir/scenario_summary.md"
        echo "" >> "$output_dir/scenario_summary.md"
    fi
    
    if [[ -f "$output_dir/hey_results.txt" ]]; then
        echo "### hey Results" >> "$output_dir/scenario_summary.md"
        echo '```' >> "$output_dir/scenario_summary.md"
        cat "$output_dir/hey_results.txt" >> "$output_dir/scenario_summary.md"
        echo '```' >> "$output_dir/scenario_summary.md"
    fi
    
    print_success "Scenario '$name' completed. Results in: $output_dir"
}

# Main execution
main() {
    print_status "Starting configuration-based load testing..."
    
    load_config
    
    # Extract and run scenarios
    local scenario_count=0
    while IFS='|' read -r name duration connections rps; do
        if [[ -n "$name" ]]; then
            ((scenario_count++))
            run_scenario "$name" "$duration" "$connections" "$rps"
            
            # Wait between scenarios
            if [[ $scenario_count -gt 1 ]]; then
                print_status "Waiting 30 seconds before next scenario..."
                sleep 30
            fi
        fi
    done < <(extract_scenarios)
    
    if [[ $scenario_count -eq 0 ]]; then
        print_warning "No scenarios found in configuration file"
        print_status "Running default test..."
        run_scenario "Default Test" "60" "10" "50"
    fi
    
    print_success "All scenarios completed!"
}

main "$@"