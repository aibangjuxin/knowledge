# GCE Dual NIC Nginx - Systemd Service Dependency Configuration

## Overview

This document provides detailed systemd service configurations to solve the race condition between Nginx startup and dual NIC route configuration in GCE environments. The solution ensures that Nginx only starts after all network routes are properly configured and verified.

### Key Components

- **Core Service Configuration**: 
  - `gce-dual-nic-routes.service`: The main route configuration service.
  - Nginx service override with proper dependencies.
  - A clear dependency chain: `network-online.target` → `route service` → `nginx.service`.
- **Production-Ready Scripts**:
  - Route setup script with error handling and logging.
  - Route verification with multiple validation layers.
  - Pre-Nginx check script for final validation.
  - Cleanup script for proper service shutdown.
- **Installation & Validation Tools**:
  - Automated installation script.
  - Configuration validation script.
  - Testing procedures and troubleshooting commands.

### Key Features

- **Robust Dependency Management**:
  - Hard dependency (`Requires=`) ensures Nginx won't start if routes fail.
  - Proper ordering (`After=`, `Before=`) guarantees the correct sequence.
  - Network readiness verification before route configuration.
- **Comprehensive Verification**:
  - Route existence checks.
  - Backend connectivity testing.
  - Gateway reachability validation.
  - Nginx configuration syntax verification.
- **Production Considerations**:
  - Detailed logging with systemd integration.
  - Idempotent operations (safe to run multiple times).
  - Proper error handling and timeouts.
  - Clean shutdown procedures.
- **Customization Support**:
  - Environment-specific configuration variables.
  - Modular script design for easy modification.
  - Comprehensive monitoring and troubleshooting tools.

This solution directly addresses the race condition issue by ensuring that network routes are fully configured and verified, and backend connectivity is confirmed, before Nginx starts accepting traffic. The configuration is production-ready and includes all the operational tools needed for deployment, monitoring, and troubleshooting.

## Architecture Summary

The solution implements the following dependency chain, guaranteeing a safe startup sequence.

```mermaid
graph LR
    A[network-online.target] --> B[gce-dual-nic-routes.service];
    B --> C[nginx.service];
```

This guarantees that:
1.  Network interfaces are online.
2.  Static routes are configured and verified.
3.  Backend connectivity is confirmed.
4.  Only then does Nginx start accepting traffic.

## Core Service Configurations

### 1. Network Route Service Configuration

This is the main route configuration service that Nginx will depend on.

**File**: `/etc/systemd/system/gce-dual-nic-routes.service`
```ini
[Unit]
Description=Configure GCE Dual NIC Static Routes for Nginx
Documentation=https://cloud.google.com/vpc/docs/multiple-network-interfaces
# Ensure network is fully online before starting
After=network-online.target
Wants=network-online.target
# This service must complete before Nginx starts
Before=nginx.service
# Conflict with shutdown to ensure clean shutdown
Conflicts=shutdown.target

[Service]
Type=oneshot
# Service remains "active" after completion
RemainAfterExit=yes
# Main route configuration script
ExecStart=/usr/local/bin/setup-dual-nic-routes.sh
# Verification script runs after main script
ExecStartPost=/usr/local/bin/verify-routes.sh
# Cleanup script for service stop
ExecStop=/usr/local/bin/cleanup-routes.sh
# Logging configuration
StandardOutput=journal
StandardError=journal
# Timeout for route configuration (30 seconds should be sufficient)
TimeoutStartSec=30
TimeoutStopSec=10
# Restart policy - don't restart automatically to avoid loops
Restart=no

[Install]
# Start this service at multi-user target
WantedBy=multi-user.target
```

### 2. Nginx Service Dependency Override

Configure Nginx to depend on the successful completion of the route service.

**File**: `/etc/systemd/system/nginx.service.d/10-dual-nic-dependency.conf`
```ini
[Unit]
Description=Nginx HTTP/Stream Proxy with Dual NIC Route Dependencies
# Nginx must start after route service completes successfully
After=gce-dual-nic-routes.service
# Hard dependency - if route service fails, don't start Nginx
Requires=gce-dual-nic-routes.service
# Additional network dependency for safety
After=network-online.target
Wants=network-online.target

[Service]
# Add pre-start verification
ExecStartPre=/usr/local/bin/pre-nginx-check.sh
# Enhanced logging for debugging
StandardOutput=journal
StandardError=journal
```

## Implementation Scripts

### 3. Main Route Setup Script

**File**: `/usr/local/bin/setup-dual-nic-routes.sh`
```bash
#!/bin/bash
set -euo pipefail

# Configuration - Adjust these values for your environment
PRIVATE_NETWORK="192.168.0.0"
PRIVATE_NETMASK="255.255.255.0"
PRIVATE_GATEWAY="192.168.1.1"
BACKEND_IP="192.168.64.33"
BACKEND_PORT="443"
PRIVATE_INTERFACE="eth1"

# Logging function with systemd integration
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | systemd-cat -t gce-dual-nic -p "$level"
}

# Function to check if route already exists
route_exists() {
    ip route show | grep -q "${PRIVATE_NETWORK}/24 via ${PRIVATE_GATEWAY}"
}

# Function to verify interface exists
check_interface() {
    if ! ip link show "$PRIVATE_INTERFACE" >/dev/null 2>&1; then
        log "err" "Private interface $PRIVATE_INTERFACE not found"
        return 1
    fi
    log "info" "Private interface $PRIVATE_INTERFACE verified"
    return 0
}

# Function to add static route
add_static_route() {
    if route_exists; then
        log "info" "Static route already exists: ${PRIVATE_NETWORK}/24 via ${PRIVATE_GATEWAY}"
        return 0
    fi

    log "info" "Adding static route: ${PRIVATE_NETWORK}/24 via ${PRIVATE_GATEWAY} dev ${PRIVATE_INTERFACE}"
    
    if ip route add "${PRIVATE_NETWORK}/24" via "$PRIVATE_GATEWAY" dev "$PRIVATE_INTERFACE"; then
        log "info" "Static route added successfully"
        return 0
    else
        log "err" "Failed to add static route"
        return 1
    fi
}

# Function to verify backend connectivity
verify_backend_connectivity() {
    log "info" "Verifying backend connectivity to ${BACKEND_IP}:${BACKEND_PORT}"
    
    local retries=3
    local delay=2
    
    for ((i=1; i<=retries; i++)); do
        if timeout 5 nc -z "$BACKEND_IP" "$BACKEND_PORT" 2>/dev/null; then
            log "info" "Backend connectivity verified (attempt $i/$retries)"
            return 0
        fi
        
        if [ $i -lt $retries ]; then
            log "warning" "Backend connectivity failed, retrying in ${delay}s (attempt $i/$retries)"
            sleep $delay
        fi
    done
    
    log "err" "Backend connectivity verification failed after $retries attempts"
    return 1
}

# Function to set up routing table rules (if needed)
setup_routing_rules() {
    # Add custom routing rules if your setup requires them
    # Example: ip rule add from 192.168.1.0/24 table 100
    log "info" "Setting up additional routing rules if needed"
    
    # Add your custom routing rules here
    # This is environment-specific
    
    return 0
}

# Main execution
main() {
    log "info" "Starting GCE dual NIC route configuration"
    
    # Step 1: Verify private interface exists
    if ! check_interface; then
        exit 1
    fi
    
    # Step 2: Set up routing rules
    if ! setup_routing_rules; then
        log "err" "Failed to set up routing rules"
        exit 1
    fi
    
    # Step 3: Add static route
    if ! add_static_route; then
        exit 1
    fi
    
    # Step 4: Verify backend connectivity
    if ! verify_backend_connectivity; then
        exit 1
    fi
    
    log "info" "GCE dual NIC route configuration completed successfully"
    
    # Create a marker file for other scripts to check
    touch /var/run/gce-dual-nic-routes-ready
    
    return 0
}

# Execute main function
main "$@"
```

### 4. Route Verification Script

**File**: `/usr/local/bin/verify-routes.sh`
```bash
#!/bin/bash
set -euo pipefail

# Configuration
PRIVATE_NETWORK="192.168.0.0"
PRIVATE_GATEWAY="192.168.1.1"
BACKEND_IP="192.168.64.33"
BACKEND_PORT="443"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | systemd-cat -t gce-dual-nic-verify -p "$level"
}

# Verification functions
verify_route_exists() {
    local expected_route="${PRIVATE_NETWORK}/24 via ${PRIVATE_GATEWAY}"
    
    if ip route show | grep -q "$expected_route"; then
        log "info" "✓ Route verified: $expected_route"
        return 0
    else
        log "err" "✗ Route missing: $expected_route"
        return 1
    fi
}

verify_gateway_reachable() {
    log "info" "Verifying gateway reachability: $PRIVATE_GATEWAY"
    
    if ping -c 1 -W 3 "$PRIVATE_GATEWAY" >/dev/null 2>&1; then
        log "info" "✓ Gateway reachable: $PRIVATE_GATEWAY"
        return 0
    else
        log "warning" "Gateway ping failed (may be normal if ICMP is blocked)"
        return 0  # Don't fail on ping - many gateways block ICMP
    fi
}

verify_backend_route() {
    log "info" "Verifying route to backend: $BACKEND_IP"
    
    local route_output
    route_output=$(ip route get "$BACKEND_IP" 2>/dev/null || echo "")
    
    if echo "$route_output" | grep -q "via $PRIVATE_GATEWAY"; then
        log "info" "✓ Backend route verified via correct gateway"
        return 0
    else
        log "err" "✗ Backend route not using expected gateway"
        log "info" "Route output: $route_output"
        return 1
    fi
}

verify_backend_connectivity() {
    log "info" "Final connectivity test to ${BACKEND_IP}:${BACKEND_PORT}"
    
    if timeout 5 nc -z "$BACKEND_IP" "$BACKEND_PORT" 2>/dev/null; then
        log "info" "✓ Backend connectivity confirmed"
        return 0
    else
        log "err" "✗ Backend connectivity failed"
        return 1
    fi
}

# Main verification
main() {
    log "info" "Starting route verification"
    
    local failed=0
    
    # Run all verifications
    verify_route_exists || ((failed++))
    verify_gateway_reachable || ((failed++))
    verify_backend_route || ((failed++))
    verify_backend_connectivity || ((failed++))
    
    if [ $failed -eq 0 ]; then
        log "info" "All route verifications passed successfully"
        echo "$(date -Iseconds)" > /var/run/gce-dual-nic-routes-verified
        return 0
    else
        log "err" "Route verification failed ($failed checks failed)"
        return 1
    fi
}

main "$@"
```

### 5. Pre-Nginx Check Script

**File**: `/usr/local/bin/pre-nginx-check.sh`
```bash
#!/bin/bash
set -euo pipefail

# Configuration
BACKEND_IP="192.168.64.33"
BACKEND_PORT="443"
NGINX_CONFIG="/etc/nginx/nginx.conf"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | systemd-cat -t pre-nginx-check -p "$level"
}

# Check if route service completed successfully
check_route_service_status() {
    log "info" "Checking route service status"
    
    if systemctl is-active --quiet gce-dual-nic-routes.service; then
        log "info" "✓ Route service is active"
    else
        log "err" "✗ Route service is not active"
        return 1
    fi
    
    # Check for marker files
    if [ -f /var/run/gce-dual-nic-routes-ready ] && [ -f /var/run/gce-dual-nic-routes-verified ]; then
        log "info" "✓ Route configuration markers found"
        return 0
    else
        log "err" "✗ Route configuration markers missing"
        return 1
    fi
}

# Verify Nginx configuration syntax
check_nginx_config() {
    log "info" "Verifying Nginx configuration syntax"
    
    if nginx -t 2>/dev/null; then
        log "info" "✓ Nginx configuration syntax is valid"
        return 0
    else
        log "err" "✗ Nginx configuration syntax error"
        nginx -t  # Show the error
        return 1
    fi
}

# Final connectivity test
final_connectivity_test() {
    log "info" "Final pre-start connectivity test"
    
    if timeout 3 nc -z "$BACKEND_IP" "$BACKEND_PORT" 2>/dev/null; then
        log "info" "✓ Backend is reachable before Nginx start"
        return 0
    else
        log "err" "✗ Backend unreachable before Nginx start"
        return 1
    fi
}

# Main function
main() {
    log "info" "Starting pre-Nginx checks"
    
    # Run all checks
    if ! check_route_service_status; then
        exit 1
    fi
    
    if ! check_nginx_config; then
        exit 1
    fi
    
    if ! final_connectivity_test; then
        exit 1
    fi
    
    log "info" "All pre-Nginx checks passed - ready to start Nginx"
    return 0
}

main "$@"
```

### 6. Cleanup Script

**File**: `/usr/local/bin/cleanup-routes.sh`
```bash
#!/bin/bash
set -euo pipefail

# Configuration
PRIVATE_NETWORK="192.168.0.0"
PRIVATE_GATEWAY="192.168.1.1"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | systemd-cat -t gce-dual-nic-cleanup -p "$level"
}

# Remove static route
remove_static_route() {
    local route="${PRIVATE_NETWORK}/24 via ${PRIVATE_GATEWAY}"
    
    if ip route show | grep -q "$route"; then
        log "info" "Removing static route: $route"
        if ip route del "${PRIVATE_NETWORK}/24" via "$PRIVATE_GATEWAY" 2>/dev/null; then
            log "info" "Static route removed successfully"
        else
            log "warning" "Failed to remove static route (may already be gone)"
        fi
    else
        log "info" "Static route not present, nothing to remove"
    fi
}

# Clean up marker files
cleanup_markers() {
    log "info" "Cleaning up marker files"
    rm -f /var/run/gce-dual-nic-routes-ready
    rm -f /var/run/gce-dual-nic-routes-verified
}

# Main cleanup
main() {
    log "info" "Starting route cleanup"
    
    remove_static_route
    cleanup_markers
    
    log "info" "Route cleanup completed"
}

main "$@"
```

## Installation and Setup

### 7. Installation Script

Create an installation script to set up all components.

**File**: `/usr/local/bin/install-dual-nic-services.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Installing GCE Dual NIC Service Dependencies..."

# Create systemd service directory if it doesn't exist
mkdir -p /etc/systemd/system/nginx.service.d

# Make all scripts executable
chmod +x /usr/local/bin/setup-dual-nic-routes.sh
chmod +x /usr/local/bin/verify-routes.sh
chmod +x /usr/local/bin/pre-nginx-check.sh
chmod +x /usr/local/bin/cleanup-routes.sh

# Reload systemd daemon
systemctl daemon-reload

# Enable the route service
systemctl enable gce-dual-nic-routes.service

# Verify nginx service dependencies
echo "Checking Nginx service dependencies:"
systemctl list-dependencies nginx.service

echo "Installation completed successfully!"
echo ""
echo "To test the configuration:"
echo "1. sudo systemctl restart gce-dual-nic-routes.service"
echo "2. sudo systemctl restart nginx.service"
echo "3. sudo systemctl status gce-dual-nic-routes.service nginx.service"
```

### 8. Configuration Validation Script

**File**: `/usr/local/bin/validate-dual-nic-config.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "=== GCE Dual NIC Configuration Validation ==="
echo

# Check if all files exist
echo "1. Checking required files..."
files=(
    "/etc/systemd/system/gce-dual-nic-routes.service"
    "/etc/systemd/system/nginx.service.d/10-dual-nic-dependency.conf"
    "/usr/local/bin/setup-dual-nic-routes.sh"
    "/usr/local/bin/verify-routes.sh"
    "/usr/local/bin/pre-nginx-check.sh"
    "/usr/local/bin/cleanup-routes.sh"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing"
    fi
done

echo

# Check service status
echo "2. Checking service status..."
echo "Route service: $(systemctl is-enabled gce-dual-nic-routes.service 2>/dev/null || echo 'not enabled')"
echo "Nginx service: $(systemctl is-enabled nginx.service 2>/dev/null || echo 'not enabled')"

echo

# Check dependencies
echo "3. Checking service dependencies..."
systemctl list-dependencies nginx.service | grep -E "(gce-dual-nic-routes|network-online)"

echo

# Test configuration syntax
echo "4. Testing systemd configuration syntax..."
systemd-analyze verify /etc/systemd/system/gce-dual-nic-routes.service
systemd-analyze verify /etc/systemd/system/nginx.service.d/10-dual-nic-dependency.conf

echo
echo "Validation completed!"
```

## Usage and Testing

### 9. Testing the Configuration

```bash
# 1. Install all components
sudo /usr/local/bin/install-dual-nic-services.sh

# 2. Validate configuration
sudo /usr/local/bin/validate-dual-nic-config.sh

# 3. Test the service startup sequence
sudo systemctl stop nginx.service
sudo systemctl restart gce-dual-nic-routes.service
sudo systemctl start nginx.service

# 4. Check service status and logs
sudo systemctl status gce-dual-nic-routes.service nginx.service
sudo journalctl -u gce-dual-nic-routes.service -f
sudo journalctl -u nginx.service -f

# 5. Verify dependencies are working
sudo systemctl list-dependencies nginx.service
```

### 10. Monitoring and Troubleshooting

```bash
# Check if routes are properly configured
ip route show | grep "192.168.0.0/24"

# Test backend connectivity
nc -zv 192.168.64.33 443

# Check service dependency chain
systemctl show nginx.service | grep -E "(After|Requires|Wants)"

# View detailed service logs
journalctl -u gce-dual-nic-routes.service --no-pager
journalctl -u nginx.service --no-pager

# Check marker files
ls -la /var/run/gce-dual-nic-*
```

## Key Benefits

1.  **Guaranteed Startup Order**: Nginx will never start before routes are configured.
2.  **Robust Verification**: Multiple layers of verification ensure routes work correctly.
3.  **Proper Error Handling**: If route configuration fails, Nginx won't start.
4.  **Clean Shutdown**: Routes are properly cleaned up when the service stops.
5.  **Comprehensive Logging**: All operations are logged for debugging.
6.  **Idempotent Operations**: Scripts can be run multiple times safely.

## Customization Notes

- Adjust IP addresses and network ranges in the configuration variables.
- Modify timeout values based on your network latency.
- Add additional route verification steps if needed.
- Customize logging levels and destinations.
- Add environment-specific routing rules in the setup script.
