#!/bin/bash
# Test script for pod_health_check_lib.sh

echo "Testing pod_health_check_lib.sh on macOS..."
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the library
source "${SCRIPT_DIR}/pod_health_check_lib.sh"

echo "✓ Library sourced successfully"
echo ""

# Test 1: Check version
echo "Test 1: Version check"
pod_health_check_lib_version
echo ""

# Test 2: Check command detection
echo "Test 2: Command paths"
echo "AWK_CMD:   $AWK_CMD"
echo "DATE_CMD:  $DATE_CMD"
echo "SLEEP_CMD: $SLEEP_CMD"
echo ""

# Test 3: Test awk
echo "Test 3: Test awk command"
echo "HTTP/1.1 200 OK" | $AWK_CMD '{print $2}'
echo ""

# Test 4: Test date
echo "Test 4: Test date command"
$DATE_CMD +%s
echo ""

# Test 5: Test sleep
echo "Test 5: Test sleep command"
echo -n "Sleeping 1 second... "
$SLEEP_CMD 1
echo "done"
echo ""

# Test 6: Check if kubectl is available
echo "Test 6: Check kubectl"
if command -v kubectl >/dev/null 2>&1; then
    echo "✓ kubectl is available"
    kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1
else
    echo "✗ kubectl is not available"
fi
echo ""

echo "All basic tests completed!"
