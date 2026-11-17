# Architecture One-Liner Pattern

The pattern for writing a single sentence that **explains an architecture to non-engineers** without losing the technical core. Captures the user's preference, the formula, and 4 worked examples from the session.

## Why this matters

The user asked: "我想,比如说给别人去讲我这个东西是做了一个什么,我的架构是什么样的时候,我应该用怎么的方式去表达比较合适?"

The answer is: lead with **what & why**, not **tech stack**. The existing line "架构: GKE + Istio 1.30 minimal (only istiod) + K8s Gateway API v1.5.1 + ListenerSet 多租户" is a **tech stack list** — it answers "what versions did you pin" but not "what did you build" or "why".

For "explaining to others", the right structure is:

1. **What** — the shape/formula of the architecture
2. **Why** — the problem it solves (especially the cost or scaling angle)
3. **How** — the tech stack (versions, components) — keep this but as supporting detail

## The Formula: "1 X + N Y — [problem context]"

The cleanest one-liners for multi-tenant patterns follow this formula:

```
1 Gateway + N ListenerSet — 让 N 个业务团队在 1 个 GKE 集群内共享 1 个 HTTPS Gateway / 1 个 GCP ILB, 各团队在自己的 tenant namespace 独立部署 backend, 共享 *.team.appdev.aibang 通配子域名。
```

The formula works because:
- **"1 X + N Y"** is a memorable shape — the listener immediately understands the topology
- **" — "** pivots to the why
- **"N 业务团队在 1 个 GKE 集群内"** — the context
- **"共享 1 个 HTTPS Gateway / 1 个 GCP ILB"** — the what (and the cost story)
- **"各团队在自己的 tenant namespace 独立部署"** — the multi-tenancy guarantee
- **"共享 *.team.appdev.aibang 通配子域名"** — the domain pattern that makes it concrete

## When to use this pattern

- **At the top of any architecture runbook** — readers arriving from a search should understand the shape in 10 seconds
- **In a presentation / status update** — first slide / first paragraph
- **In a Slack / IM** — "what did you build?" deserves a one-liner, not a paragraph
- **In commit messages / PRs** — `feat: 1 Gateway + N ListenerSet on GKE for multi-tenant HTTPS ingress`

## When NOT to use

- For implementation details ("how do I add a new tenant?") — the runbook's §3-§5 sections answer that
- For tech selection ("why Istio over ASM?") — that's a separate decision doc
- For "how to debug X" — failure modes table

## Bilingual Pair (default for this user)

The user prefers bilingual documentation. For any cross-team / external-facing one-liner, write the Chinese + English pair:

```markdown
> **TL;DR (中文)**:
> **1 Gateway + N ListenerSet** — 让 N 个业务团队在 1 个 GKE 集群内共享 1 个 HTTPS Gateway / 1 个 GCP ILB, 各团队在自己的 tenant namespace 独立部署 backend, 共享 *.team.appdev.aibang 通配子域名。
>
> **TL;DR (English)**:
> **1 Gateway + N ListenerSets** — on a single GKE cluster, N business teams share one HTTPS Gateway and one GCP ILB; each team deploys its own backend in its own tenant namespace, all under the shared *.team.appdev.aibang wildcard subdomain.
```

The Chinese version is for in-team consumption (most of the user's team is Chinese). The English version is for cross-team / external readers (Google doc, public repo, vendor).

## Placement in the Doc

Add the one-liner as a **blockquote** at the very top, **before** the existing tech-stack line. The visual order is:

```
# Title

> TL;DR (bilingual one-liner)         ← NEW: what & why
> ...

> 目标集群 / 完成时间 / 架构 / FQDN / 状态    ← existing: tech stack + status
```

This way:
- Non-engineers see the TL;DR first, understand the shape, and stop reading if they want
- Engineers can scroll down to the tech-stack blockquote for version pins and test status

## When to Update the One-Liner

Update the one-liner when:
- The architecture shape changes (e.g., "1 Gateway + N ListenerSet" → "1 Gateway + 1 ListenerSet per region" after multi-region expansion)
- The "why" changes (e.g., new compliance requirement, new cost constraint)
- The audience shifts (e.g., from internal to customer-facing)

Do NOT update the one-liner for:
- Version bumps (Istio 1.30 → 1.31) — that's the tech-stack line
- New tenants added (newapi, app2) — the formula `1 + N` already covers it
- Internal refactors (DR mode change, image upgrade) — the formula is about topology, not implementation details

## Worked Examples from the Session

The user's runbook for k8s-gateway was the test case. The original line was:
> 架构: GKE + Istio 1.30 minimal (only istiod) + K8s Gateway API v1.5.1 + ListenerSet 多租户

The new TL;DR pair added at the top:
> TL;DR: 1 Gateway + N ListenerSet — 让 N 个业务团队在 1 个 GKE 集群内共享 1 个 HTTPS Gateway / 1 个 GCP ILB, 各团队在自己的 tenant namespace 独立部署 backend, 共享 *.team.appdev.aibang 通配子域名。
>
> TL;DR: 1 Gateway + N ListenerSets — on a single GKE cluster, N business teams share one HTTPS Gateway and one GCP ILB; each team deploys its own backend in its own tenant namespace, all under the shared *.team.appdev.aibang wildcard subdomain.

The original tech-stack line was kept (now a "supporting detail" for engineers), and the TL;DR became the "primary explanation" for non-engineers.

## Anti-Patterns to Avoid

❌ **Tech stack as headline**:
> "GKE + Istio 1.30 + K8s Gateway API v1.5.1 + ListenerSet 多租户"
> (No shape, no why — just components)

❌ **Vague benefit without shape**:
> "A scalable multi-tenant HTTPS ingress solution"
> (No components, no numbers, no specific topology)

❌ **Acronym soup**:
> "1 GW + N LS = N tenants share 1 ILB"
> (Too compressed for non-engineers, even worse for cross-team)

✅ **Formula + context + concrete numbers**:
> "1 Gateway + N ListenerSet — 让 N 个业务团队在 1 个 GKE 集群内共享 1 个 HTTPS Gateway / 1 个 GCP ILB"
> (Memorable formula + context + cost story)
