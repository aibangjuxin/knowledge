# Gemini Kubernetes Namespace Report
**Namespace:** 
lex

**Cluster:** 
default

**Generated:** Sat Aug 30 19:28:18 CST 2025

# Overall Resource Statistics

## Resource Count Summary
| Resource Type | Count |
|---------------|-------|
| Configmaps | 3 |
| Cronjobs | 0 |
| Daemonsets | 1 |
| Deployments | 3 |
| Endpoints | 3 |
| Hpa | 0 |
| Ingress | 0 |
| Jobs | 0 |
| Limitranges | 1 |
| Networkpolicies | 1 |
| Persistentvolumeclaims | 2 |
| Poddisruptionbudgets | 2 |
| Pods | 10 |
| Resourcequotas | 1 |
| Rolebindings | 1 |
| Roles | 1 |
| Secrets | 6 |
| Serviceaccounts | 2 |
| Services | 3 |
| Statefulsets | 0 |
| Vpa | 0 |

**Total Resources Found:** 40

# Container Images Statistics

## Image Usage Count
| Count | Image |
|-------|-------|
| 4 | `rancher/klipper-lb:v0.2.0` |
| 2 | `nginx:latest` |
| 1 | `redis:7-alpine` |
| 1 | `prom/node-exporter:latest` |
| 1 | `busybox:latest` |

## Registry Distribution
| Count | Registry | Type |
|-------|----------|------|
| 1 | `redis:7-alpine` | Private/Custom |
| 1 | `rancher` | Private/Custom |
| 1 | `prom` | Private/Custom |
| 1 | `nginx:latest` | Private/Custom |
| 1 | `busybox:latest` | Private/Custom |

# Ingress Analysis

No Ingress resources found.

# Secret Analysis

## Secret Type Distribution
| Count | Secret Type |
|-------|-------------|
| 2 | `Opaque` |
| 2 | `kubernetes.io/service-account-token` |
| 2 | `kubernetes.io/dockerconfigjson` |

# ConfigMap & Secret Usage Analysis

## ConfigMap Volume Mounts
| Count | ConfigMap Name |
|-------|----------------|
