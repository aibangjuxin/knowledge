# OpenSSL as Telnet & Curl Replacement in Kubernetes Pods

## Problem Statement

In Kubernetes Pods, base images often lack `curl` and `telnet` utilities. However, almost all images include OpenSSL. This document shows how to use OpenSSL commands to accomplish the same tasks.

## TL;DR Quick Commands

### Replace Telnet (Port Check)

```bash
# Test TCP port connectivity (works for any port)
openssl s_client -connect <host>:<port> -servername <host> </dev/null 2>&1 | head

# Example: Check port 443
openssl s_client -connect www.example.com:443 -servername www.example.com </dev/null 2>&1 | head

# Example: Check port 80 (HTTP)
echo "Q" | openssl s_client -connect www.example.com:80 </dev/null 2>&1 | head
```

### Replace Curl (HTTP/HTTPS Request)

```bash
# Simple HTTPS GET
echo -e "GET / HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect <host>:443 -servername <host> </dev/null 2>&1 | \
  grep -A 20 "HTTP/"

# HTTPS GET with header inspection
echo -e "GET / HTTP/1.1\r\nHost: <host>\r\n\r\n" | \
  openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \
  openssl x509 -noout -dates -subject -issuer
```

---

## Part 1: OpenSSL as Telnet Replacement

### Test HTTPS Port (443)

```bash
openssl s_client -connect www.example.com:443 -servername www.example.com </dev/null 2>&1
```

**What it shows:**
- SSL/TLS handshake result
- Certificate chain
- `Verify return code: 0 (ok)` = success
- Any certificate errors

**Quick check (exit code only):**
```bash
timeout 5 openssl s_client -connect www.example.com:443 -servername www.example.com </dev/null 2>&1 | grep -q "Verify return code: 0" && echo "OK" || echo "FAIL"
```

### Test HTTP Port (80)

```bash
echo "Q" | openssl s_client -connect www.example.com:80 2>/dev/null
```

If it connects and returns something (even an error), the port is open.

### Test Any TCP Port

```bash
openssl s_client -connect <host>:<port> -servername <host> </dev/null 2>&1 | head -5
```

If it returns a connection banner or waits (then times out), the port is reachable.

### Verify SNI Support

```bash
openssl s_client -connect <host>:443 </dev/null 2>&1 | grep "Server did not accept SNI"
```

No output = SNI is working.

---

## Part 2: OpenSSL as Curl Replacement

### Basic HTTPS GET Request

```bash
exec 3<>(/dev/tcp/<host>/443)

echo -e "GET / HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n" >&3

openssl s_client -connect <host>:443 -servername <host> 2>/dev/null <&3 | head -50
```

### Simpler Method (s_client only)

```bash
echo -e "GET / HTTP/1.1\r\nHost: www.example.com\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect www.example.com:443 \
    -servername www.example.com \
    -ign_eof 2>/dev/null | grep -v "^(Enter\|depth\|verify\|---$"
```

### HTTPS GET with Full Response Headers

```bash
echo -e "GET / HTTP/1.1\r\nHost: <host>\r\nAccept: */*\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect <host>:443 \
    -servername <host> \
    -ign_eof 2>/dev/null
```

### HTTPS GET with Specific Path and Headers

```bash
echo -e "GET /path HTTP/1.1\r\nHost: <host>\r\nUser-Agent: openssl-test/1.0\r\nAccept: application/json\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect <host>:443 \
    -servername <host> \
    -ign_eof 2>/dev/null
```

### Check HTTP Status Code Only

```bash
echo -e "HEAD / HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect <host>:443 \
    -servername <host> \
    -ign_eof 2>/dev/null | grep "HTTP/"
```

### POST Request with JSON Body

```bash
echo -e "POST /api/endpoint HTTP/1.1\r\nHost: <host>\r\nContent-Type: application/json\r\nContent-Length: 27\r\nConnection: close\r\n\r\n{\"key\":\"value\"}" | \
  openssl s_client -connect <host>:443 \
    -servername <host> \
    -ign_eof 2>/dev/null
```

---

## Part 3: Certificate Inspection Commands

### Check Certificate Expiry Date

```bash
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \
  openssl x509 -noout -dates
```

**Output example:**
```
notBefore=Jan 15 00:00:00 2024 GMT
notAfter=Jan 15 00:00:00 2025 GMT
```

### Check Certificate Subject (CN/SAN)

```bash
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \
  openssl x509 -noout -subject -serial
```

### Check All Certificate Info

```bash
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \
  openssl x509 -noout -text | head -30
```

### Verify Certificate Against System CA

```bash
echo | openssl s_client -connect <host>:443 -servername <host> \
  -CAfile /etc/ssl/certs/ca-certificates.crt 2>/dev/null | \
  grep "Verify return code"
```

### Check Supported TLS Versions

```bash
# TLS 1.3 only
openssl s_client -connect <host>:443 -tls1_3 </dev/null 2>&1 | grep "Protocol"

# TLS 1.2 only
openssl s_client -connect <host>:443 -tls1_2 </dev/null 2>&1 | grep "Protocol"
```

---

## Part 4: Kubernetes Pod Debugging Recipes

### Quick Health Check (Pod Startup Probe Alternative)

```bash
# Inside a Pod, check if a service is reachable
openssl s_client -connect my-service:443 -servername my-service </dev/null 2>&1 | grep "Verify return code"
```

### Check External API Reachability

```bash
# From inside Pod to external HTTPS endpoint
openssl s_client -connect api.example.com:443 \
  -servername api.example.com \
  -CAfile /etc/ssl/certs/ca-certificates.crt \
  </dev/null 2>&1 | grep "Verify return code"
```

### Debug 502/504 Errors

```bash
# Check if backend is responding
openssl s_client -connect backend-service.namespace.svc.cluster.local:8080 \
  -servername backend-service.namespace.svc.cluster.local \
  </dev/null 2>&1 | head

# Check TLS certificate on load balancer
openssl s_client -connect my-lb-ip.elb.amazonaws.com:443 \
  -servername my-domain.com \
  </dev/null 2>&1 | grep "Verify return code"
```

### DNS + Certificate Check (Combined)

```bash
# Resolve DNS then check cert
host my-domain.com && \
openssl s_client -connect my-domain.com:443 -servername my-domain.com \
  </dev/null 2>&1 | grep -E "(Verify|CN=|subject=|notAfter)"
```

### Check GKE Managed Certificate

```bash
# Check SSL cert on GKE Ingress
openssl s_client -connect my-ingress-ip.elb.amazonaws.com:443 \
  -servername my-domain.com \
  </dev/null 2>&1 | grep -E "Verify|notAfter|CN="
```

---

## Part 5: One-Line One-Shots (Copy-Paste Ready)

```bash
# Port 443 check
openssl s_client -connect <host>:443 -servername <host> </dev/null 2>&1 | grep "Verify return code"

# Port 80 check (HTTP)
echo "Q" | openssl s_client -connect <host>:80 2>/dev/null && echo "OPEN" || echo "CLOSED"

# HTTPS GET /
echo -e "GET / HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n" | openssl s_client -connect <host>:443 -servername <host> -ign_eof 2>/dev/null

# Check cert expiry
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | openssl x509 -noout -dates

# Check TLS version
openssl s_client -connect <host>:443 -tls1_3 </dev/null 2>&1 | grep Protocol

# Full cert info
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | openssl x509 -noout -text | head -20
```

---

## Common Error Codes

| Code | Meaning | Fix |
|------|---------|-----|
| `Verify return code: 0 (ok)` | Certificate valid | — |
| `Verify return code: 20` | Cannot get local issuer | Update CA bundle |
| `Verify return code: 21` | Incomplete certificate chain | Server misconfiguration |
| `Verify return code: 27` | Certificate not trusted | Add to trusted store |
| `Verify return code: 19` | Self-signed certificate | Use `-verify_return_error` carefully |
| `Connection refused` | Port not listening | Check service is running |
| `Connection timed out` | Firewall blocking | Check network policy |

---

## Summary

| Task | Traditional Command | OpenSSL Replacement |
|------|-------------------|-------------------|
| Port check (HTTPS) | `telnet host 443` | `openssl s_client -connect host:443` |
| Port check (HTTP) | `telnet host 80` | `echo "Q" \| openssl s_client -connect host:80` |
| HTTP GET | `curl -I https://host/` | See Part 2 scripts |
| Check cert expiry | `curl -I https://host/` | `openssl x509 -noout -dates` |
| Check TLS version | N/A | `openssl s_client -tls1_3` |
| SNI check | N/A | `openssl s_client -connect host:443` (with/without `-servername`) |
