# Critical Bug Fix - PATH Variable Collision

## 🐛 The Bug

**Symptom:** Commands like `awk`, `date`, `sleep` not found after calling health check functions.

**Root Cause:** Using `PATH` as a variable name overwrites the system `PATH` environment variable!

## ❌ Broken Code

```bash
# This BREAKS the system PATH!
read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"

# Now PATH contains "/health" instead of "/usr/bin:/bin:..."
# System can't find commands anymore!
check_pod_health "$POD" "$NS" "$SCHEME" "$PORT" "$PATH"
# awk: command not found
# date: command not found
# sleep: command not found
```

## ✅ Fixed Code

```bash
# Use PROBE_PATH instead of PATH
read SCHEME PORT PROBE_PATH <<< "$PROBE_ENDPOINT"

# Now system PATH is preserved
check_pod_health "$POD" "$NS" "$SCHEME" "$PORT" "$PROBE_PATH"
# Everything works!
```

## 🔍 Why This Happened

In bash, `PATH` is a **special environment variable** that tells the shell where to find commands:

```bash
$ echo $PATH
/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# When you do this:
PATH="/health"

# Now PATH is:
$ echo $PATH
/health

# Shell can't find commands anymore:
$ awk
bash: awk: command not found
```

## 📊 Impact

### Before Fix (v1.0.3)
- ❌ `measure_startup_simple.sh` - BROKEN
- ❌ `batch_health_check.sh` - BROKEN
- ✅ Original scripts - WORKING (they don't use `read ... PATH`)

### After Fix (v1.0.4)
- ✅ `measure_startup_simple.sh` - FIXED
- ✅ `batch_health_check.sh` - FIXED
- ✅ All scripts - WORKING

## 🛡️ Prevention

### Reserved Variable Names to Avoid

Never use these as variable names in bash scripts:

```bash
# System variables
PATH        # Command search path
HOME        # User home directory
USER        # Current user
SHELL       # Current shell
PWD         # Current directory
OLDPWD      # Previous directory
IFS         # Internal field separator
PS1, PS2    # Prompt strings

# Common conventions
RANDOM      # Random number generator
SECONDS     # Script runtime
LINENO      # Current line number
```

### Safe Alternatives

```bash
# Instead of PATH, use:
PROBE_PATH
ENDPOINT_PATH
URL_PATH
REQUEST_PATH
HTTP_PATH

# Instead of USER, use:
USERNAME
USER_NAME
ACCOUNT_NAME
```

## 🧪 How to Test

### Test 1: Verify PATH is preserved

```bash
#!/bin/bash

echo "Before: PATH=$PATH"

# Bad way (breaks PATH)
read SCHEME PORT PATH <<< "HTTP 80 /health"
echo "After bad read: PATH=$PATH"
which awk  # command not found!

# Good way (preserves PATH)
read SCHEME PORT PROBE_PATH <<< "HTTP 80 /health"
echo "After good read: PATH=$PATH"
which awk  # /usr/bin/awk
```

### Test 2: Run the fixed scripts

```bash
# Should work now
bash k8s/scripts/measure_startup_simple.sh -n lex <pod-name>
bash k8s/scripts/batch_health_check.sh -n lex <app-label>
```

## 📝 Lessons Learned

1. **Never use system variable names** as your own variables
2. **Test with real data** - the bug only appeared when actually running
3. **Compare with working code** - original scripts didn't have this issue
4. **Use descriptive names** - `PROBE_PATH` is clearer than `PATH` anyway

## 🔧 Files Fixed

- ✅ `k8s/scripts/measure_startup_simple.sh`
- ✅ `k8s/scripts/batch_health_check.sh`

## 📚 References

- [Bash Special Parameters](https://www.gnu.org/software/bash/manual/html_node/Special-Parameters.html)
- [Bash Variables](https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html)

---

**Version:** 1.0.4  
**Date:** 2024-12-16  
**Severity:** CRITICAL  
**Status:** FIXED ✅
