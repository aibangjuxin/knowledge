# Kubernetes Library Functions

This directory contains reusable shell function libraries for Kubernetes operations.

## 🎉 Latest Update: v1.0.2 - macOS Compatibility Fixed!

**Fixed issues on macOS:**
- ✅ `awk: command not found`
- ✅ `date: command not found`
- ✅ `sleep: command not found`
- ✅ Integer comparison errors

See [MACOS_FIX.md](MACOS_FIX.md) for details.

## 📦 Available Libraries

### pod_health_check_lib.sh (v1.0.2)

A comprehensive library for Pod health checking using `openssl` and `nc` to verify HTTP/HTTPS endpoints directly inside Pods.

**Now fully compatible with macOS (Apple Silicon & Intel)!**

**Quick Start:**
```bash
# Source the library
source /path/to/pod_health_check_lib.sh

# Basic health check
STATUS=$(check_pod_health "my-pod" "production" "HTTPS" "8443" "/health")
if [ $? -eq 0 ]; then
    echo "Pod is healthy: $STATUS"
fi
```

**Key Functions:**
- `check_pod_health` - Basic health check
- `check_pod_health_with_retry` - Health check with retry
- `wait_for_pod_ready` - Wait for Pod to become ready
- `get_probe_config` - Extract probe configuration
- `extract_probe_endpoint` - Parse probe endpoint
- `calculate_max_startup_time` - Calculate max startup time
- `monitor_pod_health` - Continuous monitoring

**Documentation:**
- Full documentation: [../custom-liveness/explore-startprobe/openssl-verify-health.md](../custom-liveness/explore-startprobe/openssl-verify-health.md)
- Help: Run `pod_health_check_lib_help` after sourcing

## 🚀 Example Scripts

Scripts that use these libraries can be found in `../scripts/`:

- `measure_startup_simple.sh` - Measure Pod startup time
- `batch_health_check.sh` - Check multiple Pods at once

## 💡 Usage Pattern

```bash
#!/bin/bash

# 1. Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Source the library
source "${SCRIPT_DIR}/../lib/pod_health_check_lib.sh"

# 3. Use the functions
STATUS=$(check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health")
```

## 🔧 Requirements

- `kubectl` - Kubernetes CLI
- `jq` - JSON processor
- `bc` - Calculator (for some functions)
- Pod must have `openssl` (for HTTPS) or `nc` (for HTTP)

### Platform Support
- ✅ macOS (Apple Silicon & Intel) - **v1.0.2+**
- ✅ Linux (Ubuntu, Debian, RHEL, CentOS)
- ✅ Works with system bash (3.2+) and Homebrew bash (5.0+)

## 🧪 Testing

Run the test script to verify everything works:
```bash
./test_lib.sh
```

## 📚 Learn More

For detailed documentation, examples, and best practices, see:
- [MACOS_FIX.md](MACOS_FIX.md) - macOS compatibility guide
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [openssl-verify-health.md](../custom-liveness/explore-startprobe/openssl-verify-health.md) - Complete guide
