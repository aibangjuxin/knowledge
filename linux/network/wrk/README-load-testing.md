# Load Testing Suite

A comprehensive collection of load testing tools and scripts for performance testing web applications and APIs.

## Available Tools

### 1. Basic wrk Usage (wrk.md)
Your current simple wrk command for basic load testing.

### 2. Comprehensive Pressure Test Suite (pressure-test-suite.sh)
Multi-tool testing with automatic tool installation and detailed reporting.

**Features:**
- Supports wrk, Apache Bench (ab), hey, and vegeta
- Automatic tool installation via Homebrew
- Configurable test parameters
- Detailed reporting with summary generation
- Verbose output option

**Usage:**
```bash
./pressure-test-suite.sh https://example.com
./pressure-test-suite.sh https://example.com -d 300s -c 50 -n 5000
./pressure-test-suite.sh https://example.com -t wrk,hey -o /tmp/results
```

### 3. Advanced Load Test (advanced-load-test.sh)
Real-time monitoring with system metrics and HTML reporting.

**Features:**
- Real-time progress display
- System resource monitoring (CPU, memory, network)
- Multiple testing tools integration
- HTML report generation with charts
- K6 script generation

**Usage:**
```bash
./advanced-load-test.sh https://example.com
./advanced-load-test.sh https://example.com -d 300 -c 50 -r 500
```

### 4. Configuration-Based Testing (config-based-test.sh)
YAML-driven testing with multiple scenarios.

**Features:**
- YAML configuration file support
- Multiple test scenarios
- Threshold definitions
- Automated scenario execution
- Detailed per-scenario reporting

**Usage:**
```bash
./config-based-test.sh load-test-config.yaml
```

## Tool Comparison

| Tool | Best For | Pros | Cons |
|------|----------|------|------|
| **wrk** | HTTP/HTTPS load testing | Fast, lightweight, scriptable | Limited protocol support |
| **Apache Bench (ab)** | Simple HTTP testing | Widely available, simple | Basic features only |
| **hey** | Modern HTTP testing | HTTP/2 support, good reporting | Go dependency |
| **vegeta** | Rate-controlled testing | Excellent rate control, JSON output | Learning curve |
| **k6** | Complex scenarios | JavaScript scripting, great reporting | Resource intensive |
| **Artillery** | Full-featured testing | Scenarios, plugins, WebSocket support | Node.js dependency |

## Installation

### macOS (Homebrew)
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install load testing tools
brew install wrk hey vegeta k6

# Apache Bench is included with macOS
```

### Manual Installation
```bash
# wrk (compile from source)
git clone https://github.com/wg/wrk.git
cd wrk && make

# hey (Go)
go install github.com/rakyll/hey@latest

# k6
brew install k6
# or
curl https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-macos-amd64.zip -L | tar xvs --strip-components 1
```

## Quick Start Examples

### Basic Load Test
```bash
# Test with 10 connections for 60 seconds
./pressure-test-suite.sh https://your-site.com -c 10 -d 60s

# Test with multiple tools
./pressure-test-suite.sh https://your-site.com -t wrk,hey,vegeta
```

### Advanced Monitoring
```bash
# Run with real-time monitoring
./advanced-load-test.sh https://your-site.com -d 300 -c 25 -r 100
```

### Scenario-Based Testing
```bash
# Edit load-test-config.yaml with your scenarios
./config-based-test.sh load-test-config.yaml
```

## Configuration Examples

### Custom wrk Script
```lua
-- Custom wrk script for POST requests
wrk.method = "POST"
wrk.body   = '{"key": "value"}'
wrk.headers["Content-Type"] = "application/json"
```

### K6 Advanced Script
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '2m', target: 0 },
  ],
};

export default function() {
  let response = http.get('https://your-api.com/endpoint');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
```

## Best Practices

1. **Start Small**: Begin with low load and gradually increase
2. **Monitor Resources**: Watch both client and server resources
3. **Use Realistic Data**: Test with production-like data and scenarios
4. **Test Different Endpoints**: Don't just test the homepage
5. **Consider Geographic Distribution**: Test from different locations
6. **Baseline First**: Establish baseline performance before optimization
7. **Test Regularly**: Include load testing in your CI/CD pipeline

## Troubleshooting

### Common Issues

**Connection Refused**
```bash
# Check if target is accessible
curl -I https://your-site.com

# Verify DNS resolution
nslookup your-site.com
```

**Too Many Open Files**
```bash
# Increase file descriptor limit
ulimit -n 65536
```

**SSL/TLS Issues**
```bash
# Test SSL connectivity
openssl s_client -connect your-site.com:443
```

### Performance Tuning

**Client-side Tuning**
```bash
# Increase system limits
echo 'kern.maxfiles=65536' | sudo tee -a /etc/sysctl.conf
echo 'kern.maxfilesperproc=65536' | sudo tee -a /etc/sysctl.conf
```

**Network Tuning**
```bash
# Check network settings
sysctl net.inet.tcp.msl
sysctl net.inet.ip.portrange.first
```

## Results Interpretation

### Key Metrics to Monitor

- **Requests/sec**: Throughput measure
- **Response Time**: Latency (p50, p95, p99)
- **Error Rate**: Percentage of failed requests
- **Connections**: Active connection count
- **CPU/Memory**: Resource utilization

### Sample Output Analysis
```
Running 1m test @ https://example.com
  4 threads and 50 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   123.45ms   67.89ms   2.34s    87.65%
    Req/Sec   456.78     123.45     789      76.54%
  27890 requests in 1.00m, 123.45MB read
Requests/sec:   465.15
Transfer/sec:     2.06MB
```

**Analysis:**
- Average latency: 123.45ms (good for web apps)
- 465 requests/sec throughput
- No errors reported
- Consistent performance (low stdev)

## Integration with CI/CD

### GitHub Actions Example
```yaml
name: Load Test
on: [push]
jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install tools
        run: |
          sudo apt-get update
          sudo apt-get install -y wrk
      - name: Run load test
        run: ./pressure-test-suite.sh ${{ secrets.TEST_URL }}
```

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review tool-specific documentation
3. Test with minimal configuration first
4. Monitor both client and server resources