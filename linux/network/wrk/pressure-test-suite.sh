#!/bin/bash

# Comprehensive Pressure Testing Suite
# Usage: ./pressure-test-suite.sh <URL> [OPTIONS]

set -e

# Default values
URL=""
DURATION="60s"
CONNECTIONS=10
REQUESTS=1000
OUTPUT_DIR="./test-results"
TOOLS=("wrk" "ab" "hey")
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Help function
show_help() {
    cat << EOF
Comprehensive Pressure Testing Suite

Usage: $0 <URL> [OPTIONS]

OPTIONS:
    -d, --duration DURATION     Test duration (default: 60s)
    -c, --connections NUM       Number of connections (default: 10)
    -n, --requests NUM          Number of requests (default: 1000)
    -o, --output DIR           Output directory (default: ./test-results)
    -t, --tools TOOLS          Comma-separated tools to use (wrk,ab,hey,vegeta)
    -v, --verbose              Verbose output
    -h, --help                 Show this help

Examples:
    $0 https://example.com
    $0 https://example.com -d 300s -c 50 -n 5000
    $0 https://example.com -t wrk,hey -o /tmp/results

Supported Tools:
    wrk     - Modern HTTP benchmarking tool
    ab      - Apache Bench
    hey     - HTTP load generator
    vegeta  - HTTP load testing tool
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -c|--connections)
                CONNECTIONS="$2"
                shift 2
                ;;
            -n|--requests)
                REQUESTS="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -t|--tools)
                IFS=',' read -ra TOOLS <<< "$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$URL" ]]; then
                    URL="$1"
                else
                    print_error "Multiple URLs provided"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$URL" ]]; then
        print_error "URL is required"
        show_help
        exit 1
    fi
}

# Check if tool is installed
check_tool() {
    local tool=$1
    if command -v "$tool" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install missing tools (macOS)
install_tools() {
    print_status "Checking and installing missing tools..."
    
    for tool in "${TOOLS[@]}"; do
        if ! check_tool "$tool"; then
            print_warning "$tool not found. Installing..."
            case "$tool" in
                wrk)
                    if command -v brew &> /dev/null; then
                        brew install wrk
                    else
                        print_error "Please install Homebrew or wrk manually"
                        exit 1
                    fi
                    ;;
                ab)
                    print_status "ab (Apache Bench) should be available by default on macOS"
                    ;;
                hey)
                    if command -v brew &> /dev/null; then
                        brew install hey
                    else
                        print_error "Please install Homebrew or hey manually"
                        exit 1
                    fi
                    ;;
                vegeta)
                    if command -v brew &> /dev/null; then
                        brew install vegeta
                    else
                        print_error "Please install Homebrew or vegeta manually"
                        exit 1
                    fi
                    ;;
            esac
        else
            print_success "$tool is available"
        fi
    done
}

# Create output directory
setup_output() {
    mkdir -p "$OUTPUT_DIR"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    OUTPUT_DIR="$OUTPUT_DIR/test_$timestamp"
    mkdir -p "$OUTPUT_DIR"
    print_status "Results will be saved to: $OUTPUT_DIR"
}

# Run wrk test
run_wrk() {
    print_status "Running wrk test..."
    local output_file="$OUTPUT_DIR/wrk_results.txt"
    
    wrk -c "$CONNECTIONS" -d "$DURATION" "$URL" > "$output_file" 2>&1
    
    if [[ $VERBOSE == true ]]; then
        cat "$output_file"
    fi
    
    print_success "wrk test completed. Results saved to $output_file"
}

# Run Apache Bench test
run_ab() {
    print_status "Running Apache Bench test..."
    local output_file="$OUTPUT_DIR/ab_results.txt"
    
    ab -n "$REQUESTS" -c "$CONNECTIONS" "$URL" > "$output_file" 2>&1
    
    if [[ $VERBOSE == true ]]; then
        cat "$output_file"
    fi
    
    print_success "Apache Bench test completed. Results saved to $output_file"
}

# Run hey test
run_hey() {
    print_status "Running hey test..."
    local output_file="$OUTPUT_DIR/hey_results.txt"
    
    hey -n "$REQUESTS" -c "$CONNECTIONS" "$URL" > "$output_file" 2>&1
    
    if [[ $VERBOSE == true ]]; then
        cat "$output_file"
    fi
    
    print_success "hey test completed. Results saved to $output_file"
}

# Run vegeta test
run_vegeta() {
    print_status "Running vegeta test..."
    local output_file="$OUTPUT_DIR/vegeta_results.txt"
    local attack_file="$OUTPUT_DIR/vegeta_attack.bin"
    
    echo "GET $URL" | vegeta attack -duration="$DURATION" -connections="$CONNECTIONS" > "$attack_file"
    vegeta report "$attack_file" > "$output_file"
    
    if [[ $VERBOSE == true ]]; then
        cat "$output_file"
    fi
    
    print_success "vegeta test completed. Results saved to $output_file"
}

# Generate summary report
generate_summary() {
    print_status "Generating summary report..."
    local summary_file="$OUTPUT_DIR/summary.md"
    
    cat > "$summary_file" << EOF
# Load Test Summary Report

**Test Target:** $URL  
**Test Date:** $(date)  
**Duration:** $DURATION  
**Connections:** $CONNECTIONS  
**Requests:** $REQUESTS  

## Test Configuration
- Tools Used: ${TOOLS[*]}
- Output Directory: $OUTPUT_DIR

## Results

EOF

    for tool in "${TOOLS[@]}"; do
        if [[ -f "$OUTPUT_DIR/${tool}_results.txt" ]]; then
            echo "### $tool Results" >> "$summary_file"
            echo '```' >> "$summary_file"
            head -20 "$OUTPUT_DIR/${tool}_results.txt" >> "$summary_file"
            echo '```' >> "$summary_file"
            echo "" >> "$summary_file"
        fi
    done
    
    print_success "Summary report generated: $summary_file"
}

# Main execution
main() {
    parse_args "$@"
    
    print_status "Starting pressure test suite for: $URL"
    print_status "Configuration: Duration=$DURATION, Connections=$CONNECTIONS, Requests=$REQUESTS"
    
    install_tools
    setup_output
    
    # Run tests
    for tool in "${TOOLS[@]}"; do
        case "$tool" in
            wrk)
                if check_tool wrk; then
                    run_wrk
                fi
                ;;
            ab)
                if check_tool ab; then
                    run_ab
                fi
                ;;
            hey)
                if check_tool hey; then
                    run_hey
                fi
                ;;
            vegeta)
                if check_tool vegeta; then
                    run_vegeta
                fi
                ;;
            *)
                print_warning "Unknown tool: $tool"
                ;;
        esac
    done
    
    generate_summary
    print_success "All tests completed! Check results in: $OUTPUT_DIR"
}

# Run main function with all arguments
main "$@"