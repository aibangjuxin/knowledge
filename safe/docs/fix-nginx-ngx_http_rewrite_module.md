# NGINX ngx_http_rewrite_module Heap Buffer Overflow — Fix Guide

**CVE:** CVE-2026-42945  
**Severity:** 8.1 HIGH (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H)  
**Affected Versions:** NGINX Open Source & Plus 0.6.27 through 1.30.0  
**Fixed Versions:** 1.30.1, 1.31.0+  
**CWE:** CWE-122 (Heap-based Buffer Overflow)  
**Module:** `ngx_http_rewrite_module`

---

## Overview

A critical heap buffer overflow vulnerability exists in NGINX's `ngx_http_rewrite_module`, introduced in 2008 (nginx 0.6.27). The flaw enables **unauthenticated remote code execution (RCE)** on servers using `rewrite` and `set` directives with PCRE captures.

The bug was autonomously discovered by DepthFirst's security analysis system. It affects every NGINX version released in the past ~18 years.

---

## Vulnerability Details

### Root Cause

NGINX's rewrite script engine uses a **two-pass process**:

1. **Length pass** — compute the required buffer size
2. **Copy pass** — actually write the data

The vulnerability occurs when:

1. A `rewrite` directive's replacement string contains a literal `?` character
2. The `is_args` flag is set on the **main** rewrite engine during the copy pass
3. But the **length-calculation pass** runs on a freshly zeroed sub-engine that has `is_args = 0`

This mismatch causes:

- **Length pass** returns the **raw capture length** (e.g., `$1` = 10 bytes)
- **Copy pass** expands `?` to `%3F` (URL encoding), causing the actual output to be **3x longer**
- Buffer allocated based on step 1 → overflow in step 2

### Trigger Conditions

The vulnerability fires when ALL of these are true:

1. A `rewrite` directive is followed by another `rewrite`, `if`, or `set` directive
2. An unnamed PCRE capture (`$1`, `$2`, etc.) appears in the replacement string
3. The replacement string contains a literal `?` character

Example vulnerable config:

```nginx
server {
    # Vulnerable: rewrite with ? in replacement + set directive
    rewrite ^/(.*)$ /redirect?page=$1? permanent;

    # Or with if/set:
    if ($request_uri ~ ^/old/(.*)$) {
        set $id $1;
        rewrite ^ /new?id=$id? last;
    }
}
```

### Attack Vector

An unauthenticated remote attacker sends a crafted HTTP request with a long-enough PCRE capture to overflow the heap buffer.

**Impact:**
- Worker process crash/restart (denial of service)
- **RCE possible** on systems with ASLR disabled

### CVSS Metrics

| Metric | Value |
|--------|-------|
| Attack Vector | Network |
| Attack Complexity | High |
| Privileges Required | None |
| User Interaction | None |
| Scope | Unchanged |
| Confidentiality | High |
| Integrity | High |
| Availability | High |
| Base Score | **8.1 HIGH** |

---

## Remediation

### Primary Fix — Upgrade NGINX

Upgrade to a patched version:

- **NGINX 1.30.1+** — patch branch for the 1.30.x line
- **NGINX 1.31.0+** — mainline branch

#### Debian/Ubuntu (apt)

```bash
# Check current version
nginx -v

# Update package list
sudo apt update

# Upgrade NGINX
sudo apt install nginx

# Verify new version
nginx -v
sudo systemctl restart nginx
```

#### RHEL/CentOS/AlmaLinux (yum/dnf)

```bash
# Check current version
nginx -v

# Upgrade
sudo dnf update nginx

# Or for CentOS 7 / older
sudo yum update nginx

# Restart
sudo systemctl restart nginx
```

#### macOS (Homebrew)

```bash
# Check current version
nginx -v

# Upgrade
brew update
brew upgrade nginx

# Verify
nginx -v
```

#### Docker

```bash
# Update base image in Dockerfile
# Replace:
#   FROM nginx:1.30.0
# With:
#   FROM nginx:1.30.1
#   FROM nginx:1.31.0

docker build -t myapp:fixed .
docker push myapp:fixed
```

#### Kubernetes / Helm

Update the NGINX Ingress Controller Helm values:

```yaml
# values.yaml
controller:
  image:
    repository: registry.k8s.io/nginx-ingress-controller
    tag: "1.30.1"   # was e.g. "1.30.0"
  nginxplus: false   # set true if using NGINX Plus
```

```bash
helm upgrade my-release -n ingress-nginx -f values.yaml \
  ingress-nginx/ingress-nginx
```

### Workaround — If Upgrade Is Not Immediately Possible

If you cannot upgrade right now, **temporarily** mitigate by:

#### Option 1: Disable PCRE captures in rewrite replacements

Review all `rewrite` directives in your configs and eliminate the combination of `$N` captures and literal `?`:

```nginx
# BEFORE (vulnerable if followed by another rewrite/if/set)
rewrite ^/(.*)$ /new?id=$1? permanent;

# AFTER (safe) — avoid ? in replacement when $N is also present
rewrite ^/(.*)$ /new?id=$1 permanent;
```

#### Option 2: Use `return` instead of `rewrite`

```nginx
# Instead of:
rewrite ^/old/(.*)$ /new?id=$1? permanent;

# Use:
location ~ ^/old/(.*)$ {
    return 301 https://example.com/new?id=$1;
}
```

#### Option 3: Separate rewrite chains carefully

If you must use rewrite chains, avoid the pattern of rewrite → set → rewrite with `?` and `$N`:

```nginx
# Audit all rewrite chains in your configs:
# nginx -T 2>&1 | grep -A5 'rewrite'
```

### Verification Steps

After applying the fix:

```bash
# 1. Verify NGINX version
nginx -v
# Should be >= 1.30.1 or >= 1.31.0

# 2. Test configuration syntax
sudo nginx -t
# Should output: nginx: configuration file /etc/nginx/nginx.conf test is successful

# 3. Reload/restart
sudo systemctl reload nginx   # graceful reload
# or
sudo systemctl restart nginx  # full restart

# 4. Check running version
sudo nginx -v 2>&1
ps aux | grep nginx

# 5. Check logs for crashes
sudo journalctl -u nginx --since "1 hour ago" | grep -i "signal"
sudo tail -50 /var/log/nginx/error.log
```

---

## Detection — How to Know If You Are Vulnerable

### Check NGINX Version

```bash
nginx -v
```

Versions **0.6.27 through 1.30.0** are vulnerable. Versions **1.30.1+** and **1.31.0+** are fixed.

### Audit Rewrite Directive Usage

Find configs using the dangerous rewrite pattern:

```bash
# Search all nginx config files for rewrite + ? + $N pattern
grep -rn 'rewrite.*\$[0-9].*\?' /etc/nginx/
grep -rn 'rewrite.*\?.*\$[0-9]' /etc/nginx/
```

### Active Scan with PoC

The public PoC (from `github.com/DepthFirstDisclosures/Nginx-Rift`) can be used to test:

```bash
# Clone the PoC
git clone https://github.com/DepthFirstDisclosures/Nginx-Rift.git
cd Nginx-Rift

# Run PoC against your NGINX server
python3 poc.py http://your-nginx-host:80
```

**WARNING:** Only run this against systems you own or have explicit permission to test.

---

## Related CVEs

This fix also addresses three related memory corruption issues discovered simultaneously:

| CVE | Module | Severity |
|-----|--------|----------|
| **CVE-2026-42945** | `ngx_http_rewrite_module` (this vuln) | 8.1 HIGH |
| CVE-2026-42946 | (related module) | medium |
| CVE-2026-40701 | (related module) | medium |
| CVE-2026-42934 | (related module) | low |

All fixed in NGINX 1.30.1 / 1.31.0.

---

## References

- [nginx.org Security Advisories](https://nginx.org/en/security_advisories.html)
- [F5 Article K000161019](https://my.f5.com/manage/s/article/K000161019)
- [NVD — CVE-2026-42945](https://nvd.nist.gov/vuln/detail/CVE-2026-42945)
- [DepthFirst Nginx-Rift PoC](https://github.com/DepthFirstDisclosures/Nginx-Rift)
- [DepthFirst Technical Analysis](https://depthfirst.com/nginx-rift)

---

## Action Checklist

- [ ] Identify all NGINX deployments and their versions
- [ ] Identify all `rewrite` directives using `$N` captures with `?` in replacement strings
- [ ] Plan upgrade to NGINX 1.30.1 or 1.31.0 (coordinate maintenance window)
- [ ] For critical systems where immediate upgrade is not possible: apply workaround (remove `?` from rewrite replacements)
- [ ] Upgrade NGINX in dev/staging first
- [ ] Verify upgrade with `nginx -v`
- [ ] Reload NGINX and monitor for errors
- [ ] Run PoC test in staging if available
- [ ] Deploy to production
- [ ] Monitor error logs for restart events
- [ ] Update deployment documentation / Infrastructure-as-Code with new NGINX version
