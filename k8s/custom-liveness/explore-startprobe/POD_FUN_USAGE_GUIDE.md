# Pod Health Check Library - Usage Guide

## 🎯 What You Get

A complete, production-ready library for checking Pod health in Kubernetes, extracted from the `openssl s_client` method used in your startup measurement scripts.

## 📁 File Structure

```
k8s/
├── lib/
│   ├── pod_health_check_lib.sh          # ⭐ Main library file
│   └── README.md                         # Library documentation
├── scripts/
│   ├── measure_startup_simple.sh         # 🆕 Simple startup measurement
│   ├── batch_health_check.sh             # 🆕 Batch health checker
│   ├── pod_status.sh                     # Your existing script (can be enhanced)
│   └── pod_exec.sh                       # Your existing script
└── custom-liveness/
    └── explore-startprobe/
        ├── openssl-verify-health.md      # 📖 Complete documentation
        ├── USAGE_GUIDE.md                # 📖 This file
        ├── pod_measure_startup_enhance.sh
        └── pod_measure_startup_enhance_eng.sh
```

## 🚀 Quick Start (3 Steps)

### Step 1: Source the Library

```bash
#!/bin/bash
source /path/to/k8s/lib/pod_health_check_lib.sh
```

### Step 2: Use a Function

```bash
# Check if Pod is healthy
STATUS=$(check_pod_health "my-pod" "production" "HTTPS" "8443" "/health")

if [ $? -eq 0 ]; then
    echo "✓ Pod is healthy (Status: $STATUS)"
else
    echo "✗ Pod is unhealthy (Status: $STATUS)"
fi
```

### Step 3: Done!

That's it. No need to write complex `openssl` or `nc` commands anymore.

## 💡 Real-World Examples

### Example 1: Measure Startup Time (Simplified)

**Before (50+ lines):**
```bash
# Complex openssl/nc commands
# Manual time calculation
# Error handling
# Progress display
# ... lots of code
```

**After (Using Library):**
```bash
#!/bin/bash
source ./pod_health_check_lib.sh

# Get probe config
PROBE=$(get_probe_config "$POD" "$NS" "readinessProbe")
read SCHEME PORT PATH <<< $(extract_probe_endpoint "$PROBE")

# Wait for ready and get elapsed time
ELAPSED=$(wait_for_pod_ready "$POD" "$NS" "$SCHEME" "$PORT" "$PATH")

echo "Startup time: ${ELAPSED}s"
```

**Try it now:**
```bash
cd k8s/scripts
./measure_startup_simple.sh -n production my-app-pod-abc123
/opt/homebrew/bin/bash k8s/scripts/measure_startup_simple.sh -n  lex nginx-deployment-854b5bc678-zq4kb
```

### Example 2: Batch Health Check

**Check all Pods in a deployment:**
```bash
cd k8s/scripts
./batch_health_check.sh -n production my-app
 /opt/homebrew/bin/bash k8s/scripts/batch_health_check.sh -n lex lex=enabled
╔════════════════════════════════════════════════════════════════╗
║  Batch Health Check for Multiple Pods                         ║
╠════════════════════════════════════════════════════════════════╣
║  Label Selector: lex=enabled
║  Namespace: lex
╚════════════════════════════════════════════════════════════════╝

Found 2 Pod(s)

Probe Configuration:
  - Endpoint: HTTP://localhost:80/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking Pods...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

nginx-deployment-854b5bc678-fls8n                  ✓ Healthy (200)
nginx-deployment-854b5bc678-zq4kb                  ✓ Healthy (200)

╔════════════════════════════════════════════════════════════════╗
║  Summary                                                       ║
╚════════════════════════════════════════════════════════════════╝

Total Pods: 2
Healthy: 2
Unhealthy: 0

Health Percentage: 100%
████████████████████ 100%

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

Checking Pods...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

my-app-pod-abc123                          ✓ Healthy (200)
my-app-pod-def456                          ✓ Healthy (200)
my-app-pod-ghi789                          ✗ Unhealthy (503)

╔════════════════════════════════════════════════════════════════╗
║  Summary                                                       ║
╚════════════════════════════════════════════════════════════════╝

Total Pods: 3
Healthy: 2
Unhealthy: 1

Health Percentage: 66%
█████████████░░░░░░░ 66%
```
#### verify pod health check

`/opt/homebrew/bin/bash k8s/scripts/debug_health_check.sh nginx-deployment-854b5bc678-fls8n lex`
```bash
=== Debug Health Check ===
Pod: nginx-deployment-854b5bc678-fls8n
Namespace: lex

1. Getting probe configuration...
Probe config: {"failureThreshold":3,"httpGet":{"path":"/","port":80,"scheme":"HTTP"},"periodSeconds":20,"successThreshold":1,"timeoutSeconds":3}

2. Extracting endpoint...
Endpoint: HTTP 80 /
  Scheme: HTTP
  Port: 80
  Path: /

3. Testing direct kubectl exec (original method)...
Status line: ''
Status code: ''

4. Testing library function...
Command paths:
  AWK_CMD: /usr/bin/awk
  DATE_CMD: /opt/homebrew/bin/gdate
  SLEEP_CMD: /bin/sleep

Library result: 000 (return code: 1)

5. Testing with verbose kubectl exec...
timeout: failed to run command 'nc': No such file or directory
command terminated with exit code 127

=== Debug Complete ===
```


### Example 3: Enhance Your Existing pod_status.sh

Add real-time health checking to your existing script:

```bash
#!/bin/bash

# Add this at the top
source "${SCRIPT_DIR}/../lib/pod_health_check_lib.sh"

# ... your existing code ...

for POD in ${PODS}; do
    echo -e "${YELLOW}Pod: ${POD}${NC}"
    
    # ... existing info gathering ...
    
    # 🆕 Add real-time health check
    if [ ! -z "$READINESS_PROBE" ]; then
        PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
        if [ ! -z "$PROBE_ENDPOINT" ]; then
            read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"
            
            echo -e "\n${YELLOW}Real-time Health Check:${NC}"
            STATUS=$(check_pod_health_with_retry "$POD" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH" 3 1)
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Current Status: Healthy (HTTP ${STATUS})${NC}"
            else
                echo -e "${RED}✗ Current Status: Unhealthy (HTTP ${STATUS})${NC}"
            fi
        fi
    fi
    
    # ... rest of your code ...
done
```

### Example 4: CI/CD Integration

**GitLab CI:**
```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  script:
    - kubectl apply -f deployment.yaml
    - source k8s/lib/pod_health_check_lib.sh
    
    # Wait for new Pod
    - |
      POD=$(kubectl get pods -n production -l app=myapp \
        --sort-by=.metadata.creationTimestamp -o name | tail -1)
      
      echo "Waiting for Pod: $POD"
      ELAPSED=$(wait_for_pod_ready "$POD" "production" "HTTPS" "8443" "/health" 60 2 "yes")
      
      if [ "$ELAPSED" -eq -1 ]; then
        echo "Deployment failed: Pod not ready"
        exit 1
      fi
      
      echo "Deployment successful in ${ELAPSED}s"
```

**Jenkins:**
```groovy
stage('Deploy and Verify') {
    steps {
        sh 'kubectl apply -f deployment.yaml'
        sh '''
            source k8s/lib/pod_health_check_lib.sh
            
            POD=$(kubectl get pods -n production -l app=myapp -o name | head -1)
            
            if check_pod_health_with_retry "$POD" "production" "HTTPS" "8443" "/health" 10 3; then
                echo "Health check passed"
            else
                echo "Health check failed"
                exit 1
            fi
        '''
    }
}
```

### Example 5: Monitoring Script

**Continuous monitoring:**
```bash
#!/bin/bash
source ./pod_health_check_lib.sh

# Monitor a specific Pod
monitor_pod_health "my-app-pod-abc123" "production" "HTTPS" "8443" "/health" 10
```

**Output:**
```
Starting health monitoring for Pod: my-app-pod-abc123
Press Ctrl+C to stop

2024-12-16 10:00:00 ✓ Status: 200
2024-12-16 10:00:10 ✓ Status: 200
2024-12-16 10:00:20 ✗ Status: 503
2024-12-16 10:00:30 ✓ Status: 200
...
```

## 🔍 Where to Use This Library

### ✅ Perfect For:

1. **Startup Time Measurement**
   - Measure how long your app takes to start
   - Optimize probe configurations
   - Track startup performance over time

2. **Deployment Verification**
   - Verify Pods are healthy after deployment
   - Automated rollback on health check failure
   - CI/CD pipeline integration

3. **Batch Operations**
   - Check all Pods in a deployment
   - Health status reports
   - Pre-maintenance verification

4. **Debugging**
   - Quick health check during troubleshooting
   - Verify probe configuration
   - Test endpoint accessibility

5. **Monitoring**
   - Continuous health monitoring
   - Alert on health check failures
   - Custom monitoring scripts

### ❌ Not Suitable For:

1. **Production Monitoring** - Use Prometheus/Grafana instead
2. **Load Testing** - Use dedicated load testing tools
3. **External Health Checks** - This checks inside the Pod only

## 📊 Comparison: Before vs After

### Checking Pod Health

**Before (Manual):**
```bash
# 15+ lines of code
HTTP_STATUS_LINE=$(printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
    kubectl exec -i my-pod -n production -- sh -c \
    "openssl s_client -connect localhost:8443 -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
if [ -z "$HTTP_CODE" ]; then
    HTTP_CODE="000"
fi
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Healthy"
else
    echo "Unhealthy"
fi
```

**After (Using Library):**
```bash
# 1 line of code
check_pod_health "my-pod" "production" "HTTPS" "8443" "/health" && echo "Healthy" || echo "Unhealthy"
```

### Measuring Startup Time

**Before:** 200+ lines in `pod_measure_startup_fixed.sh`  
**After:** 50 lines in `measure_startup_simple.sh` (using library)

**Reduction:** 75% less code, 100% more maintainable

## 🎓 Learning Path

### Level 1: Basic Usage (5 minutes)
```bash
# Just check if a Pod is healthy
source pod_health_check_lib.sh
check_pod_health "pod-name" "namespace" "HTTPS" "8443" "/health"
```

### Level 2: Practical Scripts (15 minutes)
```bash
# Use the provided example scripts
./measure_startup_simple.sh -n production my-pod
./batch_health_check.sh -n production my-app
```

### Level 3: Integration (30 minutes)
```bash
# Integrate into your existing scripts
# See Example 3 above
```

### Level 4: Advanced (1 hour)
```bash
# Create custom functions
# Extend the library for your needs
# See "Advanced Usage" in openssl-verify-health.md
```

## 🔧 Customization

### Add Custom Headers

```bash
# Extend the library
check_pod_health_with_auth() {
    local pod="$1"
    local ns="$2"
    local token="$3"
    
    # Custom implementation with Authorization header
    # ... your code ...
}
```

### Custom Timeout Logic

```bash
# Wrapper function
check_with_custom_timeout() {
    timeout 5 check_pod_health "$@"
}
```

## 📚 Documentation Index

1. **openssl-verify-health.md** - Complete documentation
   - Technical details
   - All functions explained
   - Advanced usage
   - Troubleshooting

2. **k8s/lib/README.md** - Library overview
   - Quick reference
   - Installation
   - Basic examples

3. **USAGE_GUIDE.md** - This file
   - Real-world examples
   - Integration patterns
   - Best practices

## 🎯 Next Steps

1. **Try the examples:**
   ```bash
   cd k8s/scripts
   ./measure_startup_simple.sh -n <your-namespace> <your-pod>
   ./batch_health_check.sh -n <your-namespace> <your-app>
   ```

2. **Integrate into existing scripts:**
   - Add to `pod_status.sh`
   - Use in deployment scripts
   - Add to CI/CD pipelines

3. **Customize for your needs:**
   - Add custom functions
   - Extend error handling
   - Add logging

4. **Share with team:**
   - Document your use cases
   - Create team-specific examples
   - Establish best practices

## 💬 Questions?

- Check the full documentation: `openssl-verify-health.md`
- Run `pod_health_check_lib_help` for function reference
- Look at example scripts in `k8s/scripts/`

## 🎉 Summary

You now have:
- ✅ A reusable health check library
- ✅ Two ready-to-use example scripts
- ✅ Complete documentation
- ✅ Integration examples
- ✅ Best practices guide

**Start using it today and simplify your Kubernetes health checking!**

---

**Version:** 1.0.0  
**Created:** 2024-12  
**Author:** DevOps Team
