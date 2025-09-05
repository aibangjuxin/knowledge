# Ingress Configuration Implementation

## Overview

This document describes the implementation of Ingress configurations for K8s cluster migration, supporting canary routing, multi-host/multi-path configurations, and hot configuration updates.

## Requirements Addressed

- **Requirement 2.1**: Request forwarding mechanism - Ingress configurations route traffic from old cluster to new cluster
- **Requirement 3.2**: Canary routing support - Weight-based, header-based, and cookie-based canary routing
- **Requirement 5.1**: Hot configuration updates - Dynamic configuration changes without restarting Ingress Controller

## Implementation Components

### 1. Ingress Resources (`k8s/ingress.yaml`)

#### Main Ingress (`bbdm-api-migration`)
- **Purpose**: Primary ingress for handling traffic to the migration proxy service
- **Features**:
  - SSL/TLS termination and redirect
  - Header preservation for proper request forwarding
  - Multiple path support (`/`, `/api`, `/health`)
  - Proxy configuration with timeouts and body size limits
  - Migration-specific annotations for tracking

#### Canary Ingress (`bbdm-api-canary`)
- **Purpose**: Handles canary traffic routing to new cluster
- **Features**:
  - Weight-based traffic splitting (0-100%)
  - Header-based routing (`X-Canary: new-cluster`)
  - Cookie-based routing (`canary=enabled`)
  - HTTPS backend support for new cluster
  - Initially disabled (canary: false, weight: 0)

#### Template Ingress (`migration-template`)
- **Purpose**: Template for creating new service ingresses
- **Features**:
  - Placeholder values for easy customization
  - Standard migration annotations
  - Reusable configuration pattern

#### Multi-Host Ingress (`multi-host-migration`)
- **Purpose**: Supports services with multiple domains
- **Features**:
  - Wildcard TLS certificate support
  - Multiple host rules
  - API versioning support (`/api/v1`, `/api/v2`)
  - Admin interface routing

### 2. Configuration Management (`k8s/ingress-config.yaml`)

#### Ingress Migration Config (`ingress-migration-config`)
- **ingress-config.yaml**: Main configuration for services and global settings
- **canary-rules.yaml**: Canary routing rules and rollback configuration
- **multi-host-config.yaml**: Multi-host and path routing configuration

#### Ingress Annotation Templates (`ingress-annotation-templates`)
- **standard-annotations.yaml**: Standard Nginx ingress annotations
- **header-preservation.conf**: Nginx configuration for header preservation
- **canary-annotations.yaml**: Canary-specific annotation templates
- **advanced-routing.conf**: Advanced routing rules and health checks

### 3. Management Scripts

#### Python Management Script (`scripts/manage-ingress.py`)
- **Features**:
  - Update canary weights dynamically
  - Enable/disable canary routing
  - Add new hosts and paths to existing ingresses
  - Validate ingress configurations
  - Get ingress status and health information
- **CLI Commands**:
  ```bash
  python3 manage-ingress.py set-weight bbdm-api 10
  python3 manage-ingress.py enable-canary bbdm-api --type weight --weight 5
  python3 manage-ingress.py add-path bbdm-api example.com /new-path
  python3 manage-ingress.py validate bbdm-api
  python3 manage-ingress.py status bbdm-api
  ```

#### Shell Management Script (`scripts/manage-ingress.sh`)
- **Features**:
  - User-friendly wrapper around Python script
  - Colored output and logging
  - Prerequisite checking
  - Deployment automation
  - Rollback functionality
- **Usage Examples**:
  ```bash
  ./manage-ingress.sh deploy
  ./manage-ingress.sh set-weight bbdm-api 25
  ./manage-ingress.sh enable-canary bbdm-api --type header
  ./manage-ingress.sh list
  ./manage-ingress.sh rollback bbdm-api
  ```

#### Validation Script (`scripts/validate-ingress.py`)
- **Features**:
  - YAML syntax validation
  - Kubernetes resource validation
  - Canary configuration validation
  - Annotation and label checking
  - TLS configuration validation
- **Usage**:
  ```bash
  python3 validate-ingress.py k8s/ingress.yaml --canary-validation
  ```

#### Test Script (`scripts/test-ingress.sh`)
- **Features**:
  - Comprehensive test suite (13 tests)
  - YAML syntax validation
  - Resource existence verification
  - Feature validation (canary, multi-host, TLS)
  - Management script testing
- **Usage**:
  ```bash
  ./test-ingress.sh
  ./test-ingress.sh --verbose --namespace my-namespace
  ```

## Key Features Implemented

### 1. Canary Routing Support

#### Weight-Based Routing
```yaml
nginx.ingress.kubernetes.io/canary: "true"
nginx.ingress.kubernetes.io/canary-weight: "10"  # 10% traffic to new cluster
```

#### Header-Based Routing
```yaml
nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"
nginx.ingress.kubernetes.io/canary-by-header-value: "new-cluster"
```

#### Cookie-Based Routing
```yaml
nginx.ingress.kubernetes.io/canary-by-cookie: "canary"
```

### 2. Multi-Host and Multi-Path Support

#### Multiple Hosts
- Primary API: `api-name01.teamname.dev.aliyun.intracloud.cn.aibang`
- Secondary API: `api-name02.teamname.dev.aliyun.intracloud.cn.aibang`
- Admin Interface: `admin.teamname.dev.aliyun.intracloud.cn.aibang`
- Wildcard Support: `*.teamname.dev.aliyun.intracloud.cn.aibang`

#### Multiple Paths
- Root: `/` (Prefix)
- API: `/api` (Prefix)
- Health: `/health` (Prefix)
- API Versions: `/api/v1`, `/api/v2` (Prefix)
- Admin: `/admin` (Prefix)

### 3. Hot Configuration Updates

#### Dynamic Weight Updates
```bash
# Update canary weight without restarting
kubectl patch ingress bbdm-api-canary -n namespace \
  --type merge -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"25"}}}'
```

#### Configuration Reloading
- Nginx Ingress Controller automatically reloads on annotation changes
- No service interruption during configuration updates
- Graceful rollback on configuration errors

### 4. TLS/SSL Support

#### Certificate Configuration
```yaml
spec:
  tls:
  - hosts:
    - api-name01.teamname.dev.aliyun.intracloud.cn.aibang
    secretName: bbdm-api-tls
```

#### SSL Redirect
```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "true"
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

### 5. Proxy Configuration

#### Header Preservation
```yaml
nginx.ingress.kubernetes.io/configuration-snippet: |
  proxy_set_header X-Original-Host $host;
  proxy_set_header X-Original-URI $request_uri;
  proxy_set_header X-Original-Method $request_method;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header X-Real-IP $remote_addr;
```

#### Timeout Configuration
```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
nginx.ingress.kubernetes.io/proxy-body-size: "100m"
```

## Migration Workflow

### Phase 1: Initial Setup
1. Deploy ingress configurations: `./manage-ingress.sh deploy`
2. Verify configurations: `./manage-ingress.sh validate bbdm-api`
3. Check status: `./manage-ingress.sh status bbdm-api`

### Phase 2: Canary Testing
1. Enable canary routing: `./manage-ingress.sh enable-canary bbdm-api --type weight --weight 5`
2. Monitor traffic and metrics
3. Gradually increase weight: `./manage-ingress.sh set-weight bbdm-api 10`

### Phase 3: Full Migration
1. Increase to 100%: `./manage-ingress.sh set-weight bbdm-api 100`
2. Monitor for 24-48 hours
3. Disable canary: `./manage-ingress.sh disable-canary bbdm-api`

### Phase 4: Cleanup
1. Remove old cluster references
2. Update ingress to point directly to new cluster
3. Clean up migration-specific annotations

## Monitoring and Observability

### Migration-Specific Annotations
```yaml
migration.k8s.io/enabled: "true"
migration.k8s.io/service-name: "bbdm-api"
migration.k8s.io/canary-enabled: "true"
migration.k8s.io/canary-weight: "10"
migration.k8s.io/target-cluster: "kong"
migration.k8s.io/last-updated: "2025-01-01T00:00:00Z"
```

### Status Monitoring
```bash
# Get detailed status
./manage-ingress.sh status bbdm-api

# List all migration ingresses
./manage-ingress.sh list

# Validate configuration
./manage-ingress.sh validate bbdm-api
```

## Security Considerations

### TLS Configuration
- All ingresses enforce HTTPS with SSL redirect
- TLS certificates managed via Kubernetes secrets
- Support for wildcard certificates

### Header Security
- Original headers preserved for audit trails
- Forwarded headers added for proper routing
- Real IP preservation for security logging

### Access Control
- RBAC permissions for ingress management
- Namespace isolation
- Service account restrictions

## Troubleshooting

### Common Issues

#### Canary Not Working
1. Check canary annotations: `kubectl get ingress bbdm-api-canary -o yaml`
2. Verify canary is enabled: `nginx.ingress.kubernetes.io/canary: "true"`
3. Check weight value: `nginx.ingress.kubernetes.io/canary-weight: "10"`

#### TLS Issues
1. Verify certificate exists: `kubectl get secret bbdm-api-tls`
2. Check certificate validity
3. Verify hostname matches certificate

#### Configuration Not Applied
1. Check ingress controller logs
2. Verify annotation syntax
3. Test with kubectl patch command

### Rollback Procedures
```bash
# Emergency rollback - disable canary
./manage-ingress.sh rollback bbdm-api

# Manual rollback - set weight to 0
./manage-ingress.sh set-weight bbdm-api 0

# Full rollback - disable canary routing
./manage-ingress.sh disable-canary bbdm-api
```

## Testing

### Automated Testing
```bash
# Run all tests
./test-ingress.sh

# Run with verbose output
./test-ingress.sh --verbose

# Test specific namespace
./test-ingress.sh --namespace my-namespace
```

### Manual Testing
```bash
# Test canary routing with header
curl -H "X-Canary: new-cluster" https://api-name01.teamname.dev.aliyun.intracloud.cn.aibang/

# Test canary routing with cookie
curl -b "canary=enabled" https://api-name01.teamname.dev.aliyun.intracloud.cn.aibang/

# Test different paths
curl https://api-name01.teamname.dev.aliyun.intracloud.cn.aibang/api/v1/health
```

## Conclusion

The ingress configuration implementation provides a comprehensive solution for K8s cluster migration with:

- ✅ **Canary routing** with multiple strategies (weight, header, cookie)
- ✅ **Multi-host and multi-path** support for complex services
- ✅ **Hot configuration updates** without service interruption
- ✅ **TLS/SSL support** with certificate management
- ✅ **Management tools** for easy operation
- ✅ **Validation and testing** for reliability
- ✅ **Monitoring and observability** for operational visibility

The implementation satisfies all requirements (2.1, 3.2, 5.1) and provides a robust foundation for safe and controlled cluster migration.