# Changelog - Pod Health Check Library

## Version 1.0.4 (2024-12-16)

### Fixed - CRITICAL BUG
- **PATH Variable Collision** 🐛
  - Fixed critical bug where using `PATH` as variable name overwrote system PATH
  - Changed all instances of `PATH` variable to `PROBE_PATH`
  - This was causing "command not found" errors for awk, date, sleep
  - Affected files:
    - `k8s/scripts/measure_startup_simple.sh`
    - `k8s/scripts/batch_health_check.sh`

### Technical Details

**The Problem:**
```bash
# This breaks system PATH!
read SCHEME PORT PATH <<< "HTTP 80 /health"
# Now PATH="/health" instead of "/usr/bin:/bin:..."
# Commands not found!
```

**The Solution:**
```bash
# Use PROBE_PATH instead
read SCHEME PORT PROBE_PATH <<< "HTTP 80 /health"
# System PATH preserved, everything works!
```

See [CRITICAL_BUG_FIX.md](CRITICAL_BUG_FIX.md) for full details.

---

## Version 1.0.3 (2024-12-16)

### Changed
- **Simplified Command Detection**
  - Now uses direct hardcoded paths with intelligent fallback
  - Checks for Homebrew gdate first (Apple Silicon & Intel)
  - Falls back to standard paths if Homebrew not found
  - Added `SLEEP_CMD` variable for consistency
  - Removed complex `command -v` detection logic

### Improved
- **Better macOS Support**
  - Explicitly checks `/opt/homebrew/bin/gdate` (Apple Silicon)
  - Explicitly checks `/usr/local/bin/gdate` (Intel Mac)
  - More predictable behavior across different Mac configurations

### Technical Details

**Command Paths:**
```bash
# Apple Silicon Mac with Homebrew
DATE_CMD="/opt/homebrew/bin/gdate"
AWK_CMD="/usr/bin/awk"
SLEEP_CMD="/bin/sleep"

# Intel Mac with Homebrew
DATE_CMD="/usr/local/bin/gdate"
AWK_CMD="/usr/bin/awk"
SLEEP_CMD="/bin/sleep"

# Standard macOS/Linux
DATE_CMD="/bin/date"
AWK_CMD="/usr/bin/awk"
SLEEP_CMD="/bin/sleep"
```

**Fallback Logic:**
```bash
[ ! -x "$DATE_CMD" ] && DATE_CMD="date"
[ ! -x "$AWK_CMD" ] && AWK_CMD="awk"
[ ! -x "$SLEEP_CMD" ] && SLEEP_CMD="sleep"
```

---

## Version 1.0.2 (2024-12-16)

### Fixed
- **macOS Compatibility Issues**
  - Fixed `awk: command not found` error on macOS
  - Fixed `date: command not found` error on macOS
  - Fixed `sleep: command not found` error on macOS
  - Added Homebrew path (`/opt/homebrew/bin`) to PATH
  - Implemented dynamic command detection for `awk` and `date`
  - Fixed integer comparison error with `-1` return value

### Changed
- **Command Detection**
  - Now automatically detects `gawk` vs `awk`
  - Now automatically detects `gdate` vs `date`
  - Uses `command -v` for better cross-platform detection
  - Removed hardcoded paths like `/usr/bin/awk` and `/bin/date`

### Technical Details

**Before:**
```bash
http_code=$(echo "$http_status_line" | /usr/bin/awk '{print $2}')
start_time=$(/bin/date +%s)
/bin/sleep "$interval"
```

**After:**
```bash
# Auto-detect commands at library load time
if command -v gawk >/dev/null 2>&1; then
    AWK_CMD="gawk"
elif command -v awk >/dev/null 2>&1; then
    AWK_CMD="awk"
else
    AWK_CMD="/usr/bin/awk"
fi

# Use detected commands
http_code=$(echo "$http_status_line" | $AWK_CMD '{print $2}')
start_time=$($DATE_CMD +%s)
sleep "$interval"
```

**PATH Enhancement:**
```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

### Testing
- Tested on macOS with Homebrew bash (`/opt/homebrew/bin/bash`)
- Tested with standard macOS utilities
- Verified command detection works correctly

---

## Version 1.0.1 (2024-12-16)

### Added
- Initial PATH setup to include standard locations
- Basic cross-platform support

### Fixed
- Initial command path issues

---

## Version 1.0.0 (2024-12-16)

### Added
- Initial release
- 9 core functions for Pod health checking
- HTTP and HTTPS support
- Retry mechanisms
- Wait for ready functionality
- Probe configuration extraction
- Monitoring capabilities
- Comprehensive documentation

### Functions
1. `check_pod_health` - Basic health check
2. `check_pod_health_with_retry` - Health check with retry
3. `wait_for_pod_ready` - Wait for Pod to become ready
4. `get_probe_config` - Extract probe configuration
5. `extract_probe_endpoint` - Parse probe endpoint
6. `calculate_max_startup_time` - Calculate max startup time
7. `monitor_pod_health` - Continuous monitoring
8. `check_pod_exists` - Check if Pod exists
9. `get_pod_status` - Get Pod phase status

### Documentation
- Complete technical guide (42KB)
- Usage examples and patterns
- Quick start guide
- Troubleshooting guide

---

## Upgrade Guide

### From 1.0.0/1.0.1 to 1.0.2

No breaking changes. Simply replace the library file:

```bash
# Backup old version
cp k8s/lib/pod_health_check_lib.sh k8s/lib/pod_health_check_lib.sh.bak

# Download/copy new version
# (replace with your update method)

# Test
source k8s/lib/pod_health_check_lib.sh
pod_health_check_lib_version
```

### Verification

After upgrading, verify the library works:

```bash
# Run test script
k8s/lib/test_lib.sh

# Expected output:
# Testing pod_health_check_lib.sh on macOS...
# ✓ Library sourced successfully
# Pod Health Check Library v1.0.2
# AWK_CMD: awk (or gawk)
# DATE_CMD: date (or gdate)
```

---

## Known Issues

### macOS Specific
- None currently

### Linux Specific
- None currently

### General
- Requires `kubectl` to be configured and connected to a cluster
- Requires Pod to have `openssl` (for HTTPS) or `nc` (for HTTP)
- Some container images may not have these tools installed

---

## Roadmap

### Future Enhancements
- [ ] TCP health checks (non-HTTP services)
- [ ] gRPC support
- [ ] Custom header support in main functions
- [ ] Response body validation
- [ ] Metrics export (Prometheus format)
- [ ] Multi-container Pod support
- [ ] Parallel batch checking

### Community Requests
- Submit issues or feature requests via your team's process

---

## Support

### Getting Help
1. Check documentation: `openssl-verify-health.md`
2. Run help command: `pod_health_check_lib_help`
3. Check version: `pod_health_check_lib_version`
4. Run test script: `k8s/lib/test_lib.sh`

### Reporting Issues
When reporting issues, please include:
- Library version (`pod_health_check_lib_version`)
- Operating system and version
- Shell version (`bash --version`)
- Error messages
- Steps to reproduce

---

**Maintained by:** DevOps Team  
**License:** Internal Use  
**Repository:** k8s/lib/
