#!/bin/bash

# Advanced Load Testing with Real-time Monitoring
# Usage: ./advanced-load-test.sh <URL> [OPTIONS]

set -e

# Configuration
URL=""
DURATION="60"
CONNECTIONS=10
RPS=100
OUTPUT_DIR="./advanced-test-results"
MONITOR_INTERVAL=5
ENABLE_MONITORING=true

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--duration) DURATION="$2"; shift 2 ;;
        -c|--connections) CONNECTIONS="$2"; shift 2 ;;
        -r|--rps) RPS="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        --no-monitor) ENABLE_MONITORING=false; shift ;;
        -h|--help)
            cat << EOF
Advanced Load Testing Script

Usage: $0 <URL> [OPTIONS]

OPTIONS:
    -d, --duration SECONDS     Test duration in seconds (default: 60)
    -c, --connections NUM      Number of connections (default: 10)
    -r, --rps NUM             Requests per second (default: 100)
    -o, --output DIR          Output directory
    --no-monitor              Disable real-time monitoring
    -h, --help                Show this help

Examples:
    $0 https://example.com
    $0 https://example.com -d 300 -c 50 -r 500
EOF
            exit 0 ;;
        -*) print_error "Unknown option $1"; exit 1 ;;
        *) URL="$1"; shift ;;
    esac
done

[[ -z "$URL" ]] && { print_error "URL required"; exit 1; }

# Setup
timestamp=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="$OUTPUT_DIR/test_$timestamp"
mkdir -p "$OUTPUT_DIR"

# System monitoring function
monitor_system() {
    local monitor_file="$OUTPUT_DIR/system_metrics.csv"
    echo "timestamp,cpu_usage,memory_usage,network_rx,network_tx" > "$monitor_file"
    
    while [[ -f "$OUTPUT_DIR/.testing" ]]; do
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        local cpu=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
        local memory=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local network_stats=$(netstat -ib | grep -E "en0|en1" | head -1)
        local rx=$(echo "$network_stats" | awk '{print $7}')
        local tx=$(echo "$network_stats" | awk '{print $10}')
        
        echo "$timestamp,$cpu,$memory,$rx,$tx" >> "$monitor_file"
        sleep "$MONITOR_INTERVAL"
    done
}

# Real-time display function
display_realtime() {
    local results_file="$1"
    local start_time=$(date +%s)
    
    while [[ -f "$OUTPUT_DIR/.testing" ]]; do
        clear
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        echo "=== Load Test Progress ==="
        echo "URL: $URL"
        echo "Elapsed: ${elapsed}s / ${DURATION}s"
        echo "Progress: $(( (elapsed * 100) / DURATION ))%"
        echo ""
        
        if [[ -f "$results_file" ]]; then
            echo "=== Latest Results ==="
            tail -10 "$results_file" 2>/dev/null || echo "Waiting for results..."
        fi
        
        echo ""
        echo "Press Ctrl+C to stop test"
        sleep 2
    done
}

# K6 test script generator
generate_k6_script() {
    cat > "$OUTPUT_DIR/test.js" << EOF
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

export let errorRate = new Rate('errors');

export let options = {
    stages: [
        { duration: '${DURATION}s', target: $CONNECTIONS },
    ],
    thresholds: {
        http_req_duration: ['p(95)<500'],
        errors: ['rate<0.1'],
    },
};

export default function() {
    let response = http.get('$URL');
    
    let result = check(response, {
        'status is 200': (r) => r.status === 200,
        'response time < 500ms': (r) => r.timings.duration < 500,
    });
    
    errorRate.add(!result);
    sleep(1);
}
EOF
}

# Run comprehensive test
run_comprehensive_test() {
    print_status "Starting comprehensive load test..."
    
    # Create testing flag
    touch "$OUTPUT_DIR/.testing"
    
    # Start system monitoring if enabled
    if [[ "$ENABLE_MONITORING" == true ]]; then
        print_status "Starting system monitoring..."
        monitor_system &
        MONITOR_PID=$!
    fi
    
    # Test with multiple tools
    local test_results="$OUTPUT_DIR/test_results.txt"
    
    # wrk test
    if command -v wrk &> /dev/null; then
        print_status "Running wrk test..."
        echo "=== WRK Results ===" >> "$test_results"
        wrk -c "$CONNECTIONS" -d "${DURATION}s" -t 4 "$URL" >> "$test_results" 2>&1
        echo "" >> "$test_results"
    fi
    
    # hey test
    if command -v hey &> /dev/null; then
        print_status "Running hey test..."
        echo "=== HEY Results ===" >> "$test_results"
        hey -n $((RPS * DURATION)) -c "$CONNECTIONS" -q "$RPS" "$URL" >> "$test_results" 2>&1
        echo "" >> "$test_results"
    fi
    
    # k6 test
    if command -v k6 &> /dev/null; then
        print_status "Running k6 test..."
        generate_k6_script
        echo "=== K6 Results ===" >> "$test_results"
        k6 run "$OUTPUT_DIR/test.js" >> "$test_results" 2>&1
        echo "" >> "$test_results"
    fi
    
    # Cleanup
    rm -f "$OUTPUT_DIR/.testing"
    
    if [[ "$ENABLE_MONITORING" == true ]] && [[ -n "$MONITOR_PID" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
}

# Generate HTML report
generate_html_report() {
    local html_file="$OUTPUT_DIR/report.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Load Test Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .metric { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
        pre { background: #f8f8f8; padding: 15px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Load Test Report</h1>
        <div class="metric">
            <h3>Test Configuration</h3>
            <p><strong>URL:</strong> URL_PLACEHOLDER</p>
            <p><strong>Duration:</strong> DURATION_PLACEHOLDER seconds</p>
            <p><strong>Connections:</strong> CONNECTIONS_PLACEHOLDER</p>
            <p><strong>Target RPS:</strong> RPS_PLACEHOLDER</p>
            <p><strong>Test Date:</strong> DATE_PLACEHOLDER</p>
        </div>
        
        <div class="chart-container">
            <canvas id="metricsChart"></canvas>
        </div>
        
        <div class="metric">
            <h3>Detailed Results</h3>
            <pre id="results">RESULTS_PLACEHOLDER</pre>
        </div>
    </div>
    
    <script>
        // Sample chart - you can enhance this with real data
        const ctx = document.getElementById('metricsChart').getContext('2d');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: ['0s', '10s', '20s', '30s', '40s', '50s', '60s'],
                datasets: [{
                    label: 'Response Time (ms)',
                    data: [100, 120, 110, 130, 125, 115, 105],
                    borderColor: 'rgb(75, 192, 192)',
                    tension: 0.1
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
    </script>
</body>
</html>
EOF

    # Replace placeholders
    sed -i '' "s/URL_PLACEHOLDER/$URL/g" "$html_file"
    sed -i '' "s/DURATION_PLACEHOLDER/$DURATION/g" "$html_file"
    sed -i '' "s/CONNECTIONS_PLACEHOLDER/$CONNECTIONS/g" "$html_file"
    sed -i '' "s/RPS_PLACEHOLDER/$RPS/g" "$html_file"
    sed -i '' "s/DATE_PLACEHOLDER/$(date)/g" "$html_file"
    
    if [[ -f "$OUTPUT_DIR/test_results.txt" ]]; then
        local escaped_results=$(cat "$OUTPUT_DIR/test_results.txt" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        sed -i '' "s/RESULTS_PLACEHOLDER/$escaped_results/g" "$html_file"
    fi
    
    print_success "HTML report generated: $html_file"
}

# Main execution
main() {
    print_status "Advanced Load Test Starting..."
    print_status "Target: $URL"
    print_status "Configuration: ${DURATION}s, ${CONNECTIONS} connections, ${RPS} RPS"
    
    # Start real-time display in background
    display_realtime "$OUTPUT_DIR/test_results.txt" &
    DISPLAY_PID=$!
    
    # Run the actual test
    run_comprehensive_test
    
    # Stop real-time display
    kill "$DISPLAY_PID" 2>/dev/null || true
    
    # Generate reports
    generate_html_report
    
    print_success "Test completed! Results in: $OUTPUT_DIR"
    print_status "Open $OUTPUT_DIR/report.html in your browser for detailed results"
}

main