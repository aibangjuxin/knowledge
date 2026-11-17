# Quick Start - Pod Health Check Library

## 🎯 What is This?

A shell function library that makes it easy to check Pod health in Kubernetes using the same `openssl s_client` and `nc` methods from your startup measurement scripts.

## ⚡ 30-Second Quick Start

```bash
# 1. Source the library
source k8s/lib/pod_health_check_lib.sh

# 2. Check a Pod
check_pod_health "my-pod" "production" "HTTPS" "8443" "/health"

# Done! Returns HTTP status code (200 = healthy)
```

## 📦 What You Get

### Files Created

```
k8s/
├── lib/
│   ├── pod_health_check_lib.sh    ⭐ Main library (12KB)
│   └── README.md                   📖 Library docs
│
├── scripts/
│   ├── measure_startup_simple.sh   🆕 Measure startup time (7KB)
│   └── batch_health_check.sh       🆕 Check multiple Pods (5.4KB)
│
└── custom-liveness/explore-startprobe/
    ├── openssl-verify-health.md    📖 Complete guide (42KB)
    ├── USAGE_GUIDE.md              📖 Real examples (11KB)
    └── QUICK_START.md              📖 This file
```

### 9 Ready-to-Use Functions

1. `check_pod_health` - Basic health check
2. `check_pod_health_with_retry` - With retry logic
3. `wait_for_pod_ready` - Wait until ready
4. `get_probe_config` - Get probe configuration
5. `extract_probe_endpoint` - Parse endpoint info
6. `calculate_max_startup_time` - Calculate max time
7. `monitor_pod_health` - Continuous monitoring
8. `check_pod_exists` - Check if Pod exists
9. `get_pod_status` - Get Pod phase

## 🚀 Try It Now

### Example 1: Measure Startup Time

```bash
cd k8s/scripts
./measure_startup_simple.sh -n production my-app-pod-abc123
```

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║  Pod Startup Time Measurement (Simple Version)                ║
╠════════════════════════════════════════════════════════════════╣
║  Pod: my-app-pod-abc123
║  Namespace: production
╚════════════════════════════════════════════════════════════════╝

Pod Status: Running
Container Start Time: 2024-12-16T10:00:00Z

Getting probe configuration...
Probe Endpoint:
  - Scheme: HTTPS
  - Port: 8443
  - Path: /health
  → Full URL: HTTPS://localhost:8443/health

Checking current health status...
✓ Pod is currently healthy (Status: 200)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Result
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Startup Time: 45 seconds
   (Based on Kubernetes Ready status)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Configuration Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Current configuration allows max startup time: 120s
Actual startup time: 45s
✓ Configuration is reasonable, buffer: 75s
```

### Example 2: Batch Health Check

```bash
cd k8s/scripts
./batch_health_check.sh -n production my-app
```

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║  Batch Health Check for Multiple Pods                         ║
╠════════════════════════════════════════════════════════════════╣
║  App Label: my-app
║  Namespace: production
╚════════════════════════════════════════════════════════════════╝

Found 3 Pod(s)

Probe Configuration:
  - Endpoint: HTTPS://localhost:8443/health

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking Pods...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

my-app-pod-abc123                          ✓ Healthy (200)
my-app-pod-def456                          ✓ Healthy (200)
my-app-pod-ghi789                          ✓ Healthy (200)

╔════════════════════════════════════════════════════════════════╗
║  Summary                                                       ║
╚════════════════════════════════════════════════════════════════╝

Total Pods: 3
Healthy: 3
Unhealthy: 0

Health Percentage: 100%
████████████████████ 100%
```

## 💡 Common Use Cases

### Use Case 1: In Your Scripts

```bash
#!/bin/bash
source k8s/lib/pod_health_check_lib.sh

POD="my-app-pod-abc123"
NS="production"

# Quick check
if check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health" >/dev/null; then
    echo "✓ Pod is healthy"
else
    echo "✗ Pod is unhealthy"
fi
```

### Use Case 2: Wait for Deployment

```bash
#!/bin/bash
source k8s/lib/pod_health_check_lib.sh

# Deploy
kubectl apply -f deployment.yaml

# Get new Pod
POD=$(kubectl get pods -n prod -l app=myapp -o name | head -1)

# Wait for ready
ELAPSED=$(wait_for_pod_ready "$POD" "prod" "HTTPS" "8443" "/health" 60 2 "yes")

if [ "$ELAPSED" -ne -1 ]; then
    echo "✓ Deployment successful in ${ELAPSED}s"
else
    echo "✗ Deployment failed"
    exit 1
fi
```

### Use Case 3: Auto-detect from Probe Config

```bash
#!/bin/bash
source k8s/lib/pod_health_check_lib.sh

POD="my-app-pod-abc123"
NS="production"

# Get probe config automatically
PROBE=$(get_probe_config "$POD" "$NS" "readinessProbe")
read SCHEME PORT PATH <<< $(extract_probe_endpoint "$PROBE")

# Use extracted values
STATUS=$(check_pod_health "$POD" "$NS" "$SCHEME" "$PORT" "$PATH")
echo "Status: $STATUS"
```

## 🎓 Learn More

### Next Steps

1. **Read the full documentation:**
   ```bash
   cat k8s/custom-liveness/explore-startprobe/openssl-verify-health.md
   ```

2. **See real-world examples:**
   ```bash
   cat k8s/custom-liveness/explore-startprobe/USAGE_GUIDE.md
   ```

3. **Check the library README:**
   ```bash
   cat k8s/lib/README.md
   ```

### Documentation Structure

```
📖 QUICK_START.md (this file)
   ↓ Start here - 5 minutes
   
📖 USAGE_GUIDE.md
   ↓ Real examples - 15 minutes
   
📖 openssl-verify-health.md
   ↓ Complete guide - 1 hour
   
📖 k8s/lib/README.md
   ↓ Library reference
```

## 🔧 Requirements

- `kubectl` - Kubernetes CLI
- `jq` - JSON processor
- `bc` - Calculator
- Pod must have `openssl` (HTTPS) or `nc` (HTTP)

**Install on macOS:**
```bash
brew install kubectl jq bc
```

**Install on Linux:**
```bash
apt-get install kubectl jq bc  # Ubuntu/Debian
yum install kubectl jq bc      # RHEL/CentOS
```

## 🎯 Key Benefits

### Before (Manual Method)
```bash
# 50+ lines of complex code
# openssl s_client commands
# nc commands
# Error handling
# Status code parsing
# ...
```

### After (Using Library)
```bash
# 1 line
check_pod_health "pod" "ns" "HTTPS" "8443" "/health"
```

**Result:**
- ✅ 95% less code
- ✅ 100% more maintainable
- ✅ Reusable everywhere
- ✅ Consistent behavior
- ✅ Better error handling

## 🤔 FAQ

**Q: Do I need to modify my Pods?**  
A: No, the library uses `kubectl exec` to run commands inside existing Pods.

**Q: Does it work with HTTP and HTTPS?**  
A: Yes, both are supported. HTTPS uses `openssl s_client`, HTTP uses `nc`.

**Q: Can I use it in CI/CD?**  
A: Yes! See USAGE_GUIDE.md for GitLab CI and Jenkins examples.

**Q: What if my Pod doesn't have openssl?**  
A: Use HTTP instead of HTTPS, or install openssl in your container image.

**Q: Is it production-ready?**  
A: Yes for scripts and automation. For production monitoring, use Prometheus/Grafana.

## 📞 Get Help

1. **Function help:**
   ```bash
   source k8s/lib/pod_health_check_lib.sh
   pod_health_check_lib_help
   ```

2. **Version info:**
   ```bash
   pod_health_check_lib_version
   ```

3. **Check documentation:**
   - Full guide: `openssl-verify-health.md`
   - Examples: `USAGE_GUIDE.md`
   - Library: `k8s/lib/README.md`

## 🎉 You're Ready!

Start using the library in your scripts today:

```bash
source k8s/lib/pod_health_check_lib.sh
check_pod_health "your-pod" "your-namespace" "HTTPS" "8443" "/health"
```

**Happy scripting! 🚀**

---

**Version:** 1.0.0  
**Created:** 2024-12-16  
**Files:** 5 new files, 42KB+ documentation
