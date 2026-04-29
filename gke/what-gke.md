# What is GKE (Google Kubernetes Engine)?

## Overview

**Google Kubernetes Engine (GKE)** is a managed Kubernetes service for deploying, managing, and operating containerized applications on Google Cloud Platform (GCP). It provides a fully managed control plane for Kubernetes clusters, eliminating much of the operational overhead of running Kubernetes yourself.

GKE is built on **Kubernetes** — the open-source container orchestration platform originally developed by Google, which draws from years of experience operating production workloads at scale on **Borg**, Google's internal cluster management system.

---

## Key Concepts

### What is Kubernetes?

Kubernetes (also known as **K8s**) is an open-source container orchestration system that automates:
- **Deployment** – rolling out containerized applications
- **Scaling** – adding or removing replicas based on load
- **Load balancing** – distributing traffic across containers
- **Self-healing** – restarting failed containers, replacing and rescheduling containers when nodes die
- **Configuration management** – managing secrets and configuration separately from containers

### What does "managed" mean?

Traditionally, running Kubernetes yourself means operating:
- The **control plane** (API server, scheduler, etcd) — the brain of the cluster
- The **worker nodes** — machines that run your containers
- Networking, security, upgrades, logging, monitoring, and more

GKE manages the **control plane** for you automatically. You only manage the **worker nodes** (in Standard mode) or let GKE manage those too (in Autopilot mode).

---

## GKE Modes of Operation

### GKE Standard

- You manage the worker nodes (node pools) yourself
- You have more control over node types, sizes, and scaling behavior
- You are responsible for node-level configuration and cost optimization
- More flexibility, more operational responsibility

### GKE Autopilot

- GKE manages the underlying node infrastructure for you
- Nodes are provisioned and scaled automatically based on your workloads
- You pay per-pod rather than per-node
- Optimized for developers who want less operational overhead
- Google handles node repairs, upgrades, and scaling

---

## Core Features

### 1. Container Orchestration
Deploy and manage Docker containers using familiar Kubernetes primitives:
- **Pods** – the smallest deployable unit (one or more containers)
- **Deployments** – declarative updates for Pods
- **Services** – stable network endpoints for accessing Pods
- **Ingress** – HTTP/HTTPS load balancing and routing
- **ConfigMaps & Secrets** – configuration and sensitive data management
- **Horizontal Pod Autoscaling (HPA)** – scale Pods based on CPU/memory metrics

### 2. Networking
- **Cluster networking** – containers communicate within the cluster
- **Services** – internal and external load balancing
- **Ingress** – integration with Google Cloud Load Balancing
- **Network policies** – firewall rules for Pod-to-Pod traffic
- **Private clusters** – restrict cluster to private IP ranges

### 3. Storage
- **Persistent Volumes** – durable storage for stateful applications
- **Dynamic provisioning** – auto-create storage when needed
- **CSI drivers** – support for various storage backends (PD, NFS, Cloud SQL, etc.)
- **Volume snapshots** – backup and restore persistent volumes

### 4. Security
- **Workload identity** – secure access to Google Cloud services (no static service account keys)
- **Binary Authorization** – enforce signed container images
- **Security context** – control container privileges and access
- **Network policies** – micro-segmentation
- **Secret management** – integrate with Google Secret Manager
- **RBAC** – role-based access control
- **GKE Sandbox** – additional layer of isolation for untrusted workloads

### 5. Scalability
- **Cluster autoscaler** – automatically adjusts the number of nodes in a node pool
- **Horizontal Pod Autoscaler (HPA)** – scale Pod replicas based on metrics
- **Vertical Pod Autoscaler (VPA)** – automatically adjust container resource requests
- **Node Auto-Provisioning** – automatically create new node pools based on workload demand
- **Multi-cluster** support – distribute workloads across multiple clusters

### 6. Operations & Observability
- **Cloud Logging** – integrated logging with Cloud Logging
- **Cloud Monitoring** – built-in metrics, dashboards, and alerting
- **Managed Prometheus** – optional Prometheus monitoring
- **GKE dashboards** – visual cluster management in Google Cloud Console
- **Upgrades** – GKE handles Kubernetes version upgrades

---

## Cluster Architecture

A GKE cluster consists of:

```
┌─────────────────────────────────────────────┐
│              GKE Cluster                     │
│                                              │
│  ┌─────────────────────────────────────┐    │
│  │      Control Plane (Managed by GKE)  │    │
│  │   - API Server                       │    │
│  │   - Scheduler                        │    │
│  │   - etcd                             │    │
│  │   - Cloud Controller Manager         │    │
│  └─────────────────────────────────────┘    │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Node Pool│  │ Node Pool│  │ Node Pool│  │
│  │ (e.g.    │  │ (GPU     │  │ (Spot    │  │
│  │  General)│  │  nodes)  │  │  VMs)    │  │
│  │          │  │          │  │          │  │
│  │ [Pod]    │  │ [Pod]    │  │ [Pod]    │  │
│  │ [Pod]    │  │ [Pod]    │  │ [Pod]    │  │
│  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────┘
```

### Cluster Types
- **Zonal cluster** – single zone, lower cost, single-zone availability
- **Regional cluster** – multiple zones within a region, higher availability
- **Multi-region cluster** – spread across regions (for disaster recovery)

---

## Use Cases

| Use Case | Description |
|----------|-------------|
| **Microservices** | Deploy and manage hundreds of microservices with service discovery, load balancing, and rolling updates |
| **CI/CD Pipelines** | Run containerized build, test, and deployment workloads at scale |
| **Web Applications** | Auto-scaling web apps with HTTP/HTTPS load balancing and global reach |
| **Data Processing / ML** | Run batch jobs, streaming, and ML training workloads (GPU/TPU support) |
| **API Backends** | Host RESTful or gRPC APIs with autoscaling and health checks |
| **Event-driven workloads** | Scale to zero with KEDA integration |
| **Hybrid / Multi-cloud** | GKE Fleet supports workloads across on-prem, GCP, and other clouds |

---

## GKE vs. Alternatives

| Feature | GKE | Amazon EKS | Azure AKS |
|---------|-----|------------|-----------|
| **Control plane management** | Fully managed | Fully managed | Fully managed |
| **Kubernetes upstream** | Yes | Yes | Yes |
| **Autopilot (hands-off nodes)** | Yes | No | No |
| **Native Google Cloud integration** | Deep (Cloud SQL, GCS, IAM, etc.) | Deep (AWS services) | Deep (Azure services) |
| **GKE Fleet (multi-cluster)** | Yes | EKS + Fargate | AKS + Arc |
| **Managed Prometheus** | Yes | Amazon Managed Prometheus | Azure Monitor |
| **AI/ML integration** | Strong (TPU, GPU, Vertex AI) | Moderate | Moderate |

---

## Getting Started (TL;DR)

```bash
# Install Google Cloud CLI and kubectl
brew install google-cloud-sdk

# Authenticate
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Create a GKE cluster
gcloud container clusters create my-cluster \
  --region us-central1 \
  --num-nodes=3 \
  --machine-type=e2-medium

# Get credentials for kubectl
gcloud container clusters get-credentials my-cluster --region us-central1

# Deploy an application
kubectl create deployment my-app --image=nginx:latest

# Expose it as a Service
kubectl expose deployment my-app --port=80 --type=LoadBalancer
```

---

## Pricing

- **GKE control plane** – Free (no charge for the managed control plane)
- **GKE Autopilot** – Pay per pod resource (CPU, memory,ephemeral storage)
- **GKE Standard** – Pay for the worker nodes (Compute Engine pricing)
- **Node types** – e2, n2, n2d, c2, a2, and more; preemptible/spot VMs available
- **Ephemeral storage** – charged separately from node compute

See [GKE pricing documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/gke-payments-model) for details.

---

## Further Reading

- [GKE Documentation](https://docs.cloud.google.com/kubernetes-engine/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [GKE Autopilot vs Standard](https://cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison)
- [Learn Kubernetes with Google](https://cloud.google.com/kubernetes-engine/docs/learn)

---

*Last updated: 2026-04-29*
