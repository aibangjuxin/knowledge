# ExternalName Services Configuration

This document describes the ExternalName services configuration for the K8s cluster migration project.

## Overview

ExternalName services provide DNS resolution and port mapping to the new cluster endpoints, enabling the migration proxy to forward requests from the old cluster to the new cluster services.

## Service Architecture

```
Old Cluster (*.teamname.dev.aliyun.intracloud.cn.aibang)
├── migration-proxy (Nginx)
├── ExternalName Services
│   ├── new-cluster-bbdm-api → api-name01.kong.dev.aliyun.intracloud.cn.aibang
│   ├── new-cluster-gateway → kong.dev.aliyun.intracloud.cn.aibang
│   └── new-cluster-health → api-name01.kong.dev.aliyun.intracloud.cn.aibang
└── DNS Configuration (ConfigMap)

New Cluster (*.kong.dev.aliyun.intracloud.cn.aibang)
├── bbdm-api service
├── LoadBalancer services
└── Ingress controllers
```

## ExternalName Services

### 1. new-cluster-bbdm-api

**Purpose**: Primary API service mapping for bbdm-api migration

**Configuration**:
- **ExternalName**: `api-name01.kong.dev.aliyun.intracloud.cn.aibang`
- **Namespace**: `aibang-1111111111-bbdm`
- **Ports**: 80 (HTTP), 443 (HTTPS), 8078 (API)
- **Target Service**: `bbdm-api` in `kong-bbdm` namespace

**Usage**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: new-cluster-bbdm-api
  namespace: aibang-1111111111-bbdm
spec:
  type: ExternalName
  externalName: api-name01.kong.dev.aliyun.intracloud.cn.aibang
  ports:
  - port: 443
    name: https
  - port: 80
    name: http
  - port: 8078
    name: api
```

### 2. new-cluster-gateway

**Purpose**: Generic gateway service for new cluster access

**Configuration**:
- **ExternalName**: `kong.dev.aliyun.intracloud.cn.aibang`
- **Namespace**: `aibang-1111111111-bbdm`
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Target**: New cluster gateway/load balancer

### 3. new-cluster-health

**Purpose**: Health check and connectivity verification service

**Configuration**:
- **ExternalName**: `api-name01.kong.dev.aliyun.intracloud.cn.aibang`
- **Namespace**: `aibang-1111111111-bbdm`
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Usage**: Connectivity testing and health monitoring

## DNS Configuration

The DNS configuration is managed through a ConfigMap that contains:

1. **Service Mappings**: Old cluster to new cluster service mappings
2. **Port Mappings**: Port translation configuration
3. **Verification Scripts**: DNS resolution and connectivity testing

### Key Configuration Elements

```yaml
# DNS mappings
mappings:
  - old_host: "api-name01.teamname.dev.aliyun.intracloud.cn.aibang"
    new_host: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    service_name: "bbdm-api"
    ports: [80, 443, 8078]

# External service configurations
external_services:
  - name: "new-cluster-bbdm-api"
    external_name: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    namespace: "aibang-1111111111-bbdm"
    target_namespace: "kong-bbdm"
```

## Deployment

### Prerequisites

1. Kubernetes cluster access with appropriate permissions
2. `kubectl` configured for the target cluster
3. Namespace `aibang-1111111111-bbdm` exists

### Deployment Steps

1. **Deploy ExternalName Services**:
   ```bash
   kubectl apply -f k8s/external-services.yaml
   ```

2. **Deploy DNS Configuration**:
   ```bash
   kubectl apply -f k8s/dns-config.yaml
   ```

3. **Verify Deployment**:
   ```bash
   kubectl get svc -n aibang-1111111111-bbdm -l component=external-service
   ```

### Automated Deployment

Use the provided deployment script:

```bash
# Deploy all ExternalName services
./scripts/deploy-external-services.sh deploy

# Verify deployment
./scripts/deploy-external-services.sh verify

# Test connectivity
./scripts/deploy-external-services.sh test
```

## Validation and Testing

### 1. Service Validation

Validate that ExternalName services are correctly configured:

```bash
python3 scripts/validate-external-services.py --namespace aibang-1111111111-bbdm
```

### 2. DNS Resolution Testing

Test DNS resolution for new cluster endpoints:

```bash
# Test from within the cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup api-name01.kong.dev.aliyun.intracloud.cn.aibang

# Test from migration proxy pod
kubectl exec -it deployment/migration-proxy -n aibang-1111111111-bbdm -- nslookup api-name01.kong.dev.aliyun.intracloud.cn.aibang
```

### 3. Connectivity Testing

Test network connectivity to new cluster services:

```bash
# Run comprehensive connectivity test
./scripts/verify-connectivity.sh

# Test specific endpoint
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- http://api-name01.kong.dev.aliyun.intracloud.cn.aibang/health
```

### 4. Port Connectivity

Verify that all required ports are accessible:

```bash
# Test HTTPS connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv api-name01.kong.dev.aliyun.intracloud.cn.aibang 443

# Test HTTP connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv api-name01.kong.dev.aliyun.intracloud.cn.aibang 80
```

## Troubleshooting

### Common Issues

1. **DNS Resolution Failures**
   - Check if the external hostname is resolvable from the cluster
   - Verify DNS configuration in the cluster
   - Test with `nslookup` or `dig` from within a pod

2. **Port Connectivity Issues**
   - Verify firewall rules between clusters
   - Check if the target service is running and accessible
   - Test with `telnet` or `nc` from within the cluster

3. **Service Not Found**
   - Verify the service is deployed in the correct namespace
   - Check service labels and selectors
   - Ensure the ExternalName is correctly configured

### Debugging Commands

```bash
# Check service configuration
kubectl get svc new-cluster-bbdm-api -n aibang-1111111111-bbdm -o yaml

# Check service endpoints
kubectl get endpoints new-cluster-bbdm-api -n aibang-1111111111-bbdm

# Test from within the cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Check DNS resolution
kubectl exec -it deployment/migration-proxy -n aibang-1111111111-bbdm -- nslookup api-name01.kong.dev.aliyun.intracloud.cn.aibang

# Check connectivity
kubectl exec -it deployment/migration-proxy -n aibang-1111111111-bbdm -- curl -v https://api-name01.kong.dev.aliyun.intracloud.cn.aibang/health
```

## Security Considerations

1. **Network Policies**: Ensure appropriate NetworkPolicies allow traffic to external services
2. **TLS Verification**: Configure proper TLS certificate validation for HTTPS endpoints
3. **Access Control**: Limit access to ExternalName services based on service accounts and RBAC
4. **Audit Logging**: Enable audit logging for ExternalName service access

## Monitoring

### Key Metrics

1. **DNS Resolution Success Rate**: Monitor DNS resolution failures
2. **Connection Success Rate**: Track connection establishment success
3. **Response Time**: Monitor latency to external services
4. **Error Rates**: Track HTTP error rates from external services

### Monitoring Setup

The ServiceMonitor configuration includes metrics for ExternalName service usage:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: external-services-monitor
spec:
  selector:
    matchLabels:
      component: external-service
  endpoints:
  - port: metrics
    path: /metrics
```

## Next Steps

After successfully configuring ExternalName services:

1. **Configure Migration Proxy**: Update Nginx configuration to use ExternalName services
2. **Implement Health Checks**: Set up health checks for new cluster services
3. **Configure Ingress**: Update Ingress configuration to route traffic through the proxy
4. **Set up Monitoring**: Deploy monitoring and alerting for the migration process
5. **Test End-to-End**: Perform comprehensive end-to-end testing

## Related Documentation

- [Migration Proxy Configuration](../README.md)
- [Ingress Configuration](./ingress-config.md)
- [Monitoring Setup](./monitoring.md)
- [Troubleshooting Guide](./troubleshooting.md)