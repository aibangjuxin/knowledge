# GKE Traffic Flow & Architecture

This document outlines the end-to-end traffic flow from the client to the Google Kubernetes Engine (GKE) Runtime, detailing the multi-layer proxy architecture and GKE internal high-availability configuration.

## 1. High-Level Traffic Path

The general request flow passes through multiple network layers before reaching the GKE Pods:

**User Request** $\rightarrow$ **Nginx L7 (API Routing)** $\rightarrow$ **Nginx L4 (TCP Forwarding)** $\rightarrow$ **Kong DP (API Gateway)** $\rightarrow$ **GKE Runtime (Service & Pods)**

## 2. Detailed Architecture Diagram

```mermaid
graph TD
    %% Define Styles
    classDef external fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef proxy fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef k8s fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef pod fill:#ffffff,stroke:#2e7d32,stroke-width:1px,stroke-dasharray: 5 5;

    %% External & Proxies
    User[User / Client] :::external
    
    subgraph "External / DMZ"
        NginxL7[("Nginx L7<br/>(HTTP/API Routing)")] :::proxy
        NginxL4[("Nginx L4<br/>(TCP Forwarding)")] :::proxy
    end

    subgraph "Internal Network"
        Kong[("Kong Data Plane<br/>(API Gateway)")] :::proxy
    end

    %% GKE Cluster
    subgraph "GKE Cluster"
        Service[("K8s Service")] :::k8s
        
        subgraph "Deployment: Business App"
            direction TB
            
            subgraph "Node A"
                Pod1[("Pod-1<br/>(Running)")] :::pod
            end
            
            subgraph "Node B"
                Pod2[("Pod-2<br/>(Running)")] :::pod
            end
        end
    end

    %% Connections
    User -->|HTTP Request| NginxL7
    NginxL7 -->|Proxy Pass| NginxL4
    NginxL4 -->|TCP Stream| Kong
    Kong -->|Route & Upstream| Service
    Service -->|Endpoint Selection| Pod1
    Service -->|Endpoint Selection| Pod2

    %% Annotations
    NginxL7 -.->|Features: Header Processing, Routing| NginxL7
    Kong -.->|Features: Auth, Rate Limiting, Plugins| Kong
    Pod1 -.->|Readiness Probe: /health| Pod1
```

## 3. Component Details

### A. Nginx L7 (Layer 7 Proxy)
- **Role**: Handles Application Layer (HTTP/HTTPS) traffic.
- **Responsibilities**: 
  - API Routing (Path-based routing).
  - HTTP Header manipulation and processing.
  - SSL Termination (potentially).

### B. Nginx L4 (Layer 4 Proxy)
- **Role**: Handles Transport Layer (TCP) traffic.
- **Responsibilities**:
  - Bridging traffic across different network zones (e.g., DMZ to Internal).
  - TCP Forwarding to the API Gateway.

### C. Kong Data Plane (DP)
- **Role**: Internal API Gateway.
- **Responsibilities**:
  - Service discovery (Upstreams).
  - Authentication & Authorization plugins.
  - Rate limiting and traffic control.
  - Forwarding traffic to the specific GKE Service.

### D. GKE Runtime (RT)
The final destination where the application logic resides.

#### High Availability Configuration
The deployment is configured for high availability using **Rolling Updates** and **Anti-Affinity**.

- **Deployment Strategy**: `RollingUpdate`
  - `maxUnavailable: 1`: Ensures at most 1 pod is down during updates.
  - `maxSurge: 2`: Allows creating up to 2 extra pods during updates to speed up the process.

- **Health Checks (Readiness Probe)**:
  - Ensures traffic is only sent to healthy Pods.
  - **Path**: `/health`
  - **Scheme**: HTTPS
  - **Threshold**: 3 failures mark it unhealthy; 1 success marks it ready.

- **Node Affinity**:
  - Pods are scheduled on different Nodes (e.g., Node A and Node B) to prevent single-point-of-failure at the node level.
