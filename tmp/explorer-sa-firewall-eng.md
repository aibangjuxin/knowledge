# GCP Firewall Rules — Service Account & GKE Deep Dive

> This document is based on GCP official documentation research and provides an in-depth analysis of three scenarios:
> 1. Firewall rules using Service Account as filter criteria (Ingress / Egress)
> 2. Firewall rules for communication between GCE and GKE (Node/Pod/Service)
> 3. Firewall configuration for GKE Pod egress via GCE NAT Gateway

---

## 1. Service Account as Firewall Filter Criteria

### 1.1 Core Limitations

GCP VPC Firewall Rules support for Service Account as source/destination is **direction-dependent**:

| Rule Direction | Target SA Available? | Source SA Available?           |
| -------------- | --------------------- | ------------------------------ |
| **Ingress**    | ✅ Yes                | ✅ Yes                         |
| **Egress**     | ✅ Yes                | ❌ **No** (IP CIDR only)       |

**Key Limitation**: Egress rule source can only be IP ranges, not Service Accounts.

### 1.2 Ingress Rules — Service Account as Source

Inbound rules can specify source as a Service Account within the same VPC:

```
Inbound rule source = <Service Account>
  → Packet source: Primary internal IP of instances using that SA
  → Implicit: Does not use alias IP ranges or external IPs
```

**Matching Logic**:
- Network interface must be in the VPC where the firewall rule is defined
- Virtual machine must match the source service account of the firewall rule
- Packets must use the primary internal IPv4 address (or IPv6) of that network interface

### 1.3 Egress Rules — Service Account as Target

Egress rules can use Service Account as **target** (which instances the rule applies to), but **source must be IP**:

```
Egress rule:
  Target       = <Service Account> ✅ Allowed
  Source       = <IP CIDR>        ❌ Must be IP, cannot be SA
  Destination  = <IP CIDR>        ✅ Allowed
```

### 1.4 nginx → squid Communication Case

- For the squid proxy, you need an Ingress rule.
- For the nginx server, you need an Egress rule.
- The target-service-accounts refers to the target host that needs the Egress rule.

```
Scenario: Nginx (abjx-nginx@project.iam.gserviceaccount.com) → Squid (abjx-squid@project.iam.gserviceaccount.com)
```

**Correct Configuration**:

```bash
# Nginx side: Egress rule (target = nginx SA, destination = squid IP range)
gcloud compute firewall-rules create allow-nginx-to-squid-egress \
  --network=vpc \
  --allow=tcp:3128 \
  --target-service-accounts=abjx-nginx@projectid.iam.gserviceaccount.com \
  --destination-ranges=<SQUID_IP>/32 \
  --direction=EGRESS

# Squid side: Ingress rule (target = squid SA, source = allowed range)
gcloud compute firewall-rules create allow-nginx-to-squid-ingress \
  --network=vpc \
  --allow=tcp:3128 \
  --target-service-accounts=abjx-squid@projectid.iam.gserviceaccount.com \
  --source-ranges=<SQUID_IP>/32 \
  --direction=INGRESS
```

**Limitations**:
- Egress destination still requires IP range, cannot use SA name for decoupling
- If Squid IP changes, must update Nginx's Egress rule

### 1.5 Decoupling Solutions Comparison

| Solution                  | Mechanism                            | Advantages           | Disadvantages               |
| ------------------------- | ------------------------------------ | -------------------- | --------------------------- |
| **Target SA + IP CIDR**   | Egress target uses SA, destination uses IP | Rule decoupled from source instance | Destination IP still requires maintenance |
| **Firewall Policy + FQDN** | NGFW Standard supports FQDN filtering | Fully domain-based, not IP-based | Requires NGFW Standard license |
| **GKE NetworkPolicy**      | Pod-level L3/L7 policy, label-based  | Fully decoupled from IP | GKE Pods only |
| **Istio/Service Mesh**     | VirtualService + AuthorizationPolicy  | L7 policy, fully decoupled | Introduces mesh complexity |

---

## 2. GCE ↔ GKE Communication Firewall Rules

### 2.1 GKE Network Address Architecture

GKE uses multiple IP ranges in VPC environment:

| Component        | Source                        | Example CIDR         |
| ---------------- | ----------------------------- | -------------------- |
| **Node**         | Node subnet (primary range)   | `10.0.0.0/24`       |
| **Pod**          | Secondary range (VPC alias)    | `100.64.0.0/14`     |
| **Service**      | Secondary range (another VPC alias) | `100.68.0.0/17` |
| **Control Plane**| Master IP range (private cluster) | `192.168.224.0/28` |

### 2.2 GCE VM Accessing GKE Pod

```
GCE VM (10.0.1.0/24) → GKE Pod (100.64.0.0/14)
```

**Required Firewall Rules**:

```bash
# 1. Allow inbound traffic from GCE VM (if GCE is the receiver)
gcloud compute firewall-rules create allow-gce-to-gke-pods \
  --network=vpc \
  --allow=tcp:80,tcp:443 \
  --source-ranges=10.0.1.0/24 \
  --target-tags=gke-nodes \
  --direction=INGRESS

# 2. GKE nodes allow traffic from GCE VM subnet (for NodePort/LoadBalancer)
gcloud compute firewall-rules create allow-gce-subnet-to-gke-nodes \
  --network=vpc \
  --allow=tcp:30000-32767 \
  --source-ranges=10.0.0.0/16 \
  --target-tags=gke-nodes \
  --direction=INGRESS

# 3. GKE Pod return traffic (stateful, automatically allowed)
# VPC firewall is stateful; return traffic is automatically permitted
```

### 2.3 GKE Pod Accessing GCE VM

```
GKE Pod (100.64.0.0/14) → GCE VM (10.0.1.0/24)
```

**Required Firewall Rules**:

```bash
# 1. GKE Pod egress rule (target = GKE nodes, destination = GCE subnet)
# Note: Egress source cannot use SA, must use IP range
gcloud compute firewall-rules create allow-pods-to-gce-egress \
  --network=vpc \
  --allow=tcp:5432 \
  --source-ranges=100.64.0.0/14 \
  --destination-ranges=10.0.1.0/24 \
  --direction=EGRESS

# 2. GCE VM ingress rule
gcloud compute firewall-rules create allow-pods-to-gce-ingress \
  --network=vpc \
  --allow=tcp:5432 \
  --source-ranges=100.64.0.0/14 \
  --target-tags=gce-vms \
  --direction=INGRESS
```

### 2.4 GKE Node Health Check Considerations

In GKE private clusters, L7 ILB health check source IPs come from:
- `35.191.0.0/16` (Google managed range)
- `130.211.0.0/22` (Google load balancer)

These need to be allowed in node ingress rules.

### 2.5 GKE NetworkPolicy vs VPC Firewall Rules

| Layer       | Tool             | Scope                  | Based On         |
| ----------- | ---------------- | ---------------------- | ---------------- |
| **VPC Layer** | Firewall Rules  | GCE Instance / Node    | IP / Tag / SA    |
| **Pod Layer** | NetworkPolicy   | Pod-to-Pod             | Label selector   |

**Best Practices**:
- VPC Firewall Rules manage Node-level ingress
- GKE NetworkPolicy manages Pod-level granular policies
- Use both together (defense in depth)

---

## 3. GKE Pod Egress via GCE NAT Gateway

### 3.1 Architecture Overview

```
Pod (100.64.x.x)
  → Node eth0
  → NAT Instance (iptables SNAT)
  → Internet

Return traffic automatically routes back through the NAT instance.
```

### 3.2 Firewall Rules on NAT Instance

NAT instance needs to allow forwarding of all traffic from GKE Nodes and Pods:

```bash
# NAT instance ingress rule
gcloud compute firewall-rules create allow-gke-to-nat-ingress \
  --network=vpc \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/20,100.64.0.0/14 \
  --target-tags=nat-gateway \
  --direction=INGRESS
```

### 3.3 GKE Node Egress Rules

```bash
# Allow GKE nodes to send traffic to NAT instance
gcloud compute firewall-rules create allow-gke-nodes-to-nat-egress \
  --network=vpc \
  --allow=tcp,udp,icmp \
  --source-tags=gke-nodes \
  --destination-ranges=<NAT_INSTANCE_INTERNAL_IP>/32 \
  --direction=EGRESS
```

### 3.4 NAT Instance iptables Configuration

Configure SNAT on the NAT instance:

```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
# Persist: echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# iptables SNAT rules (Pod IP → NAT IP)
iptables -t nat -A POSTROUTING -s 100.64.0.0/14 -o eth0 -j SNAT --to-source <NAT_IP>
iptables -t nat -A POSTROUTING -s 10.0.0.0/20 -o eth0 -j SNAT --to-source <NAT_IP>

# If DNAT is needed (external traffic into Pod)
iptables -t nat -A PREROUTING -i eth0 -d <NAT_IP> -j DNAT --to-destination <POD_IP>
```

### 3.5 Cloud NAT vs Manual iptables NAT

| Dimension        | Cloud NAT               | Manual iptables NAT           |
| ---------------- | ---------------------- | ----------------------------- |
| Configuration Complexity | Low (one-click enable) | High (manual iptables config) |
| Log Tracing      | Cloud Logging integration | Self-configure log           |
| Auto Connection Tracking | ✅ Yes              | Requires additional config    |
| Port Consumption | Billed per connection  | No extra cost                 |
| Pod CIDR Support | Native support         | Requires correct source range config |
| Recommended For  | Production preferred   | Experimental/simple scenarios |

### 3.6 GKE ip-masquerade-agent Integration

GKE uses ip-masquerade-agent by default to SNAT Pod traffic to node IP. If using a custom NAT gateway:

```yaml
# Configure non-masquerade CIDRs to route Pod traffic via NAT gateway instead of node IP
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masquerade-config
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
      - <CUSTOM_NAT_SUBNET>/24
```

---

## 4. Summary: Best Practices

### 4.1 Rule Design Principles

1. **Least Privilege**: Default deny, only allow required traffic
2. **Use SA instead of Tag as Target**:
   - SA binding is controlled by IAM, less likely to be accidentally modified
   - Tags can be directly modified by Compute Instance Admin
3. **Prefer SA as Source for Ingress**:
   - For intra-VPC instance-to-instance communication, SA is more stable than IP
4. **Egress Always Requires IP Ranges**:
   - Cannot use SA to decouple destination
   - Complement with FQDN Firewall Policy or GKE NetworkPolicy

### 4.2 GKE Scenario Specifics

- **GKE Node**: Can use Firewall Rule target/tag/sa
- **GKE Pod**: Firewall Rule operates at Node level, not directly on Pod
- **Pod-level Policy**: Use GKE NetworkPolicy (Calico/GKE Dataplane V2)
- **Service Communication**: Via ClusterIP/NodePort/LoadBalancer; Firewall Rule operates on Node ports

### 4.3 Strategies for Address Changes

| Scenario           | Solution                                              |
| ------------------ | ----------------------------------------------------- |
| IP changes frequently | Use GKE NetworkPolicy or Istio (based on label/name) |
| IP whitelist needed | Firewall Policy + FQDN object (NGFW Standard)        |
| Hybrid scenarios   | VPC Firewall Rule (coarse-grained) + GKE NetworkPolicy (fine-grained) |

---

## 5. References

- [VPC Firewall Rules](https://cloud.google.com/firewall/docs/firewalls)
- [Filter by service account](https://cloud.google.com/vpc/docs/firewalls#service-accounts)
- [GKE Network Policy](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)
- [Cloud NAT Documentation](https://cloud.google.com/nat/docs)
