---
name: extract-requirements-target
description: Extract concise Requirements and Target from technical documents, project briefs, meeting notes, design drafts, RFCs, PRDs, or solution writeups. Use when Codex needs to quickly identify what the requester needs, what constraints or expectations exist, and what final goal the document is driving toward, especially when the source material is long, noisy, or mixed with background details.
---

# Extract Requirements Target

## Overview

Read the source material, separate signals from background, and produce a compact summary focused on two outputs only: `Requirements` and `Target`.
Preserve the user's intent, compress repetition, and avoid inventing missing requirements.

## Extraction Workflow

### 1. Identify the document type

- Detect whether the input is a technical plan, architecture note, requirement doc, meeting summary, product brief, or mixed working draft.
- Assume that key facts may appear in scattered sections, lists, tables, or informal notes.
- Ignore decorative language, status updates, and background explanation unless they change scope or intent.

### 2. Extract `Requirements`

- Extract what must be done, delivered, satisfied, supported, avoided, or constrained.
- Include explicit needs such as functional requirements, technical constraints, dependencies, success criteria, deadlines, compatibility expectations, compliance rules, or non-functional requirements.
- Merge duplicate statements into one concise line.
- Prefer concrete wording over generic restatements.
- Keep each requirement independently scannable.

### 3. Extract `Target`

- Infer the end-state the author wants to achieve.
- Express the target as the final business, technical, delivery, or decision objective.
- Distinguish the target from implementation detail:
  - `Requirement` answers "what is needed or constrained?"
  - `Target` answers "what outcome is this document trying to achieve?"
- Prefer one short paragraph or 1 to 3 tight bullets.

### 4. Resolve ambiguity carefully

- Mark items as inferred only when the source implies them but does not state them directly.
- Do not upgrade assumptions into facts.
- If the document contains multiple competing goals, separate:
  - primary target
  - secondary target
- If the source is too vague, say that the target is unclear and list the strongest likely interpretation.

## Compression Rules

- Reduce long paragraphs into short, information-dense statements.
- Remove examples, anecdotes, rationale, and history unless they materially affect the requirement or target.
- Avoid copying the user's prose when a shorter equivalent is clearer.
- Keep terminology from the source when it is domain-critical.
- Preserve quantities, versions, deadlines, environments, and named systems when present.

## Output Format

Use this structure by default:

```markdown
## Requirements
- ...
- ...

## Target
...
```

If the source is complex, add one optional section:

```markdown
## Notes
- Inferred: ...
- Missing detail: ...
```

## Extraction Heuristics

- Treat "need", "must", "should", "expect", "goal", "want", "deliver", "support", "avoid", and "success" as strong requirement signals.
- Treat "so that", "in order to", "最终", "目标", "希望", and "achieve" as strong target signals.
- When the document mixes problem statement and solution proposal, extract requirements from the problem and target from the intended outcome.
- When the document is highly technical, keep platform names, environment names, interfaces, and operational constraints.

## Quality Bar

- Make the result understandable without rereading the original document.
- Prefer completeness over oversimplification, but stop before turning the summary back into a full document.
- Keep the final output concise enough that a teammate can understand the ask in under one minute.

## Example Triggers

- "Extract the real requirements and target from this RFC."
- "Read this technical note and give me only Requirements and Target."
- "This document is too long. Summarize the需求和目标."
- "从这份方案里提炼需求和目标，不要展开解释。"
