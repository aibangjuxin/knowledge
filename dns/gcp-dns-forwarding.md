# GCP Cloud DNS Forwarding — Deep Dive

> **Goal:** Explain what Cloud DNS Forwarding does, how it interacts with your VPC and GKE workloads, and what it means in practice when applied to a GKE-hosted VPC.

---

## 1. The Three DNS Primitives in Cloud DNS

Before diving into Forwarding, it helps to understand how it differs from its two siblings.

| Primitive | What it does | Direction | Managed by whom |
|-----------|-------------|-----------|-----------------|
| **DNS Peering** | Lets your VPC **pull** DNS zones from another VPC over a VPC Network Peering link | VPC-to-VPC (bidirectional, via peering) | Both VPCs must agree; uses internal GCP peering |
| **Forwarding Zone** | Lets Cloud DNS **push** queries for a given domain suffix to **target IP addresses** you specify | VPC → your own or third-party DNS server | Your GCP project |
| **Response Policy** | Lets Cloud DNS **intercept** queries and return **custom answers** you define — no upstream needed | Inline (Cloud DNS answers directly) | Your GCP project |

These three are **mutually exclusive per (VPC, domain-suffix)** pair. If a query matches both a Forwarding Zone and a Response Policy, Response Policy wins.

---

## 2. What DNS Forwarding Actually Is

A **Forwarding Zone** is a DNS configuration object in Cloud DNS. You give it:

- A **domain name prefix** (e.g. `aibang.`, `internal.corp.`, `azure.com.`)
- One or more **target IP addresses** — the IP of your actual DNS server(s) that should handle queries for that prefix

When any VM, GKE node, or Pod in the VPC asks Cloud DNS for a name that falls under that prefix, Cloud DNS **forwards the query over the VPC network** to the target IP(s) you specified, and returns whatever the target DNS server says.

```
VPC subnet 10.0.1.0/24
  │
  ├─ GKE node (10.0.1.10)
  │    Pod (10.1.2.15)       ← resolves "svc.internal.aibang"
  │         │
  │         │  dig svc.internal.aibang
  │         ▼
  └─ Cloud DNS resolver (169.254.254.254)   ← VPC-level resolver
           │
           │  matches Forwarding Zone: "aibang." → target 10.0.100.53
           ▼
       Target DNS server 10.0.100.53        ← your internal Unbound/BIND/AWS DNS
           │
           │  Answers with 10.0.50.20
           ▼
       Response returned to Pod
```

**Key property:** The forwarding happens **inside your VPC** — the query never leaves your Google Cloud network to reach the target DNS server. The target just needs to be reachable from the VPC (same VPC, VPC peering, Cloud VPN, etc.).

---

## 3. What "Applied to VPC" Means

When you create a Forwarding Zone in Cloud DNS, it is **not active by default**. You must **associate** it with one or more VPC networks. This is done via the `gcloud dns managed-zones update` command or the Console.

Once associated, every query originating from that VPC for the forwarding prefix hits the target IP(s). The association is at the **VPC level**, not at the subnet level — it applies to the entire VPC across all subnets, zones, and workloads.

```bash
# Create a forwarding zone
gcloud dns managed-zones create "aibang-internal" \
  --description="Forward aibang. to our internal DNS" \
  --dns-name="aibang." \
  --forwarding-targets="10.0.100.53" \
  --target-network-networks="https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/networks/YOUR_VPC"

# Update an existing zone to forward to target IPs
gcloud dns managed-zones update "aibang-internal" \
  --forwarding-targets="10.0.100.53" \
  --target-network-networks="https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/networks/YOUR_VPC"
```

After associating, the VPC-level Cloud DNS resolver (`169.254.254.254`) will intercept matching queries and forward them. No Pod or VM configuration changes needed — they all already use the VPC resolver.

---

## 4. The Full DNS Resolution Order in a GKE Context

GKE workloads do **not** use kube-dns or CoreDNS directly when Cloud DNS is the VPC DNS provider. Instead, every Pod's `/etc/resolv.conf` points to `169.254.254.254` (the VPC resolver):

```
nameserver 169.254.254.254
search <namespace>.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

When a Pod resolves `svc.internal.aibang`, the resolution chain is:

```
Step 1  Pod: "I need to resolve svc.internal.aibang"
Step 2  Pod sends UDP/TCP query to 169.254.254.254 (VPC resolver)
Step 3  VPC resolver: "Does this match any of my authoritative zones in this VPC?"
         → No match for "aibang."
Step 4  VPC resolver: "Does this match any Forwarding Zone in this VPC?"
         → YES: Forwarding Zone "aibang." → targets: [10.0.100.53]
Step 5  VPC resolver FORWARDS the query to 10.0.100.53 over VPC network
Step 6  Target DNS server (e.g. Unbound) processes the query
         → Looks up internal.aibang in its zone data
         → Returns A record: 10.0.50.20
Step 7  VPC resolver receives the answer
Step 8  VPC resolver returns answer to Pod
Step 9  Pod receives: 10.0.50.20
```

If the query were for `www.google.com` (no matching Forwarding Zone), Cloud DNS would **recurse to public DNS** directly — it would NOT use any forwarding target.

---

## 5. What Applying a Forwarding Zone Does to Your GKE Workloads

### 5.1 Transparent to Pods

**Nothing changes for your Pods.** They continue sending queries to `169.254.254.254`. The forwarding happens downstream, inside the VPC resolver. Your application code, Kubernetes Services, and DNS configuration in the cluster remain untouched.

### 5.2 DNS Reachability for Internal Domains

This is the primary benefit. After adding a Forwarding Zone for `aibang.`:

| Before | After |
|--------|-------|
| Pod queries `internal.aibang` → Cloud DNS public recursion → NXDOMAIN (or wrong answer) | Pod queries `internal.aibang` → Cloud DNS → forwarded to `10.0.100.53` → correct internal IP returned |

Your GKE workloads can now resolve internal corporate domains just like VMs in the same VPC.

### 5.3 The Target DNS Server Must Be Reachable

This is the critical constraint. Cloud DNS forwards queries **from Google's infrastructure to IPs inside your VPC**. The target DNS server must be:

- **Accessible from the VPC** (same VPC, VPC Peering, VPN, Interconnect)
- **Listening on UDP/TCP port 53**
- **Not blocked by VPC Firewall rules** (allow UDP/TCP 53 from `169.254.0.0/16` at minimum)
- **Stable IP** — forwarding targets do not support high-availability automatically; use a load-balanced IP or an internal HTTP(S) load balancer in front of your DNS fleet

If the target DNS server is unreachable, Cloud DNS will **retry** across all configured target IPs, but will eventually return `SERVFAIL` to the Pod — your workloads will get a DNS failure.

### 5.4 GKE Control Plane Implications

Forwarding Zones do **not** affect the GKE control plane. GKE's API server access and managed services are independent of DNS forwarding. However:

- **Workload Identity:** If your GKE workloads use Workload Identity to call GCP APIs, ensure the target DNS can resolve `logging.googleapis.com`, `storage.googleapis.com`, etc. — or these may fail if forwarding is misconfigured for public domains.
- **Node Local DNS Cache:** GKE offers a node-level DNS cache (`168.254.169.254` per node). Forwarding still works through it, but the cache reduces forwarding frequency for repeated queries.

### 5.5 Interaction with DNS Peering

If you also have DNS Peering configured for the same domain prefix, there is a **priority order**:

```
Response Policy (highest priority — Cloud DNS answers directly)
       ↓
DNS Peering (Cloud DNS pulls zone from another VPC over peering)
       ↓
Forwarding Zone (Cloud DNS forwards to target IPs)
       ↓
Default recursion (Cloud DNS queries public internet)
```

For the **same domain suffix**, only one mechanism applies. If you configure both a Forwarding Zone and a Peering Zone for `aibang.`, Forwarding Zone takes precedence over Peering within the same VPC.

### 5.6 Return Path — Important for Firewalls

When Cloud DNS forwards to your target IP, the **reply comes directly from that IP** back to the Pod through normal VPC routing. This means:

- The target DNS server's egress must be able to reach Pod IPs (`10.1.0.0/16` etc.)
- Firewall rules on the target DNS server side must allow UDP/TCP 53 from the VPC CIDR
- VPC firewall on GCP side must allow the forwarded traffic: allow UDP/TCP 53 from `169.254.0.0/16` to target IP

---

## 6. Common Patterns in Production

### Pattern 1: Forward Internal Corporate Domain to On-Premises DNS

```
GKE VPC ──(Forwarding Zone "corp.")──→ Cloud VPN ──→ On-prem BIND server 10.0.200.53
```

Your GKE pods resolve `svc.internal.corp` which the on-prem DNS handles.

### Pattern 2: Forward Third-Party Cloud Domain to AWS/Azure DNS

```
GKE VPC ──(Forwarding Zone "azure.com.")──→ Target: AWS Route53Resolver IP or Azure DNS 168.63.129.16
```

Useful when GKE workloads need to resolve resources in another cloud.

### Pattern 3: Forward + Response Policy Hybrid

```
Forwarding Zone "aibang."  ──→ Internal Unbound 10.0.100.53
Response Policy             ──→ Override specific record "dev.aibang." → 10.0.50.100 (bypass Unbound)
```

Cloud DNS first checks Response Policy, then falls back to Forwarding.

### Pattern 4: GKE Using Node Local DNS Cache + Forwarding

```
GKE Node (cache at 169.254.169.254)
  └─ Cache miss → VPC resolver 169.254.254.254
        └─ matches Forwarding Zone "aibang." → 10.0.100.53
```

Node Local DNS cache reduces latency for repeated queries within the node. First query still goes through the forwarding chain.

---

## 7. Troubleshooting Forwarding Issues in GKE

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Pod cannot resolve internal domain | Target DNS unreachable from VPC | Verify VPC peering/VPN is up; check firewall rules allow UDP/TCP 53 from `169.254.0.0/16` |
| Forwarding Zone created but not working | Zone not associated with VPC | Run `gcloud dns managed-zones describe <zone>` and check `forwardingTarget` and `visibility` |
| DNS queries timeout | All target IPs unreachable or not responding | Add multiple targets for redundancy; check if DNS server process is running |
| Responses are slow | Single forwarding target with high latency | Deploy a local caching DNS (Unbound) in the VPC; use node local DNS cache |
| Internal domain resolves to public IP | Forwarding Zone target returning public IP | Check target DNS configuration; consider Response Policy to override specific records |
| Peering overrides forwarding unexpectedly | Peering zone has higher priority | Verify only one mechanism is configured per domain suffix |

```bash
# Verify forwarding zone is associated
gcloud dns managed-zones describe aibang-internal --format="yaml(forwardingConfig,visibility)"

# Test from a GKE node or a VM in the same VPC
dig @169.254.254.254 svc.internal.aibang

# Check VPC DNS config
gcloud compute networks describe YOUR_VPC --format="yaml(dnsConfiguration)"

# View Cloud DNS query logs (requires Cloud Logging)
gcloud logging read 'resource.type="dns_query" AND query_name="svc.internal.aibang."' --limit=20
```

---

## 8. Security Considerations

1. **Least-privilege firewall:** Allow UDP/TCP 53 from `169.254.0.0/16` only — do not allow from `0.0.0.0/0`.
2. **Target DNS hardening:** Run your forwarding target on a dedicated node/VM, not a general-purpose workload, and disable recursion there (it should only serve your zones).
3. **No forwarded leaks:** If the target DNS recurses to public internet for unknown domains, those queries will originate from your VPC — billable egress may apply.
4. **Response Policy + Forwarding separation:** If you need some records to be overridden (Response Policy) while forwarding the rest, ensure the Response Policy rule has higher priority — Cloud DNS handles this automatically.
5. **DNSSEC:** Forwarding Zones can be signed with DNSSEC; however, the target DNS must also support DNSSEC validation if you expect validated answers.

---

## 9. Comparison: Forwarding vs Peering vs Response Policy

| Criteria | Forwarding Zone | DNS Peering | Response Policy |
|----------|----------------|-------------|-----------------|
| **Use case** | Forward queries to your own / third-party DNS | Share zones between two VPCs you own | Override answers or redirect queries inline |
| **Requires** | Target IP addresses reachable from VPC | VPC Network Peering between both VPCs | Just Cloud DNS (no network pre-req) |
| **Data ownership** | You control the target server | Shared zone lives in peer VPC | You define rules in Cloud DNS |
| **Propagation** | Instant after VPC association | Minutes (VPC peering must be active) | Instant |
| **Works with on-prem** | Yes (via Cloud VPN/Interconnect) | No (VPC-to-VPC only) | Yes |
| **Supports DNSSEC** | Yes | Yes | Limited |
| **Quota** | Per-project limit on forwarding zones | Shares VPC Peering quota | Per-project limit on response policies |

---

## 10. Key Takeaways for GKE

1. **Forwarding Zones are VPC-level configuration.** Once associated, every Pod in that VPC that queries the matching domain suffix will have its query forwarded — no Pod-level changes needed.

2. **The target DNS server is the single point of failure.** If you only have one forwarding target and it goes down, all matching DNS queries fail. Always configure at least two targets.

3. **Return traffic must be possible.** The forwarding is stateless UDP/TCP over the VPC — ensure firewall rules allow the reply path from your DNS server back to Pod CIDRs.

4. **Forwarding does not replace recursive resolution.** Cloud DNS still recurses to public DNS for non-matching domains — your GKE pods can still reach `google.com`, `github.com`, etc. without any forwarding.

5. **Node Local DNS cache + Forwarding = best practice.** Place a node-level cache on each GKE node to reduce forwarding overhead for hot queries, while forwarding handles the internal domain lookups transparently.

6. **Forwarding Zone and Peering Zone can conflict.** If you configure both for the same domain suffix on the same VPC, Forwarding Zone wins. Use one mechanism per domain.

---

## 11. Diagram

See accompanying diagram: `gcp-dns-forwarding.drawio.png`

The diagram illustrates:
- DNS resolution flow from Pod through VPC resolver to forwarding target
- Comparison of the three DNS primitives (Peering, Forwarding, Response Policy)
- Node Local DNS cache placement in the GKE context

---

## 12. Related Files

| File | Description |
|------|-------------|
| `dns/docs/dns-peerning.md` | DNS Peering — cross-VPC zone sharing |
| `dns/docs/dns-v2.md` | Cloud DNS v2 configuration reference |
| `dns/docs/verify-dnspeering.md` | DNS Peering verification scripts |
| `dns/docs/migrate-dns-enhance.md` | DNS migration procedures |
| `dns/docs/private-access/create-private-access-usage.md` | Private access endpoints |
| `dns/docs/cloud-dns.md` | Cloud DNS general overview |

---

*Document version: 1.0.0 — 2026-04-30*
