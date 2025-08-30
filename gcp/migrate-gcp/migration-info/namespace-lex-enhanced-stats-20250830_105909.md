# Enhanced Kubernetes Namespace Statistics Report
**Namespace:** lex
**Cluster:** default
**Generated:** Sat Aug 30 10:59:09 CST 2025

# Overall Resource Statistics

## Resource Count Summary
| Resource Type | Count |
|---------------|-------|
| Deployments | 3 |
| DaemonSets | 1 |
| StatefulSets | 0 |
| Jobs | 0 |
| CronJobs | 0 |
| Services | 3 |
| Endpoints | 3 |
| HPAs | 0 |
| VPAs | 0 |
| ConfigMaps | 3 |
| Secrets | 6 |
| Ingresses | 0 |
| NetworkPolicies | 1 |
| Pods | 10 |
| PVCs | 2 |
| ServiceAccounts | 2 |
| RoleBindings | 1 |
| Roles | 1 |
| PodDisruptionBudgets | 2 |
| ResourceQuotas | 1 |
| LimitRanges | 1 |

**Total Workloads:** 4
**Total Resources:** 27

# Container Images Statistics

## Image Usage Count
| Count | Image |
|-------|-------|
| 4 | rancher/klipper-lb:v0.2.0 |
| 2 | nginx:latest |
| 1 | redis:7-alpine |
| 1 | prom/node-exporter:latest |
| 1 | busybox:latest |

## Registry Distribution
| Count | Registry | Type |
|-------|----------|------|
| 1 | redis:7-alpine | Private/Custom |
| 1 | rancher | Private/Custom |
| 1 | prom | Private/Custom |
| 1 | nginx:latest | Private/Custom |
| 1 | busybox:latest | Private/Custom |

## Image Pull Policy Distribution
| Count | Pull Policy |
|-------|-------------|
| 6 | IfNotPresent |
| 2 | Never |
| 2 | Always |

**Total unique images:**        5

# Health Probes Statistics

## Liveness Probe Analysis

### Liveness Probe Types
| Count | Probe Type |
|-------|------------|
| 3 | httpGet |
| 1 | tcpSocket |

### HTTP Liveness Probe Paths
| Count | Path | Port |
|-------|------|------|
| 1 | /metrics | 9100 |
| 1 | /health | 80 |
| 1 | / | 80 |

## Readiness Probe Analysis

### Readiness Probe Types
| Count | Probe Type |
|-------|------------|
| 3 | httpGet |
| 1 | exec |

### HTTP Readiness Probe Paths
| Count | Path | Port |
|-------|------|------|
| 1 | /ready | 80 |
| 1 | / | 9100 |
| 1 | / | 80 |

## Startup Probe Analysis

### Startup Probe Types
| Count | Probe Type |
|-------|------------|
| 2 | httpGet |

## Probe Timing Configuration
| Probe Type | Common Initial Delay | Common Period | Common Timeout |
|------------|---------------------|---------------|----------------|
| livenessProbe | 30s | 20s | 3s |
| readinessProbe | 5s | 10s | 3s |
| startupProbe | 10s | 10s | 5s |

# Service Account Statistics

## Service Account Usage
| Count | Service Account |
|-------|-----------------|
| 4 | default |
| 1 | web-service-account |

# Container Ports Statistics

## Port Usage
| Count | Port | Protocol | Name |
|-------|------|----------|------|
| 1 | 9100 | TCP | metrics |
| 1 | 9100 | TCP | lb-port-9100 |
| 1 | 80 | TCP | lb-port-80 |
| 1 | 80 | TCP | http |
| 1 | 6379 | TCP | redis |
| 1 | 6379 | TCP | lb-port-6379 |
| 1 | 443 | TCP | lb-port-443 |
| 1 | 443 | TCP | https |

# Service Types Statistics

## Service Type Distribution
| Count | Service Type |
|-------|--------------|
| 1 | NodePort |
| 1 | LoadBalancer |
| 1 | ClusterIP |

## Service Port Distribution
| Count | Port | Target Port | Protocol |
|-------|------|-------------|----------|
| 3 | 80 | 80 | TCP |
| 1 | 9100 | 9100 | TCP |
| 1 | 6379 | 6379 | TCP |
| 1 | 443 | 443 | TCP |

## Session Affinity Distribution
| Count | Session Affinity |
|-------|------------------|
| 2 | None |
| 1 | ClientIP |

# Resource Requirements Statistics

## CPU Requests Distribution
| Count | CPU Request |
|-------|-------------|
| 3 | 100m |
| 1 | 50m |
| 1 | 25m |

## Memory Requests Distribution
| Count | Memory Request |
|-------|----------------|
| 3 | 64Mi |
| 1 | 32Mi |
| 1 | 128Mi |

## CPU Limits Distribution
| Count | CPU Limit |
|-------|-----------|
| 3 | 200m |
| 1 | 50m |
| 1 | 100m |

## Memory Limits Distribution
| Count | Memory Limit |
|-------|--------------|
| 3 | 128Mi |
| 1 | 64Mi |
| 1 | 256Mi |

# Volume Types Statistics

## Volume Type Distribution
| Count | Volume Type |
|-------|-------------|
| 2 | persistentVolumeClaim |
| 2 | hostPath |
| 2 | emptyDir |
| 2 | configMap |

## Persistent Volume Claims
| Name | Storage Class | Access Mode | Size | Status |
|------|---------------|-------------|------|--------|
| static-content-pvc | standard | ReadWriteOnce | 5Gi | Pending |
| redis-data-pvc | fast-ssd | ReadWriteOnce | 2Gi | Pending |

# Scaling Configuration Analysis

## Pod Disruption Budgets
| Name | Min Available | Max Unavailable | Selector |
|------|---------------|-----------------|----------|
| busybox-pdb | 1 | N/A | app=busybox |
| complex-web-app-pdb | 2 | N/A | app=complex-web-app |

# Network Policies Analysis

## Network Policy Summary
| Name | Pod Selector | Ingress Rules | Egress Rules |
|------|--------------|---------------|--------------|
| complex-web-app-netpol | app=complex-web-app | 2 | 2 |

## Policy Types Distribution
| Count | Policy Types |
|-------|--------------|
| 1 | Ingress,Egress |

# RBAC Analysis

## Service Accounts
| Name | Secrets | Image Pull Secrets |
|------|---------|-------------------|
| default | 1 | 0 |
| web-service-account | 2 | 2 |

## Role Bindings
| Name | Role | Subject Type | Subject Name |
|------|------|--------------|--------------|
| web-app-rolebinding | web-app-role | ServiceAccount | web-service-account |

## Roles
| Name | Rules Count | Resources |
|------|-------------|-----------|
| web-app-role | 3 | configmaps,deployments,pods,secrets |

# Resource Quotas and Limits Analysis

## Resource Quotas
| Name | CPU Limit | Memory Limit | Pods Limit |
|------|-----------|--------------|------------|
| lex-resource-quota | 8 | 16Gi | 20 |

## Limit Ranges
| Name | Type | Default CPU | Default Memory | Max CPU | Max Memory |
|------|------|-------------|----------------|---------|------------|
| lex-limit-range | Container | 200m | 256Mi | 1 | 1Gi |
| lex-limit-range | Pod | N/A | N/A | 2 | 2Gi |

# Migration-Specific Analysis

## Security Context Analysis
| Count | Run As Non Root | Privileged | Read Only Root FS |
|-------|-----------------|------------|-------------------|
| 6 | false | false | false |
| 2 | true | false | true |
| 1 | true | false | false |

## Node Placement Analysis
| Workload | Node Selector | Affinity | Tolerations |
|----------|---------------|----------|-------------|
| Deployment/nginx-deployment | No | No | 0 |
| Deployment/busybox-deployment | No | No | 0 |
| Deployment/complex-web-app | Yes | Yes | 1 |
| DaemonSet/svclb-complex-web-app-service | No | No | 3 |

## Migration Checklist

### Critical Items to Verify:
- [ ] **Container Registry Access** - Ensure target cluster can pull all images
- [ ] **Storage Classes** - Verify storage classes exist in target cluster
- [ ] **Network Policies** - Review and adapt network security policies
- [ ] **RBAC Configuration** - Ensure service accounts and roles are properly configured
- [ ] **Resource Quotas** - Check if resource quotas need adjustment
- [ ] **Node Selectors** - Verify node labels and selectors compatibility
- [ ] **Persistent Volumes** - Plan data migration strategy for PVCs
- [ ] **Health Check Paths** - Verify probe endpoints are accessible
- [ ] **Security Contexts** - Review security policies and constraints
- [ ] **External Dependencies** - Check external service connectivity

