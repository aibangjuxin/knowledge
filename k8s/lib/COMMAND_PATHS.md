# Command Path Configuration

## 📍 How Commands Are Located

The library uses **hardcoded paths** with **intelligent fallback** for maximum compatibility.

## 🔧 Command Definitions

Located at the top of `pod_health_check_lib.sh`:

```bash
# macOS with Homebrew (Apple Silicon)
if [ -f "/opt/homebrew/bin/gdate" ]; then
    DATE_CMD="/opt/homebrew/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"

# macOS with Homebrew (Intel)
elif [ -f "/usr/local/bin/gdate" ]; then
    DATE_CMD="/usr/local/bin/gdate"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"

# Standard macOS or Linux
else
    DATE_CMD="/bin/date"
    AWK_CMD="/usr/bin/awk"
    SLEEP_CMD="/bin/sleep"
fi

# Fallback: try to find commands in PATH if hardcoded paths don't exist
[ ! -x "$DATE_CMD" ] && DATE_CMD="date"
[ ! -x "$AWK_CMD" ] && AWK_CMD="awk"
[ ! -x "$SLEEP_CMD" ] && SLEEP_CMD="sleep"
```

## 🎯 Detection Logic

### Priority Order:

1. **Check for Homebrew gdate** (macOS with GNU coreutils)
   - Apple Silicon: `/opt/homebrew/bin/gdate`
   - Intel Mac: `/usr/local/bin/gdate`

2. **Use standard paths**
   - DATE: `/bin/date`
   - AWK: `/usr/bin/awk`
   - SLEEP: `/bin/sleep`

3. **Fallback to PATH**
   - If hardcoded paths don't exist, use command name only
   - Shell will find it in PATH

## 📋 Command Paths by Platform

### macOS (Apple Silicon with Homebrew)
```
DATE_CMD:  /opt/homebrew/bin/gdate
AWK_CMD:   /usr/bin/awk
SLEEP_CMD: /bin/sleep
```

### macOS (Intel with Homebrew)
```
DATE_CMD:  /usr/local/bin/gdate
AWK_CMD:   /usr/bin/awk
SLEEP_CMD: /bin/sleep
```

### macOS (without Homebrew)
```
DATE_CMD:  /bin/date
AWK_CMD:   /usr/bin/awk
SLEEP_CMD: /bin/sleep
```

### Linux
```
DATE_CMD:  /bin/date
AWK_CMD:   /usr/bin/awk
SLEEP_CMD: /bin/sleep
```

## 🔍 Verify Your Paths

Run the test script:
```bash
bash k8s/lib/test_lib.sh
```

Output will show:
```
Test 2: Command paths
AWK_CMD:   /usr/bin/awk
DATE_CMD:  /opt/homebrew/bin/gdate
SLEEP_CMD: /bin/sleep
```

## 🛠️ Customization

### Override Paths

If you need different paths, set them **before** sourcing the library:

```bash
#!/bin/bash

# Custom paths
export DATE_CMD="/custom/path/to/date"
export AWK_CMD="/custom/path/to/awk"
export SLEEP_CMD="/custom/path/to/sleep"

# Now source the library
source k8s/lib/pod_health_check_lib.sh

# Use functions...
```

### Check Current Paths

After sourcing the library:
```bash
source k8s/lib/pod_health_check_lib.sh

echo "DATE:  $DATE_CMD"
echo "AWK:   $AWK_CMD"
echo "SLEEP: $SLEEP_CMD"
```

## 🐛 Troubleshooting

### Issue: "command not found" errors

**Check if files exist:**
```bash
ls -la /opt/homebrew/bin/gdate
ls -la /usr/bin/awk
ls -la /bin/sleep
```

**Check if they're executable:**
```bash
[ -x /opt/homebrew/bin/gdate ] && echo "✓ gdate is executable"
[ -x /usr/bin/awk ] && echo "✓ awk is executable"
[ -x /bin/sleep ] && echo "✓ sleep is executable"
```

### Issue: Wrong date command used

**macOS users should install GNU coreutils:**
```bash
brew install coreutils
```

This provides `gdate` which has better compatibility with the scripts.

**Verify gdate is installed:**
```bash
which gdate
gdate --version
```

### Issue: Commands in different locations

**Find where commands are:**
```bash
which date
which awk
which sleep
```

**Update the library** with your paths, or set environment variables before sourcing.

## 📝 Why These Paths?

### `/opt/homebrew/bin/gdate` (Apple Silicon)
- Homebrew on Apple Silicon installs to `/opt/homebrew`
- GNU coreutils provides `gdate` with better date parsing

### `/usr/local/bin/gdate` (Intel Mac)
- Homebrew on Intel Macs installs to `/usr/local`
- Same GNU coreutils, different location

### `/usr/bin/awk`
- Standard location on both macOS and Linux
- Works consistently across platforms

### `/bin/sleep`
- Standard location on both macOS and Linux
- Built-in command, always available

### `/bin/date`
- Fallback for systems without GNU coreutils
- Works but has different options on macOS vs Linux

## ✅ Best Practices

1. **Install GNU coreutils on macOS:**
   ```bash
   brew install coreutils
   ```

2. **Run test script after installation:**
   ```bash
   bash k8s/lib/test_lib.sh
   ```

3. **Verify paths are correct:**
   ```bash
   source k8s/lib/pod_health_check_lib.sh
   echo "Using: $DATE_CMD"
   ```

4. **Keep Homebrew updated:**
   ```bash
   brew update
   brew upgrade coreutils
   ```

## 🎯 Summary

The library uses a **smart detection system**:
1. ✅ Tries Homebrew paths first (best compatibility)
2. ✅ Falls back to standard paths
3. ✅ Uses PATH as last resort
4. ✅ Works on macOS (Intel & Apple Silicon) and Linux

No manual configuration needed in most cases!

---

**Version:** 1.0.3  
**Last Updated:** 2024-12-16
