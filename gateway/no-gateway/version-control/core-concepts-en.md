# Core Concepts: Version Control and Smooth Switching in GKE Gateway API No-Gateway Mode

This document summarizes the core concepts and best practices for managing backend service version control and smooth upgrades directly using GKE Gateway API, and provides detailed deployment configuration examples.

## 1. Core Architecture

In the No-Gateway mode, the GKE Gateway assumes the responsibility of traffic entry and routing distribution. The architecture design follows the **Immutable Infrastructure** principle.

*   **HTTPRoute (Routing Contract)**:
    *   Defines the external API structure (e.g., `/v2025`).
    *   **Does not carry** specific backend behavior configurations; it is only responsible for Matching, Filters (Filter/Rewrite), and Distribution (BackendRefs).
    *   Acts as the **sole atomic operation point** for version switching.

*   **Service (Immutable Backend)**:
    *   Each release version corresponds to an independent Kubernetes Service (e.g., `service-v11-25`).
    *   Releasing a new version means **creating a new Service**, not updating the old Service.

*   **Policies (Policy Binding)**:
    *   **HealthCheckPolicy** & **GCPBackendPolicy**: Must be **independently bound** to the Service of each version.
    *   The `metadata.name` of the Policy does not participate in routing logic; the only effective condition is that `targetRef` points to the corresponding Service.

---

## 2. Versioning Strategy

The goal is to separate the **stability of the external contract** from the **flexibility of internal releases**.

### URL Abstraction Model

*   **External URL**: `https://api.example.com/api/v2025/...`
    *   Uses the Major Version to maintain a long-term commitment to clients.
*   **Internal Routing**: Forwards to `service-v11-25`
    *   Uses the specific Patch Version to facilitate rollback and troubleshooting.

### Key Configuration: URL Rewrite

Utilize the Gateway API's `URLRewrite` filter to map the external generic path to the internal specific version path (if the backend application requires path version awareness).

```mermaid
graph TD
    Client[Client Request] -->|/api/v2025/users| GW[GKE Gateway]
    GW -->|Match PathPrefix: /api/v2025| Route[HTTPRoute]
    Route -->|URLRewrite: ReplacePrefix /api/v2025.11.23| Svc[Service: v2025.11.23]
    Svc --> Pod[Pod: v2025.11.23]
```

---

## 3. Workflow & Configuration

To achieve **Zero-Downtime** deployment, the following process must be strictly followed. The core principle is: **Verify deployment first, then switch atomically**.

### 3.1 Phase 1: Pre-deployment

In this phase, we need to create the new version of the backend Service and its associated GKE Policies.

#### 1. Create New Version Service
The new version Service (`service-v11-25`) must exist independently and cannot overwrite the old version.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: service-v11-25
  namespace: abjx-int-common
spec:
  selector:
    app: api-name-sprint-samples-v11-25
  ports:
  - port: 8443
    targetPort: 8443
```

#### 2. Bind HealthCheckPolicy
**Must** explicitly define the health check policy for the new Service.

```yaml
apiVersion: cloud.google.com/v1
kind: HealthCheckPolicy
metadata:
  name: hcp-service-v11-25
  namespace: abjx-int-common
spec:
  healthCheck:
    type: HTTP
    httpHealthCheck:
      port: 8443
      requestPath: /.well-known/healthcheck
  targetRef:
    group: ""
    kind: Service
    name: service-v11-25
```

#### 3. Bind GCPBackendPolicy
Configure backend parameters such as timeout and Connection Draining.

```yaml
apiVersion: cloud.google.com/v1
kind: GCPBackendPolicy
metadata:
  name: gbp-service-v11-25
  namespace: abjx-int-common
spec:
  backendConfig:
    # Configure specific backend parameters here, e.g., timeout
    timeoutSec: 40
  targetRef:
    group: ""
    kind: Service
    name: service-v11-25
```

#### 4. Verify Readiness
Ensure new resources are ready before switching traffic.
```bash
# Check resource creation
kubectl get svc service-v11-25 -n abjx-int-common
kubectl get healthcheckpolicy hcp-service-v11-25 -n abjx-int-common

# At this point, the new service should be started but receiving no external traffic
```

---

### 3.2 Phase 2: Traffic Switching

**Key Point:** Updates must be performed on the **same HTTPRoute object**.

#### Scenario: Upgrading from v11-24 to v11-25

Update the `backendRefs` and `URLRewrite` configuration of the HTTPRoute.

**Before Update (Pointing to v11-24):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-name-sprint-samples-route-v2025
  namespace: abjx-int-common
spec:
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api-name-sprint-samples/v2025
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /api-name-sprint-samples/v2025.11.24/
    backendRefs:
    - name: service-v11-24
      port: 8443
      weight: 1
```

**After Update (Pointing to v11-25):**
You can choose to replace directly or use weights for a canary release.

*   **Atomic Switch**:
    Directly modify `replacePrefixMatch` to the new path and change `backendRefs` to the new Service.

*   **Canary Switch (Recommended)**:
    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: api-name-sprint-samples-route-v2025
      namespace: abjx-int-common
    spec:
      rules:
      - matches:
        - path:
            type: PathPrefix
            value: /api-name-sprint-samples/v2025
        # Note: When using weights to split traffic to Services with different path versions,
        # a single URLRewrite might not meet the rewriting needs of both backends.
        # If paths differ between old and new versions, it is recommended to switch completely
        # or update in stages.
        # Here shows the final state after a full switch:
        filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /api-name-sprint-samples/v2025.11.25/
        backendRefs:
        - name: service-v11-25  # New service
          port: 8443
          weight: 1
    ```

### 3.3 Upgrade Process Sequence Diagram

```mermaid
sequenceDiagram
    participant Dev as Ops/CI
    participant K8s as K8s API
    participant GW as GKE Gateway
    participant SvcOld as Old Service (v11-24)
    participant SvcNew as New Service (v11-25)

    Note over Dev, SvcNew: Phase 1: Resource Preparation
    Dev->>K8s: 1. Create Service (v11-25)
    Dev->>K8s: 2. Bind HealthCheck/BackendPolicy (v11-25)
    K8s->>SvcNew: Deploy Pods and register Endpoints
    K8s->>SvcNew: GCP starts health check probing
    SvcNew-->>K8s: Health Check Passed (Healthy)

    Note over Dev, SvcNew: Phase 2: Verification
    Dev->>K8s: Check Service and Policy status
    K8s->>Dev: Resources Ready

    Note over Dev, SvcNew: Phase 3: Switching
    Dev->>K8s: Update HTTPRoute (Point to v11-25)
    K8s->>GW: Atomically update forwarding rules
    
    par Smooth Traffic Migration
        GW->>SvcOld: Stop forwarding traffic
        GW->>SvcNew: Start forwarding traffic
    end

    Note over Dev, SvcNew: Phase 4: Verification & Cleanup
    Dev->>GW: Verify /v2025/health response
    Dev->>K8s: Delete Old Service (v11-24)
```

---

## 4. FAQ

### Q1: Why can't I create a new HTTPRoute to release a new version?
GKE Gateway follows the **Oldest Wins** principle. If two HTTPRoutes configure the same `host` and `path`, the one created earliest will take effect, and the later one will be ignored. Therefore, you must update the existing HTTPRoute object.

### Q2: How to verify the gateway is ready?
Check the status of the HTTPRoute:
```bash
kubectl get httproute <name> -o jsonpath='{.status.parents[0].conditions}'
```
Ensure `Accepted` is `True` and `ResolvedRefs` is `True`.
You can also verify using `curl`:
```bash
curl -vk https://env-region.aliyun.cloud.uk.aibang/api-name-sprint-samples/v2025/health
```

### Q3: What is the difference between Ingress and Gateway API in switching?
*   **Ingress**: Typically relies on NGINX Reload or complex Annotation configurations to implement canary releases, and has weaker rewrite rule capabilities.
*   **Gateway API**: Natively supports multi-backend weight distribution, standard URLRewrite filters, provides clearer status feedback, and is more suitable for automated releases.
