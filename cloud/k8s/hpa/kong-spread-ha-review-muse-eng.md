# Kong PRD High-Availability Configuration Review: Spread Results (Muse Revision)

> Review target: Kong gateway Deployment (namespace `clienta-int-kdp`, instance `clienta-int-kdp-prd`)
> Sources: `kong-spread-ha-review.md` (original document) + `kong-spread-ha-review-claude.md` (Claude review)
> + `pdb-multi-zone-spread-ha.md` (general methodology)
> This document presents the conclusions recomputed by Muse on top of the three documents above, correcting two errors in §5 of the original document.
> Date: 2026-11-19

> **Conclusion first (final configuration, see §12)**
>
> **This is the lowest-cost, most stable-bottom-line combination: at low load, one Pod per Zone, and at any moment (including during maintenance) at least 2 Pods are available.**
>
> Configuration: `HPA minReplicas: 3 / maxReplicas: 5` + `PDB maxUnavailable: 1`; all other settings (`required` hostname anti-affinity, `topologySpread maxSkew: 1 + DoNotSchedule + Honor/Honor`, `RollingUpdate maxSurge: 1 / maxUnavailable: 0`) stay unchanged.
> Numbers: with 3 replicas at low load the spread is `1/1/1`, the voluntary-disruption floor is 2 available Pods, a single Zone failure leaves 2 (-33%); with 4 replicas `2/1/1` and with 5 replicas `2/2/1`, with floors of 3 and 4 respectively. The cost is one extra Pod at low load compared to before, and upgrades still only touch one Pod at a time.

---

## 0. The YAML Under Review (core configuration)

```yaml
# ── Deployment ────────────────────────────────────────────────────────
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1            # At most 1 extra Pod started during an update
      maxUnavailable: 0      # Never proactively reduce available replicas during an update (start new first, then delete old)
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app.kubernetes.io/component: app
                  app.kubernetes.io/instance: clienta-int-kdp-prd
                  app.kubernetes.io/name: kong
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          nodeAffinityPolicy: Honor
          nodeTaintsPolicy: Honor
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: app
              app.kubernetes.io/instance: clienta-int-kdp-prd
              app.kubernetes.io/name: kong
---
# ── HorizontalPodAutoscaler ───────────────────────────────────────────
spec:
  minReplicas: 2
  maxReplicas: 5
---
# ── PodDisruptionBudget ──────────────────────────────────────────────
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: clienta-int-kdp-prd-kong
  namespace: clienta-int-kdp
spec:
  maxUnavailable: 1    # Max unavailable: during voluntary disruptions at most 1 Pod may be unavailable at a time; smaller is not always better, see §2.5
  selector:
    matchLabels:
      app.kubernetes.io/component: app
      app.kubernetes.io/instance: clienta-int-kdp-prd
      app.kubernetes.io/name: kong
```

**Premise:** the cluster has 3 available Zones (a/b/c), and there are enough Nodes (steady-state Node count ≥ replica count; during rolling updates ≥ replica count + 1).

---

## 1. Spread Results This Configuration Can Achieve (core table)

| Replicas | Steady-state spread a/b/c | Per Pod | Left after a single Zone failure | Capacity change | Left after a single Node failure |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **2** (HPA min) | **1/1/0** | 1 Node each | **1** left | **-50%** | 1 left |
| **3** | **1/1/1** | 1 Node each | **2** left | **-33%** | 2 left |
| **4** | **2/1/1** | 1 Node each | **2~3** left, worst case 2 left (lost the Zone that had 2) | -25% ~ -50% | 3 left |
| **5** (HPA max) | **2/2/1** | 1 Node each | **3~4** left, worst case 3 left | -20% ~ -40% | 4 left |
| **During rolling update** | replicas + 1 | 1 Node each | Old Pods stay online throughout | 0 | 0 |

Transient spread during a rolling update (`maxSurge: 1`):

| Replicas | Before update | Where the surge Pod lands | Transient spread |
| :---: | :---: | :---: | :---: |
| 2 | `1/1/0` | **Only the empty zone-c** (going to a/b would make skew 2 and be rejected by `DoNotSchedule`) | `1/1/1` |
| 3 | `1/1/1` | Any Zone (skew still ≤ 1) | `2/1/1` |
| 4 | `2/1/1` | The Zone that currently has the fewest | `2/2/1` |
| 5 | `2/2/1` | The Zone that currently has the fewest | `2/2/2`, requires 6 Nodes |

Degradation when there are not enough Zones:

| Available Zones | 2 replicas | 3 replicas | 4 replicas | 5 replicas |
| :---: | :---: | :---: | :---: | :---: |
| 2 Zones | `1/1` | `2/1` | `2/2` | `3/2` |
| 1 Zone | All land in the same Zone, skew=0, **the constraint neither errors nor warns**, silently losing Zone redundancy | Same | Same | Same |

---

## 2. What Each YAML Setting Actually Does

### 2.1 `podAntiAffinity: required + hostname` — Node isolation, hard guarantee

Once a Pod with matching labels sits on a Node, that Node can no longer host another Kong Pod. If the requirement cannot be met, the Pod stays Pending — there is no fallback. This is the strongest setting in this configuration.

### 2.2 `topologySpreadConstraints: maxSkew: 1 + zone + DoNotSchedule` — Zone balance, hard guarantee

This is no longer the "best effort" wording in the original requirement — the strength already exceeds "best effort". Whenever the scheduler can satisfy it, the Pod count difference between any two Zones is ≤ 1. When replicas ≤ number of Zones, each Zone gets at most 1 Pod; when replicas > number of Zones, you still never end up with 3 Pods in one Zone while another is empty.

### 2.3 `nodeAffinityPolicy: Honor / nodeTaintsPolicy: Honor` — replacement Pods can be scheduled after a Zone failure

`nodeTaintsPolicy: Honor` excludes tainted Nodes that the Pod does not tolerate from the skew calculation, even when the Pod declares no tolerations. During a Zone failure the Nodes get the `unreachable` taint; with Honor that Zone is removed from the calculation so the replacement Pod can land in a surviving Zone. With the default `Ignore`, the failed Zone still counts as having 0 Pods and the replacement Pod may end up Pending.

### 2.4 `RollingUpdate: maxSurge: 1 / maxUnavailable: 0` — this is the gate for zero-downtime releases, not the PDB

New Pods start first and old Pods are deleted afterwards, so old Pods stay online throughout. The cost is: the surge Pod can only land in the Zone that currently has the fewest Pods; if that Zone has no schedulable Node, the surge Pod stays Pending, the rollout stalls, and the old version keeps serving — no downtime, but the new version cannot roll out.

### 2.5 `PDB: maxUnavailable: 1` — governs voluntary disruptions only, not failures or rollouts

It only intercepts the Eviction API, i.e. `kubectl drain`, GKE node upgrades, and Cluster Autoscaler scale-down. Pods crashing on their own and Zone failures are not covered by the PDB; Deployment rolling updates go through delete and do not go through the PDB either. So with 2 replicas, during maintenance the PDB allows eviction down to **1** remaining Pod.

#### Is `maxUnavailable` smaller-is-better? — No, looking at only half the picture is wrong

The first half of your understanding is correct: `maxUnavailable` literally means **the upper bound on the number of Pods allowed to be unavailable simultaneously during a voluntary disruption**. The smaller the value, the fewer Pods may be down at once, and the higher the availability floor:

```
Minimum available = replicas - maxUnavailable
```

| `maxUnavailable` | Min available with 2 replicas | Min available with 3 replicas | Min available with 5 replicas |
| :---: | :---: | :---: | :---: |
| 0 | 2 | 3 | 5 |
| **1 (current configuration)** | **1** | **2** | **4** |
| 2 | 0 | 1 | 3 |

But "smaller is better" holds only along the **availability** dimension; switch to the **operability** dimension and it flips:

- **`maxUnavailable: 0` looks safest but is practically unusable.** It means not a single eviction is allowed, `disruptionsAllowed` is always 0, `kubectl drain` is permanently blocked by the PDB, and GKE node upgrades and node scale-down all hang — you have to manually delete the PDB before upgrading, which is effectively turning the protection off.
- **The smaller the value, the slower and more blockage-prone upgrades / drains become.** `maxUnavailable: 1` can only advance one Node at a time; if one Pod is already NotReady (not yet recovered), `disruptionsAllowed` becomes 0 and the next eviction is blocked outright, stretching out the upgrade window.
- **The larger the value, the faster the upgrade but the lower the floor.** `maxUnavailable: 2` allows 2 Pods to move at once, making upgrades faster and less likely to stall, but the floor drops by another 1 (see §10).

So the correct framing is not "smaller is better" but: **take the smallest value that still preserves the floor, under the premise that maintenance can actually proceed.** For the 2~5 replica range, `1` is usually that balance point — maintenance proceeds one at a time while the floor is `replicas - 1`. If you raise the replica count to 3~4 and pair it with `maxUnavailable: 1`, the floor becomes 2~3, which is exactly the combination recommended in §7 and §11.

Be careful not to confuse this with the Deployment's `maxUnavailable: 0` (§2.4): that 0 is correct, because a rolling update starts a surge Pod first and then deletes the old Pod, so it never needs the Eviction API and a 0 will not block the rollout; a PDB 0 does block drain — completely different mechanisms.

### 2.6 `HPA: 2~5` — the lower and upper bounds on replica count

2 is the floor, 5 is the ceiling. All the 2~5 rows in §1 are determined by it.

---

## 3. Two Errors in the Original Document (Corrected)

| # | Original document's claim | Verdict | Correct statement |
| :--- | :--- | :---: | :--- |
| 1 | §5: with 2 replicas, "on a single Zone failure, both Pods are in that Zone and both die, causing downtime" | ❌ Wrong | In steady state 2 replicas are `1/1/0`; a single Zone failure only drops 1, leaving 1 serving — capacity is halved, but there is no downtime. Total loss requires scale-down drift that happens to place both Pods in the same Zone |
| 2 | "With 3 replicas a single Zone failure does not reduce capacity" | ⚠️ Exaggerated | 3 becomes 2, capacity drops by 1/3. The accurate statement is "there are still 2 Pods, and the HPA will backfill capacity in the surviving Zones" |
| 3 | "Don't add `minDomains`, because it gives up the constraint when Zones are insufficient and degenerates into crowding the same Zone" | ❌ Right conclusion, wrong reason | When the number of available Zones is insufficient, `minDomains` treats the global minimum as 0, making the constraint **stricter** (extra Pods stay Pending) rather than abandoning it. With ≥ 3 Zones it has no effect, so there is no reason to add it |

---

## 4. Three Effects This YAML Cannot Achieve

| Effect you might want | Actual effect | Verdict |
| :--- | :--- | :--- |
| Pods on different Nodes | `required` + hostname, hard guarantee | ✅ Achieved |
| Pods spread across Zones as evenly as possible | `DoNotSchedule` + `maxSkew: 1`, hard guarantee at scheduling time | ✅ Achieved, stronger than the requirement |
| Keep at least 2 replicas | HPA min=2, but the PDB floor is 1 | ❌ Does not match the stated goal |
| No capacity loss on a single Zone failure | 2 replicas lose half, 3 replicas lose 1/3 | ⚠️ Needs a decision |

To truly get "at least 2 available at any time + one Pod per Zone", you need **`minReplicas: 3` + PDB `minAvailable: 2`**. But even then, "capacity never drops" is impossible — losing a Zone means losing that Zone's Pods, and the only remedy is the HPA backfilling capacity in the surviving Zones afterwards.

---

## 5. Silent Risk: Scale-Down Drift

topologySpread only takes effect **at scheduling time** and does not actively rebalance. When the HPA scales from 5 down to 2 (from `2/2/1`), the ReplicaSet deletes Pods without looking at Zones, so in theory the result could be `2/0/0` — both Pods in the same Zone, and a failure of that Zone wipes everything out.

Mitigations:

| Mitigation | Explanation |
| :--- | :--- |
| Deploy Descheduler | Enable `RemovePodsViolatingTopologySpreadConstraint` to periodically reschedule violating Pods |
| `minReplicas: 3` | Steady state is one Pod per Zone; after scale-down the worst case is only `1/1/0`-type drift |
| Alerting | Alert when `max(zoneCount) - min(zoneCount) > 1` |

---

## 6. Do Not Add `minDomains`

With 3 Zones it has no effect; when Zones are insufficient it does not "give up the constraint" — it computes skew by treating the global minimum as 0, which makes the constraint **stricter**, so extra Pods stay Pending. Official Kubernetes semantics: when the number of available domains is less than `minDomains`, the global minimum is computed as 0; when it is greater than or equal, there is no impact. So adding `minDomains: 3` would instead block replacement Pods during Zone recovery.

---

## 7. Recommendations

| Priority | Action | Rationale |
| :---: | :--- | :--- |
| P0 | Keep `DoNotSchedule`, `required` hostname, `Honor/Honor`, and do not add `minDomains` | The current topology design is correct, and `Honor` genuinely helps with Zone failure recovery |
| P0 | Add alerts: Zone distribution imbalance, available Zone count < 3, Kong Pods Pending | Losing Zone redundancy is silent |
| P1 | `minReplicas: 2 → 3`, change PDB to `minAvailable: 2` | Aligns with "at least 2 available" and "one per Zone" |
| P1 | Deploy Descheduler or periodically inspect the Zone distribution | Resolves scale-down drift |

---

## 8. Verification Commands

```bash
NS=clienta-int-kdp
SEL='app.kubernetes.io/component=app,app.kubernetes.io/instance=clienta-int-kdp-prd,app.kubernetes.io/name=kong'

# Node of each Pod and its Zone (first confirm the Node's zone labels)
kubectl get pod -n $NS -l "$SEL" -o wide
kubectl get node -L topology.kubernetes.io/zone

# Count Pods per Zone (look up the Zone from each Node)
for n in $(kubectl get pod -n $NS -l "$SEL" -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node $n -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}'
done | sort | uniq -c

# PDB status
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
```

> Note: Pods do not carry the `topology.kubernetes.io/zone` label themselves; reading Pod labels directly returns empty, so you have to look up the Zone through the Node as shown above.

---

## 9. One-Sentence Summary

> In steady state, 2 replicas are `1/1/0`, 3 replicas are `1/1/1`, 4 replicas are `2/1/1`, 5 replicas are `2/2/1`; skew is always ≤ 1, each Pod has its own Node, and neither a single Node nor a single Zone failure causes an interruption — capacity does drop though. The real weaknesses are not in the topology constraints but in **the PDB floor being only 1, possible distribution drift after scale-down, and whether there are enough Nodes for rolling updates.**

---

## Related Documents

- `kong-spread-ha-review.md` — review of the original document
- `kong-spread-ha-review-claude.md` — Claude review (corrected the errors in §5 of the original document)
- `pdb-multi-zone-spread-ha.md` — general methodology: choosing Zone spread constraints, `required` vs `topologySpread`, `minDomains` semantics

---

## 10. Addendum (2026-11-19): Impact of Changing PDB `maxUnavailable: 1 → 2`

> Only this one line changes: `spec.maxUnavailable: 1` becomes `2`; all other settings (HPA 2~5, RollingUpdate `maxSurge: 1 / maxUnavailable: 0`, anti-affinity, topologySpread) stay unchanged.

### 10.1 One-Sentence Conclusion

**The availability floor drops by one Pod overall, in exchange for faster and less PDB-blocked node upgrades / drains.**
With the HPA floor at 2 replicas this trade is not worth it: during maintenance the deployment could drop to **0 available Pods — full downtime**.

### 10.2 Numeric Comparison by Replica Count

The PDB floor formula is: `minimum available = replicas - maxUnavailable` (`disruptionsAllowed` is the number of evictions allowed by that difference).

| Replicas | Min available with `maxUnavailable: 1` | Min available with `maxUnavailable: 2` | Change |
| :---: | :---: | :---: | :---: |
| **2** (HPA min) | **1** | **0** | -1, **possible total loss** |
| **3** | **2** | **1** | -1, becomes a single point of failure |
| **4** | **3** | **2** | -1, still keeps 2 |
| **5** (HPA max) | **4** | **3** | -1, still keeps 3 |

### 10.3 Impact on Zone Distribution: Zone Redundancy Is Lost During the Maintenance Window

The PDB only looks at the global count of available Pods and is **not Zone-aware**. With 2 evictions allowed at once, and since drain order follows Nodes rather than Zones, the distribution during maintenance could become:

| Replicas | Steady-state spread | With `maxUnavailable: 2`, could become during maintenance |
| :---: | :---: | :---: |
| 2 | `1/1/0` | `0/0/0` — both Pods evicted, **full downtime** |
| 3 | `1/1/1` | `1/0/0` — only 1 Zone and 1 Pod left, a single point of failure; another failure in that Zone means downtime |
| 4 | `2/1/1` | Worst case 2 Pods left, e.g. `0/1/1` or `1/0/1`, still 2 Zones |
| 5 | `2/2/1` | Worst case 3 Pods left, e.g. `1/1/1` or `2/1/0` |

Note: the above is the **floor (guaranteed value)**, not what happens every time. If the drain proceeds strictly one Node at a time and only evicts the next Pod after the replacement becomes Ready, the actual available count may stay above the floor. But once the PDB is changed to 2, **the floor itself permits** the second eviction to happen before the first replacement Pod is Ready, so this window genuinely exists and cannot be covered by "it generally won't happen at the same time".

### 10.4 The Benefits: Faster and Less-Blocked Upgrades / Drains

| Aspect | `maxUnavailable: 1` | `maxUnavailable: 2` |
| :--- | :--- | :--- |
| GKE node upgrade / `kubectl drain` parallelism | Only 1 Pod at a time, advancing Node by Node | 2 Pods at a time, shortening the upgrade window |
| When 1 Pod is already NotReady | `disruptionsAllowed = 0`, drain is blocked by the PDB | 1 more eviction is allowed, upgrades stall less often |
| Cluster Autoscaler scaling down Nodes | Scales down 1 related Pod at a time | Can scale down 2 in parallel |

### 10.5 Three Things That Are Not Affected (Common Misunderstandings)

| Item | Affected? | Why |
| :--- | :---: | :--- |
| Deployment rolling update speed / zero downtime | ❌ No | Rolling updates go through delete and do not use the Eviction API, so the PDB does not block them; the gate is the Deployment's own `maxUnavailable: 0`, not the PDB |
| Pods crashing on their own, involuntary Node / Zone failures | ❌ No | The PDB only governs voluntary disruptions (drain / upgrade / proactive eviction); it does not participate in involuntary failures |
| Steady-state spread (`1/1/0`, `1/1/1`, etc.) | ❌ No | The PDB does not participate in scheduling; the spread is determined by anti-affinity + topologySpread. Changing the PDB neither improves nor worsens the steady-state spread |
| HPA scale-down | ❌ No | HPA scale-down deletes Pods directly through the Deployment and likewise does not use the Eviction API |

### 10.6 Recommendations

| Scenario | Recommendation |
| :--- | :--- |
| Current state (HPA min=2) | **Do not change it to 2.** The floor becomes 0, which amounts to deliberately giving up high availability in the maintenance window |
| Want faster node upgrades while keeping a floor ≥ 2 | First raise `minReplicas` to **4**, then change `maxUnavailable: 2`, so the floor is still 2; or keep `maxUnavailable: 1` and use GKE surge upgrades so the replacement Pod comes up first |
| Replica count stays in the 4~5 range | Changing it to 2 is relatively cheap (floor 2~3) and acceptable, but you still have to accept that Zone redundancy during the maintenance window may drop to 2 Zones |
| Do not use `minAvailable: 2` as an "equivalent substitute" | With 3 replicas it is equivalent to `maxUnavailable: 1`, but with 5 replicas it allows 3 simultaneous evictions — looser than `maxUnavailable: 2`. Recompute the floor against the maximum replica count before using it |

### 10.7 How to Verify After the Change

```bash
NS=clienta-int-kdp

# PDB status: check whether Allowed disruptions becomes 2
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
kubectl describe pdb -n $NS clienta-int-kdp-prd-kong | grep -E 'Allowed disruptions|Current|Desired'

# Dry run before an upgrade / drain (changes nothing)
kubectl drain <node> --dry-run=server --ignore-daemonsets
```

---

## 11. Addendum (2026-11-19): Can `HPA min=3` + PDB `maxUnavailable: 2` Perfectly Solve Everything?

> Proposal: raise `HPA minReplicas: 2 → 3` while also changing `PDB maxUnavailable: 1 → 2`, with everything else unchanged.

### 11.1 One-Sentence Conclusion

**No, it does not solve everything. This combination only solves half the problem, and it weakens the other half itself.**

It does improve the steady-state spread (3 replicas `1/1/1`, one per Zone), but in the low-load steady state where it spends most of its time (exactly 3 replicas), the voluntary-disruption floor is still **1 Pod** — the same as the current `min=2 + maxUnavailable: 1`. It is still a single point of failure during the maintenance window.

### 11.2 Do the Math First: The Floor Formula Does Not Change

Minimum available = replicas - `maxUnavailable`. `min=3` merely raises the starting replica count by 1, while `maxUnavailable=2` lowers the floor by 1 — the two cancel out exactly.

| Combination | Min available at 3 replicas | At 4 replicas | At 5 replicas | Steady-state spread (low load) |
| :--- | :---: | :---: | :---: | :---: |
| Current: `min=2` + `maxUnavailable: 1` | 2 (when replicas=3) / **1 (when replicas=2)** | 3 | 4 | `1/1/0` |
| Proposal: `min=3` + `maxUnavailable: 2` | **1** | 2 | 3 | `1/1/1` |
| Alternative: `min=3` + `maxUnavailable: 1` | **2** | 3 | 4 | `1/1/1` |
| Alternative: `min=4` + `maxUnavailable: 2` | — (replicas ≥ 4) | **2** | 3 | `2/1/1` |

How to read the table:

- The proposal's floor at 3 replicas is **1**, not 2. To have "at least 2 available at any moment" you need `replicas - maxUnavailable ≥ 2`, i.e. with `maxUnavailable: 2` you need at least **4** replicas.
- The proposal's only advantage is the steady-state spread: at low load it goes from `1/1/0` to `1/1/1`, so a single Zone failure leaves 2 Pods (-33%) instead of 1 (-50%). This benefit comes from `min=3`, not from `maxUnavailable: 2`.
- With the same `min=3`, pairing with `maxUnavailable: 1` gives a floor of 2, while `maxUnavailable: 2` gives a floor of 1. **`maxUnavailable: 2` brings no availability benefit here — what it brings is faster drain / upgrade speed, at the cost of a lower floor.**

### 11.3 What Happens During the Maintenance Window

The PDB only looks at the global count of available Pods and is not Zone-aware. From a `1/1/1` spread, with 2 evictions allowed at once and drain proceeding in Node order, the result could be:

| Scenario | Spread change | Consequence |
| :--- | :---: | :---: |
| Evicting 2 Pods | `1/1/1` → `1/0/0` | Only 1 Zone and 1 Pod left, a single point of failure; another failure in that Zone means downtime |
| Evicting 1 Pod (as with `maxUnavailable: 1`) | `1/1/1` → `1/1/0` | 2 Zones and 2 Pods left, Zone redundancy preserved |

So the proposed combination is: **in normal operation (steady state) Zone redundancy is full, but as soon as the maintenance window opens, Zone redundancy may drop to a single Zone.** And the maintenance window is precisely when node upgrades and drains are most frequent.

### 11.4 Even `min=4 + maxUnavailable: 2` Is Not "Perfect"

`min=4 + maxUnavailable: 2` does achieve both "floor ≥ 2" and "2 evictions at once", and it is the cheapest combination for the goal of "fast and still keep 2". But it still cannot solve the following:

| Problem | Why it cannot be solved |
| :--- | :--- |
| Capacity drop on a single Zone failure | With 4 replicas `2/1/1`, losing the Zone that has 2 Pods leaves 2 (-50%); the same holds for any finite replica count — losing a Zone loses that Zone's Pods, and the HPA can only backfill afterwards |
| Involuntary failures (Pod crash, Node / Zone failure) | The PDB only governs voluntary disruptions; it does not participate in involuntary failures |
| Scale-down drift | topologySpread only takes effect at scheduling time; HPA scale-down deletes Pods without looking at Zones, so the spread may drift (see §5) |
| Rolling update stalls | The surge Pod can only go to the Zone that currently has the fewest; if that Zone has no Node the surge Pod stays Pending, regardless of the PDB setting |
| Silently losing redundancy when only 1~2 Zones are available | The constraint neither errors nor warns; only monitoring can detect it |

"Perfect" simply does not exist mathematically: no capacity loss on a single Zone failure would require infinite replicas; no loss at any moment would require zero-downtime maintenance. Both are impossible. What you can do is **write the trade-off between floor, capacity loss, upgrade speed and cost clearly**.

### 11.5 Trade-off Table for the Four Combinations

| Combination | Low-load steady-state spread | Voluntary-disruption floor (low load) | Left after a single Zone failure | drain / upgrade speed | Cost (Pods at low load) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Current: `min=2` + `maxU: 1` | `1/1/0` | 1 | 1 (-50%) | Slow (1 at a time) | 2 |
| Proposal: `min=3` + `maxU: 2` | `1/1/1` | **1** | 2 (-33%) | Fast (2 at a time) | 3 |
| **Recommended: `min=3` + `maxU: 1`** | `1/1/1` | **2** | 2 (-33%) | Slow (1 at a time) | 3 |
| Fast and still keep 2: `min=4` + `maxU: 2` | `2/1/1` | **2** | Worst case 2 (-50%) | Fast (2 at a time) | 4 |

### 11.6 Recommendations

| Your priority | Which combination to pick |
| :--- | :---: |
| **High availability first** (you care most about "at least 2 available at any moment") | **`min=3` + `maxUnavailable: 1`**. This is the lowest-cost, most stable-bottom-line combination, consistent with the P1 recommendation in §7 |
| **Upgrade speed also matters, and you want to keep 2** | **`min=4` + `maxUnavailable: 2`**. One extra Pod buys double drain parallelism while keeping the floor at 2 |
| **Upgrade speed first, willing to accept a single point of failure during maintenance** | The proposal's `min=3` + `maxUnavailable: 2` is acceptable, but write it down explicitly: during the maintenance window only 1 Pod and 1 Zone are allowed to remain, and alerts must be in place |
| **Do not choose** | `min=3` + `maxUnavailable: 2` while believing it "perfectly solves all problems" — at 3 replicas its floor is the same as the current setup, both are 1 |

---

## 12. Summary (2026-11-19): Final Configuration `HPA min=3 / max=5` + PDB `maxUnavailable: 1`

> The final, signed-off configuration (only two changes, everything else unchanged):
>
> ```yaml
> # ── HorizontalPodAutoscaler ───────────────────────────────────────────
> spec:
>   minReplicas: 3
>   maxReplicas: 5
> ---
> # ── PodDisruptionBudget ──────────────────────────────────────────────
> spec:
>   maxUnavailable: 1
> ```
>
> All other settings remain as they were: `podAntiAffinity: required + hostname`, `topologySpreadConstraints: maxSkew: 1 + zone + DoNotSchedule + Honor/Honor`, `RollingUpdate: maxSurge: 1 / maxUnavailable: 0`.

### 12.1 One-Sentence Conclusion

**This is the lowest-cost, most stable-bottom-line combination: at low load, one Pod per Zone, and at any moment (including during maintenance) at least 2 Pods are available.**

### 12.2 Master Numbers: What This Configuration Achieves

| Replicas | Steady-state spread a/b/c | Min available during voluntary disruptions | Left after a single Zone failure | Left after a single Node failure | Transient spread during rolling update |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **3** (HPA min, the most common state) | **1/1/1** | **2** | **2** (-33%) | 2 | `2/1/1` |
| **4** | `2/1/1` | `3` | `2~3` (worst case -50%) | 3 | `2/2/1` |
| **5** (HPA max) | `2/2/1` | `4` | `3~4` (worst case -40%) | 4 | `2/2/2`, needs 6 Nodes |

Floor formula: minimum available = replicas - `maxUnavailable` = replicas - 1, so with this configuration the **floor is always ≥ 2**.

### 12.3 Comparison with the Original Configuration (`min=2` + `maxUnavailable: 1`)

| Dimension | Before: `min=2` + `maxU: 1` | Now: `min=3` + `maxU: 1` | Change |
| :--- | :---: | :---: | :---: |
| Low-load steady-state spread | `1/1/0`, the 3rd Zone sits empty | `1/1/1`, one Pod per Zone | ✅ Complete Zone disaster recovery |
| Min available during voluntary disruptions | 1 | **2** | ✅ No longer a single point of failure |
| Left after a single Zone failure | 1 (-50%) | **2** (-33%) | ✅ Smaller capacity loss |
| Zone redundancy during maintenance | Evicting 1 → only 1 Zone left | Evicting 1 → `1/1/0`, still 2 Zones serving | ✅ Zone redundancy preserved during maintenance |
| Upgrade / drain speed | 1 at a time | 1 at a time | — Unchanged, still one at a time |
| Low-load cost | 2 Pods | 3 Pods | +1 Pod |

### 12.4 What This Configuration Solves and What It Does Not

**Solved:**

- ✅ "Keep at least 2 replicas" — this now also holds under PDB semantics, with at least 2 available at any moment, no longer the mismatched situation where the floor was only 1
- ✅ "One Pod per Zone" — the low-load steady state is `1/1/1`, and a single Zone failure still leaves 2 Pods
- ✅ Zone redundancy during maintenance — only 1 eviction at a time, `1/1/1` becomes `1/1/0`, so 2 Zones are still serving
- ✅ The impact of scale-down drift is greatly reduced — when the HPA scales from 5 down to 3, even if Pod deletion ignores Zones, the remaining 3 Pods cannot all end up in one Zone (at most 2 per Zone), so they span at least 2 Zones

**Not solved (still to be accepted or handled separately):**

- ⚠️ Capacity still drops on a single Zone failure — 1/3 with 3 replicas, up to half in the worst case with 4; "capacity never drops" is impossible at any finite replica count and can only be mitigated by the HPA backfilling capacity in the surviving Zones afterwards
- ⚠️ Upgrades / drains are still 1 Pod at a time, no faster — this is the cost of `maxUnavailable: 1`, which buys a higher floor; if upgrade speed becomes the bottleneck later, consider `min=4` + `maxUnavailable: 2` (see §11.5)
- ⚠️ The PDB does not participate in involuntary failures (Pod crashes, Node / Zone failures); those still rely on the topology spread itself as the safety net
- ⚠️ When only 1~2 Zones are available, the constraint neither errors nor warns, so monitoring is still required (see the degradation table at the end of §1)

### 12.5 Verification After Rollout

```bash
NS=clienta-int-kdp
SEL='app.kubernetes.io/component=app,app.kubernetes.io/instance=clienta-int-kdp-prd,app.kubernetes.io/name=kong'

# 1. The HPA floor is now 3
kubectl get hpa -n $NS

# 2. The steady-state spread should be 1/1/1 (at low load)
kubectl get pod -n $NS -l "$SEL" -o wide

# 3. PDB: Allowed disruptions should be 1, min available 2
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
kubectl describe pdb -n $NS clienta-int-kdp-prd-kong | grep -E 'Allowed disruptions|Current|Desired'

# 4. Node count: peak rolling update needs 6 schedulable Nodes
kubectl get node --no-headers | wc -l
```
