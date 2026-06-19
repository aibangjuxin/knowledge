# Shell Review — Reference Index

This directory contains the methodology documents that this SKILL.md distills.
The audit reports live in the **parent directory** (`../`) — they're full review
outputs that show the expected format.

## Documents in this directory (methodology)

| File | When to read | Purpose |
|---|---|---|
| [`methodology.md`](../methodology.md) | When you need the full rationale for any step in SKILL.md | Master 4-layer × 8-class framework with gotcha tables, blind spots, and decision tree. ~18k chars. Read once to internalize. |
| [`checklist.md`](../checklist.md) | As a fallback when the skill isn't available, or as a one-page printable reference | Tick-by-tick review flow, all four layers, copy-paste commands. ~6k chars. |
| [`tool-stack.md`](../tool-stack.md) | When picking which tools to install, or which combination fits the script's risk class | Per-tool install instructions + per-scenario combo matrix. ~9k chars. |

## Audit templates in the parent directory (`../`)

These are **real review reports produced by this skill**. Use them as the shape
reference for your own outputs.

| File | Scope | When to copy |
|---|---|---|
| [`../audit-public-mtls-global-ingress-scripts.md`](../audit-public-mtls-global-ingress-scripts.md) | 5 GCP scripts, 1,976 LOC | Original worked example; tone baseline |
| [`../audit-verify-pub-priv-ip-glm-ipv6.md`](../audit-verify-pub-priv-ip-glm-ipv6.md) | Single 830-LOC DNS script | **Newest template — preferred reference.** Shows L2 → L3 escalation pattern, adds Layer column, includes reproducibility section |

## How an agent should use these references

Load SKILL.md (the skill's main entrypoint). SKILL.md references this directory
for **deep reasoning** — when a finding needs justification beyond "this is a
gotcha", when an agent encounters a bug class not covered in the executive
summary, or when the user asks "why?" after a review.

For **format reference** (what the final output should look like), read at least
one audit template first. Match its severity ladder, headline-table columns,
finding density, and verdict format.

Don't re-read every reference on every invocation. Use them on demand:
- "Why is `cmd && ok || warn` wrong?" → methodology.md §3.1
- "What's the right shellcheck invocation?" → tool-stack.md § "Tool cheat sheet"
- "How should the output look?" → `../audit-verify-pub-priv-ip-glm-ipv6.md` (preferred) or
  `../audit-public-mtls-global-ingress-scripts.md` (older baseline)

## Maintenance

Methodology docs and audit templates are both source of truth. When you update
methodology.md or any doc in this directory, **update SKILL.md to match** — they
should stay consistent. The SKILL.md is the **distilled, executable form**;
methodology is the **reasoned form**; audits are the **demonstrated form**.
If they diverge, SKILL.md wins for runtime behavior; methodology wins for
"why"; audits win for "what the output should look like".