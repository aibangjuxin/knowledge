# Pod Startup Measurement v5 - Enhancements

## What's New in v5

The v5 version brings significant enhancements over v4, adding live testing, polling, and export capabilities.

## New Features

### 1. **Live Polling** (`-p`, `--poll`)
- Waits for pod to become Ready before measuring
- Shows real-time progress during polling
- Configurable max probes and interval

```bash
./pod_measure_startup_enhanced_v5.sh -n default -p my-app-pod
```

### 2. **Live Probe Testing** (`--simulate`, `--live-test`)
- **Simulate mode**: Shows what the probe test would do
- **Live mode**: Actually tests the probe endpoint via port-forward

```bash
# Simulate
./pod_measure_startup_enhanced_v5.sh -n default --simulate my-app-pod

# Live test
./pod_measure_startup_enhanced_v5.sh -n default --live-test my-app-pod
```

### 3. **Millisecond Precision Timing**
- Uses `date +%s.%N` when available
- Accurate to nanoseconds on Linux
- Handles macOS/BSD date differences

### 4. **Export Capabilities**
- **JSON export**: Structured data for automation
- **CSV export**: Spreadsheet-friendly format
- Both formats with timestamps

```bash
# Export to JSON
./pod_measure_startup_enhanced_v5.sh -n default --export-json results.json my-app-pod

# Export to CSV
./pod_measure_startup_enhanced_v5.sh -n default --export-csv results.csv my-app-pod

# Export both
./pod_measure_startup_enhanced_v5.sh -n default --export my-app-pod
```

### 5. **Custom Probe Parameters**
- Override probe port: `--port 8080`
- Override probe path: `--path /health`
- Useful for testing different endpoints

```bash
./pod_measure_startup_enhanced_v5.sh -n default --live-test --port 8080 --path /healthz my-app-pod
```

### 6. **Verbose Logging** (`-v`, `--verbose`)
- Creates timestamped log file
- Shows detailed execution flow
- Debug information for troubleshooting

### 7. **Enhanced Error Handling**
- Better path resolution for commands
- Retry logic for live tests
- Graceful handling of missing timestamps

### 8. **Multi-container Support**
- Continue support for `-c` container index
- Works with all new features

```bash
./pod_measure_startup_enhanced_v5.sh -n prod -c 1 --live-test my-multi-pod
```

## Usage Examples

### Basic Usage
```bash
# Simple measurement
./pod_measure_startup_enhanced_v5.sh -n default my-app-pod
```

### Complete Analysis
```bash
# Poll, test, export, verbose
./pod_measure_startup_enhanced_v5.sh -n production \
  -p \
  --live-test \
  --export-json \
  --verbose \
  my-app-pod
```

### CI/CD Integration
```bash
# Automated with JSON output
./pod_measure_startup_enhanced_v5.sh -n staging --export-json ci-results.json my-app-pod

# Parse results
cat ci-results.json | jq '.measurements.startupTimeSeconds'
```

### Debugging Slow Startups
```bash
# Verbose with live testing
./pod_measure_startup_enhanced_v5.sh -n default --live-test --verbose my-slow-app
```

## Output Improvements

### Section 1-2: Pod & Container Info
- Shows pod phase and container status
- Alerts if container not started
- Suggests polling if needed

### Section 3: Probe Analysis
- Lists all configured probes
- Shows per-probe settings
- Calculates max startup time allowance

### Section 4: Endpoint Detection
- Smart probe selection (startup → readiness → liveness)
- Respects custom port/path overrides
- Shows full URL

### Section 5: Live Testing
- Performs actual HTTP calls
- Shows response codes and times
- Multiple retry attempts

### Section 6: Precise Timing
- Millisecond-precision results
- Timeline visualization
- Raw timestamp preservation

### Section 7: Recommendations
- Performance assessment (Excellent/Good/Mod/etc)
- 3 configuration approaches
- Slow/fast startup optimizations

## Comparison with v4

| Feature | v4 | v5 |
|---------|----|----|
| Basic measurement | ✓ | ✓ |
| Multi-container | ✓ | ✓ |
| Color output | ✓ | ✓ |
| Command resolution | ✓ | ✓ |
| **Live polling** | ✗ | **✓** |
| **Probe testing** | ✗ | **✓** |
| **Millisecond precision** | ✗ | **✓** |
| **Export features** | ✗ | **✓** |
| **Verbose logging** | ✗ | **✓** |
| **Custom parameters** | ✗ | **✓** |

## Technical Enhancements

### Timing Precision
```bash
# v4: Second precision only
date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "2025-12-18T10:00:00Z" +%s

# v5: Nanosecond precision when available
date -u +%s.%N  # Linux (GNU date)
```

### Port Forwarding
- Automatic port discovery
- Background process management
- Cleanup on completion

### Result Parsing
- JSON for structured data
- CSV for analysis
- Timestamped files

## File Size & Complexity

- v4: ~465 lines
- v5: ~680 lines (+46%)
- Added 6 new major functions
- Full backward compatibility

## Dependencies

### v4 Requirements
- kubectl, jq, grep/sed, date

### v5 Additional
- curl (for live testing)
- bc (for precise math)
- lsof (for port detection)

All automatically detected and resolved.

## Run Help

```bash
./pod_measure_startup_enhanced_v5.sh -h
```

Shows full usage with all options and examples.

---

## Quick Start

1. **Basic**:
   ```bash
   ./pod_measure_startup_enhanced_v5.sh -n default my-app
   ```

2. **Recommended**:
   ```bash
   ./pod_measure_startup_enhanced_v5.sh -n default -p --live-test --export my-app
   ```

3. **Automation**:
   ```bash
   ./pod_measure_startup_enhanced_v5.sh -n staging -p --export-json results.json my-app
   results=$(cat results.json | jq '.measurements.startupTimeSeconds')
   ```
