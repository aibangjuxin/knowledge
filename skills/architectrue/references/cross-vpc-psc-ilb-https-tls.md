# Cross-VPC PSC NEG with ILB HTTPS TLS Termination

## What

Variant of `cross-project-psc-architecture` where the **Producer-side Internal LB terminates TLS itself** (instead of being plain HTTP pass-through to the MIG). Result: every cross-VPC / cross-network hop is TLS-encrypted; only the final ILB→MIG intra-VPC hop is plaintext HTTP. This is the pattern the user has named "Producer ILB 二次终结 TLS" and codified in `tenant-tls-setup-https.md`.

This is the **opposite design choice** from the standard pattern in `cross-project-psc-architecture`, which uses a Target HTTP Proxy / plain HTTP ILB and lets the GLB be the single TLS terminator.

## Key insight: Backend Service has TWO independent things, and `get-health` mixes them

A Backend Service is configured with both a **traffic forwarding spec** and a **health check spec**. They are completely independent:

| Dimension | Traffic forwarding | Health check |
|-----------|-------------------|--------------|
| Purpose | Send real user traffic to backend | Probe if backend is alive |
| How configured | `protocol` + `portName` (set at create) | `--health-checks=...` (set at create or update) |
| For ILB→MIG hop | `protocol=HTTP` + `portName=http` (= port 80) | `health-checks=ajbx-tenant-vpc-internal-https-hc` (HTTPS :443) |
| Visible in `get-health` output? | YES — appears as `port: 80` per backend instance | NO (port/protocol details live on the HC resource; only the *result* `healthState: HEALTHY/UNHEALTHY` shows in get-health) |

### The single most-misread line in `get-health` output

```
status:
  healthStatus:
  - healthState: HEALTHY
    instance: .../instances/ajbx-tenant-vpc-backend-8kgn
    ipAddress: 10.0.1.2
    port: 80       ← THIS IS THE TRAFFIC PORT, NOT THE HC PORT
  - healthState: HEALTHY
    instance: .../instances/ajbx-tenant-vpc-backend-17wp
    ipAddress: 10.0.1.3
    port: 80       ← same: traffic port
```

**Correct one-sentence summary** (user's own wording): "get-health 里的 `port: 80` 告诉您：如果现在有用户流量来，ILB 会往实例的 80 端口 转发；同时，该实例的可用性是由在 443 端口 跑的 HTTPS 健康检查保障的。"

Two things happen independently:
1. **Traffic**: BS sends real user requests to the instance's port 80 (because `protocol=HTTP` + `portName=http` → resolves to 80)
2. **Health probe**: GCP probe system opens an HTTPS connection to instance's port 443, GETs `/healthz`, and sets `healthState: HEALTHY/UNHEALTHY` based on the response

The `port: 80` in get-health tells you **nothing** about which port the health check uses. To see the HC's port/protocol, run:
```bash
gcloud compute health-checks describe ajbx-tenant-vpc-internal-https-hc \
    --project=$PROJECT --region=$REGION
# → httpsPort: 443, httpsHealthCheck: { port: 443, requestPath: /healthz, ... }
```

## Key insight: The 3 TLS hops are NOT what most people say

Common wrong phrasing (and the actual reality):

| What people think | What it actually is |
|-------------------|---------------------|
| TLS 1: Client → GLB | **CORRECT** — GLB terminates TrustAsia cert, SNI=tenant.taobao.abjx.uk |
| TLS 2: GLB → Backend Service | **CORRECT** — GLB re-encrypts to BS (BS protocol=HTTPS, port-name=https) |
| TLS 3: Backend Service → ILB | **WRONG**. BS→ILB is not one TLS hop. The actual hop 3 is **Service Attachment → ILB**, and the path between is: BS → NEG (HTTPS, since BS is HTTPS) → SA (PSC tunnel, GCP-internal, encrypted but not standard TLS) → ILB (TLS 3, terminated by ILB's HTTPS proxy) |

So the 3 TLS terminations happen at:
1. **GLB** (terminates Client→GLB)
2. **GLB** again (re-encrypts to BS)
3. **ILB** (terminates SA→ILB)

Between BS and ILB, the encryption is **PSC tunnel** (GCP-managed, encrypted) and **HTTPS** (BS→NEG, since BS protocol=HTTPS). Calling the whole BS→ILB stretch "TLS" hides the actual mechanism and makes it impossible to understand why the ILB has to terminate TLS at all.

## Key insight: LB family + PSC NEG compatibility

The "do I need `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`?" question is a recurring source of confusion. The actual LB family that PSC NEG works with:

| LB type | Flag | PSC NEG support | Proxy-only subnet purpose | Notes |
|---------|------|-----------------|---------------------------|-------|
| Classic External Application LB | `EXTERNAL` (no `_MANAGED`) | **NO** — explicitly rejected | `INTERNAL_HTTPS_LOAD_BALANCER` (deprecated) | The "classic" / "HTTP(S) LB" being sunset. Org policy `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed` is unrelated to this. |
| **Regional External Application LB** | `EXTERNAL_MANAGED` (regional) | **YES** ✅ | `REGIONAL_MANAGED_PROXY` | **This is the default for PSC NEG**. Port-range regional, IP regional. |
| Global External Application LB | `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` | **YES** (if Org Policy allows) | `REGIONAL_MANAGED_PROXY` (still!) | User often assumes this is required; it is not. |
| Regional Internal Application LB | `INTERNAL_MANAGED` | **YES** ✅ | `REGIONAL_MANAGED_PROXY` | For internal-only exposure; the **Producer ILB** in this doc. |
| Internal TCP/UDP LB (classic) | `INTERNAL` | NO (L4 only) | n/a | n/a |

**Key non-obvious facts**:
- The classic `EXTERNAL` LB is the only LB that **cannot** use PSC NEG backend. All `*_MANAGED` variants can.
- The `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` Org Policy does NOT block Regional external ALB.
- A PSC NEG backend service must be regional. Once a BS uses PSC NEG, the whole chain (BS, URL map, target proxy, forwarding rule) must be `--region=...` not `--global`.
- The proxy-only subnet purpose `INTERNAL_HTTPS_LOAD_BALANCER` is a CLASSIC-ALB artifact. Modern `*_MANAGED` ALBs all use `REGIONAL_MANAGED_PROXY` regardless of regional/global scope.

## Key insight: The "migration" prompt is a red herring

GCP Console sometimes warns: *"the purpose of your proxy-only subnet needs to be migrated from `INTERNAL_HTTPS_LOAD_BALANCER`"*. This warning only applies if the subnet was originally created for the **classic `EXTERNAL` LB** (the deprecated one). For a Regional external ALB on a fresh `REGIONAL_MANAGED_PROXY` subnet, no migration is needed.

## Content: Resource table pattern for v2-over-v1 docs

When the v2 doc (this variant) documents changes over the v1 doc (the standard HTTP-backend pattern), the **§0 resource tables should be self-contained** — include ALL resources in the chain, not just deltas. The user explicitly asked: "我通过这一个文档就能知道我所有的东西" / "我通过这一个文档就能知道我所有的东西，所有的资源". Recommended column shape:

| # | 资源 | 资源名称 | 创建资源的命令 | 状态 | 简单的Description |
|---|------|----------|----------------|------|-------------------|
| 1 | VPC | `ajbx-tenant-vpc` | `gcloud compute networks create ...` | v1 已建 | (description) |
| ... | ... | ... | ... | ... | ... |
| 16 | Health Check (HTTPS) | `ajbx-tenant-vpc-internal-https-hc` | `gcloud compute health-checks create https ...` | **v2 新建** | HTTPS :443 健康检查 |

The "状态" column is critical — without it, a colleague cannot tell which resources they need to *create* in the current phase vs which are pre-existing.

## Concrete instance

User's working setup (`aibang-12345678-ajbx-dev` project, region `europe-west2`):
- Producer VPC: `ajbx-tenant-vpc` (10.0.0.0/16) — MIG, ILB (L7 HTTPS :443), Service Attachment
- Consumer VPC: `aibang-12345678-ajbx-dev-cinternal-vpc1` (192.168.0.0/18) — External GLB, BS (HTTPS), PSC NEG

Full doc: `/Users/lex/git/gcp/ingress/public-ingress/tenant-tls-setup-https.md` (the v2 variant — full HTTPS chain).
Companion v1 doc: `/Users/lex/git/gcp/ingress/public-ingress/tenant-tls-setup.md` (HTTP backend variant — keep for diff/rollback).

## Common pitfalls

### Pitfall 1: Reading `port: 80` in `get-health` as "the HC is broken"

The most common confusion. `port: 80` = traffic port (from `portName=http` → 80 on the MIG). The HC is a SEPARATE configuration that determines `healthState`. The two are independent. To debug "is the instance actually HEALTHY for the right reason", run:
```bash
gcloud compute backend-services get-health <BS> --region=$REGION
# Look at: healthState (the RESULT) + port (the traffic port, NOT the HC port)

gcloud compute health-checks describe <HC> --region=$REGION
# Look at: port + protocol (this is what the HC actually probes)
```

### Pitfall 2: Conflating "BS protocol" with "BS backend encryption"

`protocol=HTTPS` on a Backend Service means: when the LB sends traffic to the backend, it uses HTTPS. This is a **different** setting from the LB-front-end protocol (which is set on the target proxy). For internal LBs, the target proxy is what the consumer side talks to; the BS protocol is what the LB uses to talk to the backend.

### Pitfall 3: Assuming "Regional external ALB" needs `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` allow-list

It does not. `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` is a specific LB type (Global scope). Regional external ALB has its own scope and is not affected by that Org Policy. The user's original belief that "I must enable GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS" was incorrect — they were already running Regional external ALB successfully without it.

### Pitfall 4: Treating `INTERNAL_HTTPS_LOAD_BALANCER` and `REGIONAL_MANAGED_PROXY` as interchangeable proxy-only subnet purposes

They are NOT. `INTERNAL_HTTPS_LOAD_BALANCER` was for the **classic (deprecated) HTTP(S) LB**. `REGIONAL_MANAGED_PROXY` is for all `*_MANAGED` LBs (Regional external, Global external, Regional internal). If a subnet was created with the old purpose and you're trying to use it with a `_MANAGED` LB, you DO need to migrate; but if you create a fresh subnet for a `_MANAGED` LB, use `REGIONAL_MANAGED_PROXY` and there is no migration concern.

## Trigger

Use this reference when:
- Working on a cross-VPC PSC NEG setup where the Producer-side LB terminates TLS
- Debugging "why is `port: 80` showing in `get-health`" or "is my health check working"
- Evaluating whether a project needs `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` Org Policy exception
- Choosing between Regional external ALB and Global external ALB for a PSC NEG backend
- Documenting v2 changes over a v1 PSC NEG doc (resource table self-containment pattern)
- Reviewing code/docs that mention `INTERNAL_HTTPS_LOAD_BALANCER` or `REGIONAL_MANAGED_PROXY` proxy-only subnet purposes
