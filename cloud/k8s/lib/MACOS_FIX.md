# macOS Compatibility Fix Guide

## 🐛 Issue Description

When running the scripts on macOS, you may encounter these errors:

```
awk: command not found
date: command not found
sleep: command not found
-1: integer expression expected
```

## ✅ Solution

The library has been updated to **v1.0.2** with full macOS support.

## 🔧 What Was Fixed

### 1. Command Detection
The library now automatically detects available commands:

```bash
# Auto-detect awk
if command -v gawk >/dev/null 2>&1; then
    AWK_CMD="gawk"
elif command -v awk >/dev/null 2>&1; then
    AWK_CMD="awk"
else
    AWK_CMD="/usr/bin/awk"
fi

# Auto-detect date
if command -v gdate >/dev/null 2>&1; then
    DATE_CMD="gdate"
else
    DATE_CMD="date"
fi
```

### 2. PATH Enhancement
Added Homebrew paths:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

### 3. Integer Comparison Fix
Changed from:
```bash
if [ "$ELAPSED" -eq -1 ]; then
```

To:
```bash
if [ -z "$ELAPSED" ] || [ "$ELAPSED" = "-1" ]; then
```

## 🧪 Verify the Fix

Run the test script:

```bash
k8s/lib/test_lib.sh
```

**Expected output:**
```
Testing pod_health_check_lib.sh on macOS...

✓ Library sourced successfully

Test 1: Version check
Pod Health Check Library v1.0.2

Test 2: Command detection
AWK_CMD: awk
DATE_CMD: date

Test 3: Test awk command
200

Test 4: Test date command
1702742400

Test 5: Check kubectl
✓ kubectl is available
Client Version: v1.28.0

All basic tests completed!
```

## 🚀 Test with Real Pod

Now try the actual scripts:

```bash
# Get a running Pod
kubectl get pods -n <your-namespace>

# Test startup measurement
k8s/scripts/measure_startup_simple.sh -n <namespace> <pod-name>

# Test batch health check
k8s/scripts/batch_health_check.sh -n <namespace> <app-label>
```

## 🔍 Troubleshooting

### Issue: Still getting "command not found"

**Check your PATH:**
```bash
echo $PATH
```

Should include:
- `/opt/homebrew/bin` (for Apple Silicon Macs)
- `/usr/local/bin` (for Intel Macs)
- `/usr/bin`
- `/bin`

**Check if commands exist:**
```bash
which awk
which date
which sleep
```

### Issue: "kubectl: command not found"

**Install kubectl:**
```bash
# Using Homebrew
brew install kubectl

# Verify
kubectl version --client
```

### Issue: "jq: command not found"

**Install jq:**
```bash
# Using Homebrew
brew install jq

# Verify
jq --version
```

### Issue: Pod doesn't have openssl or nc

**For HTTPS Pods without openssl:**
- Use HTTP instead if available
- Or add openssl to your container image:
  ```dockerfile
  RUN apk add --no-cache openssl
  ```

**For HTTP Pods without nc:**
- Most images have nc (netcat) by default
- Or add it to your container image:
  ```dockerfile
  RUN apk add --no-cache netcat-openbsd
  ```

## 📋 System Requirements

### macOS
- macOS 10.15 (Catalina) or later
- Bash 3.2+ (built-in) or Bash 5.0+ (Homebrew)
- Homebrew (recommended)

### Required Tools
```bash
# Check if installed
command -v kubectl && echo "✓ kubectl"
command -v jq && echo "✓ jq"
command -v awk && echo "✓ awk"
command -v date && echo "✓ date"
```

### Install Missing Tools
```bash
# Install all at once
brew install kubectl jq

# awk and date are built-in on macOS
```

## 🎯 Quick Test

Run this one-liner to test everything:

```bash
source k8s/lib/pod_health_check_lib.sh && \
pod_health_check_lib_version && \
echo "AWK: $AWK_CMD" && \
echo "DATE: $DATE_CMD" && \
echo "Test: $(echo 'HTTP/1.1 200 OK' | $AWK_CMD '{print $2}')"
```

**Expected output:**
```
Pod Health Check Library v1.0.2
AWK: awk
DATE: date
Test: 200
```

## 📝 Notes

### Bash Version
The scripts work with both:
- **System bash** (`/bin/bash`) - version 3.2.x
- **Homebrew bash** (`/opt/homebrew/bin/bash`) - version 5.x

To check your bash version:
```bash
bash --version
```

### Shebang Line
All scripts use:
```bash
#!/bin/bash
```

This will use the first `bash` found in your PATH. If you want to force Homebrew bash:
```bash
#!/opt/homebrew/bin/bash
```

But this is not necessary - the scripts work with system bash.

## ✅ Verification Checklist

- [ ] Library version shows v1.0.2
- [ ] Test script runs without errors
- [ ] AWK_CMD is detected correctly
- [ ] DATE_CMD is detected correctly
- [ ] kubectl is available
- [ ] jq is available
- [ ] Can connect to Kubernetes cluster
- [ ] Can list Pods in a namespace
- [ ] measure_startup_simple.sh works
- [ ] batch_health_check.sh works

## 🎉 Success!

If all checks pass, you're ready to use the library on macOS!

---

**Version:** 1.0.2  
**Platform:** macOS (Apple Silicon & Intel)  
**Tested on:** macOS 14.x (Sonoma), macOS 13.x (Ventura)  
**Last Updated:** 2024-12-16
