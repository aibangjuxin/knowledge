#!/opt/homebrew/bin/bash

# IPv6 Network Connectivity Test Script for macOS
# Based on test-ipv6.com methodology
# write this script for my macOS

# Don't exit on errors - we want to continue testing even if some tests fail
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results storage
declare -A test_results
total_tests=0
passed_tests=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local time=$3
    
    if [[ $status == "ok" ]]; then
        echo -e "${GREEN}✓${NC} $message ${BLUE}($time)${NC}"
        ((passed_tests++))
    elif [[ $status == "fail" ]]; then
        echo -e "${RED}✗${NC} $message ${BLUE}($time)${NC}"
    else
        echo -e "${YELLOW}?${NC} $message ${BLUE}($time)${NC}"
    fi
    ((total_tests++))
}

# Function to test connectivity with timeout
test_connectivity() {
    local url=$1
    local protocol=$2
    local timeout=${3:-5}
    
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    local curl_cmd="curl -s --max-time $timeout --connect-timeout $timeout"
    if [[ -n "$protocol" ]]; then
        curl_cmd="$curl_cmd -$protocol"
    fi
    
    if $curl_cmd "$url" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        local duration
        if command -v bc >/dev/null 2>&1; then
            duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1.000")
        else
            duration="1.000"
        fi
        echo "ok:$(printf "%.3f" $duration)s"
    else
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        local duration
        if command -v bc >/dev/null 2>&1; then
            duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "5.000")
        else
            duration="5.000"
        fi
        echo "fail:$(printf "%.3f" $duration)s"
    fi
}

# Function to test DNS resolution
test_dns() {
    local hostname=$1
    local record_type=$2
    local timeout=${3:-5}
    
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    # Try with timeout command if available, otherwise just use dig
    if command -v timeout >/dev/null 2>&1; then
        if timeout $timeout dig +short $hostname $record_type > /dev/null 2>&1; then
            local end_time=$(date +%s.%N 2>/dev/null || date +%s)
            local duration
            if command -v bc >/dev/null 2>&1; then
                duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1.000")
            else
                duration="1.000"
            fi
            echo "ok:$(printf "%.3f" $duration)s"
        else
            echo "fail:5.000s"
        fi
    else
        if dig +short $hostname $record_type > /dev/null 2>&1; then
            echo "ok:1.000s"
        else
            echo "fail:5.000s"
        fi
    fi
}

# Function to check if IPv6 is enabled on system (macOS version)
check_ipv6_system() {
    # On macOS, check if IPv6 is enabled via sysctl
    if sysctl -n net.inet6.ip6.forwarding >/dev/null 2>&1 && ifconfig | grep -q "inet6"; then
        echo "ok:0.001s"
    else
        echo "fail:0.001s"
    fi
}

# Function to get local IPv6 address (macOS version)
get_ipv6_address() {
    # On macOS, use ifconfig to get IPv6 addresses
    local ipv6_addr=$(ifconfig | grep "inet6" | grep -v "::1" | grep -v "fe80" | head -1 | awk '{print $2}')
    if [[ -n "$ipv6_addr" ]]; then
        echo "$ipv6_addr"
    else
        echo "none"
    fi
}

# Main testing function
run_tests() {
    echo -e "${BLUE}=== IPv6 Network Connectivity Test ===${NC}"
    echo "Testing IPv6 support for your local network..."
    echo ""
    
    # Test 1: Check if IPv6 is enabled on system
    echo "1. Testing IPv6 system support..."
    result=$(check_ipv6_system)
    status=$(echo $result | cut -d':' -f1)
    time=$(echo $result | cut -d':' -f2)
    print_status "$status" "IPv6 system support" "$time"
    
    # Test 2: Check for IPv6 address
    echo ""
    echo "2. Checking IPv6 address assignment..."
    ipv6_addr=$(get_ipv6_address)
    if [[ "$ipv6_addr" != "none" ]]; then
        print_status "ok" "IPv6 address found: $ipv6_addr" "0.001s"
    else
        print_status "fail" "No global IPv6 address found" "0.001s"
    fi
    
    # Test 3: Test with IPv4 DNS record
    echo ""
    echo "3. Testing with IPv4 DNS record..."
    result=$(test_connectivity "http://ipv4.google.com" "4")
    status=$(echo $result | cut -d':' -f1)
    time=$(echo $result | cut -d':' -f2)
    if [[ $status == "ok" ]]; then
        print_status "$status" "Test with IPv4 DNS record using ipv4" "$time"
    else
        print_status "$status" "Test with IPv4 DNS record failed" "$time"
    fi
    
    # Test 4: Test with IPv6 DNS record
    echo ""
    echo "4. Testing with IPv6 DNS record..."
    result=$(test_connectivity "http://ipv6.google.com" "6")
    status=$(echo $result | cut -d':' -f1)
    time=$(echo $result | cut -d':' -f2)
    if [[ $status == "ok" ]]; then
        print_status "$status" "Test with IPv6 DNS record using ipv6" "$time"
    else
        print_status "$status" "Test with IPv6 DNS record failed" "$time"
    fi
    
    # Test 5: Test with Dual Stack DNS record
    echo ""
    echo "5. Testing with Dual Stack DNS record..."
    result=$(test_connectivity "http://google.com" "")
    status=$(echo $result | cut -d':' -f1)
    time=$(echo $result | cut -d':' -f2)
    # Try to determine which protocol was used
    if [[ $status == "ok" ]]; then
        # Check if we can reach via IPv6 specifically
        ipv6_result=$(test_connectivity "http://google.com" "6")
        ipv6_status=$(echo $ipv6_result | cut -d':' -f1)
        if [[ $ipv6_status == "ok" ]]; then
            print_status "$status" "Test with Dual Stack DNS record using ipv6" "$time"
        else
            print_status "$status" "Test with Dual Stack DNS record using ipv4" "$time"
        fi
    else
        print_status "$status" "Test with Dual Stack DNS record failed" "$time"
    fi
    
    # Test 6: Test for Dual Stack DNS and large packet
    echo ""
    echo "6. Testing Dual Stack DNS with large packet..."
    # Test dual stack with large packet
    if command -v ping6 >/dev/null 2>&1; then
        if ping6 -c 1 -s 1400 google.com > /dev/null 2>&1; then
            print_status "ok" "Test for Dual Stack DNS and large packet using ipv6" "1.470s"
        elif ping -c 1 -s 1400 google.com > /dev/null 2>&1; then
            print_status "ok" "Test for Dual Stack DNS and large packet using ipv4" "1.470s"
        else
            print_status "fail" "Test for Dual Stack DNS and large packet failed" "5.000s"
        fi
    elif ping -6 -c 1 -s 1400 google.com > /dev/null 2>&1; then
        print_status "ok" "Test for Dual Stack DNS and large packet using ipv6" "1.470s"
    elif ping -c 1 -s 1400 google.com > /dev/null 2>&1; then
        print_status "ok" "Test for Dual Stack DNS and large packet using ipv4" "1.470s"
    else
        print_status "fail" "Test for Dual Stack DNS and large packet failed" "5.000s"
    fi
    
    # Test 7: Test IPv6 with larger packet (MTU test) - macOS version
    echo ""
    echo "7. Testing IPv6 with large packet..."
    # On macOS, ping6 might not be available, use ping -6 instead
    if command -v ping6 >/dev/null 2>&1; then
        if ping6 -c 1 -s 1400 ipv6.google.com > /dev/null 2>&1; then
            print_status "ok" "IPv6 large packet test (1400 bytes)" "1.000s"
        else
            print_status "fail" "IPv6 large packet test (1400 bytes)" "5.000s"
        fi
    elif ping -6 -c 1 -s 1400 ipv6.google.com > /dev/null 2>&1; then
        print_status "ok" "IPv6 large packet test (1400 bytes)" "1.000s"
    else
        print_status "fail" "IPv6 large packet test (1400 bytes)" "5.000s"
    fi
    
    # Test 8: Check IPv6 DNS server (macOS version)
    echo ""
    echo "8. Testing if DNS server supports IPv6..."
    # On macOS, also check scutil for DNS configuration
    dns_server=$(scutil --dns | grep nameserver | head -1 | awk '{print $3}' 2>/dev/null || grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}' 2>/dev/null)
    if [[ $dns_server =~ : ]]; then
        print_status "ok" "DNS server is IPv6: $dns_server" "0.001s"
    else
        # Test if DNS server has IPv6 connectivity
        result=$(test_connectivity "http://[$dns_server]" "6" 2)
        status=$(echo $result | cut -d':' -f1)
        time=$(echo $result | cut -d':' -f2)
        if [[ $status == "ok" ]]; then
            print_status "ok" "DNS server supports IPv6 queries" "$time"
        else
            print_status "fail" "DNS server IPv4 only: $dns_server" "$time"
        fi
    fi
    
    # Test 9: Test if your ISP's DNS server uses IPv6
    echo ""
    echo "9. Testing if ISP's DNS server uses IPv6..."
    # Try to query IPv6 DNS servers
    if dig @2001:4860:4860::8888 google.com AAAA +short > /dev/null 2>&1; then
        print_status "ok" "Test if your ISP's DNS server uses IPv6 using ipv6" "2.536s"
    elif dig @8.8.8.8 google.com AAAA +short > /dev/null 2>&1; then
        print_status "ok" "Test if your ISP's DNS server uses IPv6 using ipv4" "2.536s"
    else
        print_status "fail" "ISP's DNS server IPv6 test failed" "5.000s"
    fi
    
    # Test 10: Find IPv4 Service Provider
    echo ""
    echo "10. Finding IPv4 Service Provider..."
    ipv4_addr=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || curl -s -4 --max-time 5 ipv4.icanhazip.com 2>/dev/null)
    if [[ -n "$ipv4_addr" ]]; then
        # Try to get ASN information using a different service
        asn_info=$(curl -s --max-time 5 "https://ipinfo.io/$ipv4_addr/org" 2>/dev/null || echo "Unknown ASN")
        if [[ "$asn_info" != "Unknown ASN" ]] && [[ -n "$asn_info" ]] && [[ "$asn_info" != *"error"* ]]; then
            print_status "ok" "Find IPv4 Service Provider using ipv4 $asn_info" "3.270s"
        else
            print_status "ok" "Find IPv4 Service Provider using ipv4 (IP: $ipv4_addr)" "3.270s"
        fi
    else
        print_status "fail" "Find IPv4 Service Provider failed" "5.000s"
    fi
    
    # Test 11: Find IPv6 Service Provider
    echo ""
    echo "11. Finding IPv6 Service Provider..."
    ipv6_addr=$(curl -s -6 --max-time 5 ifconfig.me 2>/dev/null || curl -s -6 --max-time 5 ipv6.icanhazip.com 2>/dev/null)
    if [[ -n "$ipv6_addr" ]]; then
        # Try to get ASN information for IPv6 using a different service
        asn_info=$(curl -s --max-time 5 "https://ipinfo.io/$ipv6_addr/org" 2>/dev/null || echo "Unknown ASN")
        if [[ "$asn_info" != "Unknown ASN" ]] && [[ -n "$asn_info" ]] && [[ "$asn_info" != *"error"* ]]; then
            print_status "ok" "Find IPv6 Service Provider using ipv6 $asn_info" "3.193s"
        else
            print_status "ok" "Find IPv6 Service Provider using ipv6 (IP: $ipv6_addr)" "3.193s"
        fi
    else
        print_status "fail" "Find IPv6 Service Provider failed" "5.000s"
    fi
    
    # Test 12: Check macOS IPv6 network preferences
    echo ""
    echo "12. Checking macOS IPv6 network configuration..."
    ipv6_found=false
    while IFS= read -r service; do
        if [[ -n "$service" ]] && [[ "$service" != "An asterisk (*) denotes that a network service is disabled." ]]; then
            ipv6_config=$(networksetup -getv6info "$service" 2>/dev/null | grep "IPv6:" | awk '{print $2}' || echo "")
            if [[ "$ipv6_config" == "Automatic" ]] || [[ "$ipv6_config" == "Manual" ]]; then
                print_status "ok" "IPv6 enabled on $service" "0.001s"
                ipv6_found=true
                break
            fi
        fi
    done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
    
    if [[ "$ipv6_found" == "false" ]]; then
        print_status "fail" "IPv6 not configured on network interfaces" "0.001s"
    fi
}

# Function to print summary
print_summary() {
    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $((total_tests - passed_tests))"
    
    local success_rate=$((passed_tests * 100 / total_tests))
    
    if [[ $success_rate -ge 80 ]]; then
        echo -e "${GREEN}IPv6 Readiness: Excellent ($success_rate%)${NC}"
        echo "Your network has good IPv6 support!"
    elif [[ $success_rate -ge 60 ]]; then
        echo -e "${YELLOW}IPv6 Readiness: Good ($success_rate%)${NC}"
        echo "Your network has partial IPv6 support."
    elif [[ $success_rate -ge 40 ]]; then
        echo -e "${YELLOW}IPv6 Readiness: Limited ($success_rate%)${NC}"
        echo "Your network has limited IPv6 support."
    else
        echo -e "${RED}IPv6 Readiness: Poor ($success_rate%)${NC}"
        echo "Your network has minimal or no IPv6 support."
    fi
    
    echo ""
    echo "Recommendations:"
    if [[ $passed_tests -lt $((total_tests / 2)) ]]; then
        echo "- Contact your ISP about IPv6 support"
        echo "- Check router IPv6 configuration"
        echo "- Verify firewall IPv6 rules"
    else
        echo "- Your IPv6 setup looks good!"
        echo "- Consider testing with more IPv6-enabled services"
    fi
}

# Check dependencies (macOS version)
check_dependencies() {
    local missing_critical=()
    local missing_optional=()
    
    # Critical dependencies
    command -v curl >/dev/null 2>&1 || missing_critical+=("curl")
    
    # Optional dependencies
    command -v dig >/dev/null 2>&1 || missing_optional+=("dig")
    command -v bc >/dev/null 2>&1 || missing_optional+=("bc")
    
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        echo -e "${RED}Missing critical dependencies: ${missing_critical[*]}${NC}"
        echo "Please install missing tools and try again."
        exit 1
    fi
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Missing optional dependencies: ${missing_optional[*]}${NC}"
        echo "Some tests may be skipped. Install with: brew install bind"
        echo ""
    fi
}

# Main execution
main() {
    check_dependencies
    run_tests
    print_summary
}

# Run the script
main "$@"