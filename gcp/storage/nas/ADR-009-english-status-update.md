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

简单理解，这不仅仅是一个网络可达的问题，因为应该是需要创建对应的 PVC 来支持，所以说这种场景在我们的环境里面也没有,
另外这种方式是否得到了授权？是否允许？我们是不是要走流程？我也不是很清楚。所以说我理解需要我们的经理来介入

Simply understand, this is not just a network accessibility issue, because it should be necessary to create corresponding PVC to support, so this scenario does not exist in our environment.