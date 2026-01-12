# HSTS Best Practices for Multi-Layer Architectures

This document outlines the best practices for implementing Strict-Transport-Security (HSTS) headers in multi-layer architectures, particularly from a platform perspective. It addresses the common issue of duplicate HSTS headers and provides clear guidance on where and how to implement HSTS in layered systems.

## Table of Contents
- [Introduction](#introduction)
- [The Problem with Multi-Layer HSTS](#the-problem-with-multi-layer-hsts)
- [Platform-Level Recommendations](#platform-level-recommendations)
- [Layer-Specific Guidelines](#layer-specific-guidelines)
- [Implementation Examples](#implementation-examples)
- [Security Rationale](#security-rationale)
- [Troubleshooting](#troubleshooting)
- [Conclusion](#conclusion)

## Introduction

Strict-Transport-Security (HSTS) is a security mechanism that forces browsers to use HTTPS for all connections to a domain. When implemented correctly, it protects against protocol downgrade attacks and cookie hijacking. However, in multi-layer architectures, HSTS headers can be inadvertently added multiple times, leading to security and compliance issues.

This document provides platform-level guidance for implementing HSTS in layered systems such as:
- GCP L7 Load Balancer → Nginx → Kong → Java Application
- Edge Proxy → Gateway → Application Services
- Any multi-tier architecture with multiple response generation points

## The Problem with Multi-Layer HSTS

### Common Issues
- **Duplicate Headers**: Multiple layers independently adding HSTS headers
- **Penetration Testing Failures**: Security scanners flag duplicate headers as misconfigurations
- **Browser Behavior**: Some browsers may ignore HSTS policies when multiple headers exist
- **Compliance Violations**: Security audits may flag duplicate headers as vulnerabilities

### Root Cause
In multi-layer architectures, each component may believe it's responsible for security headers, leading to multiple HSTS headers in the final response.

## Platform-Level Recommendations

### Single Responsibility Principle
**HSTS should be configured at exactly one layer: the outermost edge**

### Recommended Architecture
| Layer | Configure HSTS? | Reason |
|-------|----------------|---------|
| Edge Load Balancer / Proxy | ✅ **YES** (Required) | First point of contact with external clients |
| Internal Gateways (Kong, etc.) | ❌ **NO** | Would cause duplication |
| Application Layer | ❌ **NO** | Should be platform-agnostic |
| Health Checks | ❌ **NO** | Not browser-accessible endpoints |

### Why Edge-Only Configuration?

1. **Security Scanner Compliance**: Penetration testing tools evaluate the outermost response
2. **Browser Behavior**: Browsers only process the first HSTS header they receive
3. **Simplified Management**: Single point of control for security policy
4. **Clear Responsibility**: Unambiguous ownership of security configuration

## Layer-Specific Guidelines

### Edge Layer (Load Balancer / Nginx / Proxy)
This is the **only** layer that should add HSTS headers.

#### Nginx Configuration Example
```nginx
# Configure HSTS at the edge layer only
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

# Prevent duplicate headers from downstream services
proxy_hide_header Strict-Transport-Security;
```

#### GCP Load Balancer Configuration
```yaml
# In your FrontendConfig resource
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: hsts-frontend-config
spec:
  redirectToHttps:
    enabled: true
    responseCodeName: MOVED_PERMANENTLY_DEFAULT
  # HSTS configuration at the load balancer level
```

### Gateway Layer (Kong, API Gateway)
This layer should **not** add HSTS headers but should handle header propagation carefully.

#### Kong Configuration Example
```yaml
# Remove any HSTS headers from upstream services to prevent duplication
response-transformer:
  config:
    remove:
      headers:
        - Strict-Transport-Security
```

### Application Layer (Java, Node.js, etc.)
Applications should **not** add HSTS headers when deployed behind a platform that handles security headers.

#### Spring Boot Configuration Example
```java
@Configuration
@EnableWebSecurity
public class SecurityConfig extends WebSecurityConfigurerAdapter {
    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http.headers()
            // Disable HSTS since it's handled at the platform edge
            .httpStrictTransportSecurity().disable()
            .and()
            .authorizeRequests()
            .anyRequest().authenticated();
    }
}
```

## Implementation Examples

### Complete Nginx Configuration
```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # SSL configuration
    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;

    # HSTS configuration - EDGE ONLY
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Prevent duplicate headers from upstream
    proxy_hide_header Strict-Transport-Security;

    # Upstream proxy configuration
    location / {
        proxy_pass http://upstream-service;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Kong Plugin Configuration
```yaml
# Remove HSTS headers to prevent duplication
- name: response-transformer
  config:
    remove:
      headers:
        - Strict-Transport-Security
    rename:
      headers:
        # Optionally rename for debugging purposes
        - Strict-Transport-Security: X-Upstream-HSTS
```

### Kubernetes Ingress Configuration
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hsts-ingress
  annotations:
    # Configure HSTS at the ingress controller level
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
      proxy_hide_header Strict-Transport-Security;
spec:
  tls:
  - hosts:
    - example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: backend-service
            port:
              number: 80
```

## Security Rationale

### Why Edge Configuration is Critical

Security scanners and penetration testing tools evaluate the **first response** that external clients receive. If the outermost layer doesn't return an HSTS header:

```
External Client
      |
      v
[ Public Entry - No HSTS ] ← Security scanners evaluate THIS
      |
      v
[ Internal Service - Has HSTS ]
```

**Result**: Security violation detected, regardless of internal HSTS configuration.

### Browser Security Model

Browsers implement HSTS by caching the policy from the first HTTPS response. Subsequent HSTS headers from internal services are irrelevant to external clients.

### Platform vs. Application Responsibilities

- **Platform**: Handle infrastructure-level security (TLS termination, HSTS, CORS, etc.)
- **Application**: Focus on business logic and application-level security (authentication, authorization, etc.)

## Troubleshooting

### Identifying Duplicate Headers

Use curl to check for duplicate headers:
```bash
curl -I https://your-domain.com/api/endpoint
```

Look for multiple Strict-Transport-Security headers in the response.

### Debugging Layer by Layer

1. **Check Application Response**:
   ```bash
   kubectl port-forward <pod-name> 8080:8080
   curl -I http://localhost:8080/health
   ```

2. **Check Gateway Response**:
   ```bash
   kubectl port-forward svc/gateway-service 8000:80
   curl -I -H "Host: yourdomain.com" http://localhost:8000/api/endpoint
   ```

3. **Check Edge Response**:
   ```bash
   curl -I https://your-domain.com/api/endpoint
   ```

### Verification Checklist

- [ ] Only one HSTS header in final response
- [ ] HSTS header present at edge layer
- [ ] Downstream services not adding HSTS headers
- [ ] Security scanner compliance verified
- [ ] Browser HSTS preload list compatibility (if applicable)

## Conclusion

Implementing HSTS in multi-layer architectures requires a clear separation of responsibilities. The platform should handle HSTS configuration at the edge layer only, while ensuring downstream services do not add duplicate headers. This approach:

- Ensures security compliance
- Prevents duplicate header issues
- Simplifies management and troubleshooting
- Maintains clear boundaries between platform and application concerns

By following these best practices, platforms can provide secure, compliant HSTS implementation while allowing applications to focus on business logic rather than infrastructure-level security concerns.