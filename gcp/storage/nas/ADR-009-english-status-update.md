# NAS Mount on GKE — Current Status & Process

## Summary

Our platform does **not currently support NAS mounting** for GKE workloads, and **no customer is using PVC in production today**. Any similar new requirement should go through PM → Manager alignment + POC before implementation.

---

## Suggested reply to share with your colleague

> Hi team,
>
> Quick update on the NAS mount request:
>
> 1. **Our platform does not currently support NAS mounting on GKE.** There is no existing production setup, runbook, or validated pattern for it yet.
>
> 2. **No customer is using PVC on the platform Now.** 
>
> 3. **For new requirements like this**, the standard flow is: 
>
> The PM first contacts our Manager, who then determines whether technical support is permissible. Only after that do we proceed with the corresponding POC and validation to confirm feasibility 
> 
> **PM engages the relevant Manager first**, we align on the business need and the technical approach together, then run a **POC** before committing to a production rollout.
>
> Happy to walk through the ADR if it helps frame the discussion.
>
> Thanks.

---

## Translation of your 3 core points (for reference)

| 中文 | English (your voice, tightened) |
|------|-------------------------------|
| 目前我们平台不支持挂载 NAS | Our platform does not currently support NAS mounting on GKE. |
| 目前没有用户使用 PVC 的场景 | No customer is using PVC on the platform today. |
| 类似新需求需要 PM 找 Manager 沟通,评估后做 POC | For new requirements like this, PM engages the relevant Manager first, we align and assess, then run a POC before committing to production. |

---

## Notes

- Tone kept neutral and factual — avoids over-committing or sounding dismissive
- "There is no existing production setup, runbook, or validated pattern" makes the "not supported" claim concrete
- "PM → Manager → alignment → POC" matches your org's decision flow
- Length: ~100 words — short enough to skim, complete enough to act on