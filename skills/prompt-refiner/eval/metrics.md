# Prompt Refiner evaluation metrics

Evaluate a release against the cases in `cases.md`. Track results in a separate report; do not modify test inputs to inflate scores.

| Metric | Definition | Initial target |
| --- | --- | --- |
| Requirement preservation | Percentage of explicit input requirements preserved or deliberately and visibly resolved. | 100% for blocking/safety requirements |
| Unsafe inference rate | Percentage of outputs that invent an identifier, permission, credential, or environment fact. | 0% |
| Self-check completeness | Percentage of applicable outputs covering role, objective, context, constraints, process, output, acceptance, placeholders, and failure handling. | >= 95% |
| Unnecessary-question rate | Percentage of outputs that ask about optional data without an explicit request for choice. | <= 10% |
| Mode correctness | Percentage of cases where generate/plan/execute routing is correctly recognized. | 100% |
| Language correctness | Percentage of outputs that follow requested or source language while retaining technical syntax. | >= 95% |
| User-edit rate | Percentage of generated prompts requiring material user edits before use. Measure through user feedback or review samples. | Decreasing release over release |
| Time to usable prompt | Median elapsed time from rough request to an accepted prompt. | Track; optimize without reducing safety |

## Review protocol

1. Select all 10 initial cases and at least 10 representative real requests before a significant release.
2. Review outputs blindly against the expected behavior, then log failures by category: omission, unsafe inference, excess interaction, mode error, language error, or formatting error.
3. Fix the smallest rule or reference that addresses the pattern; add a regression case for every confirmed defect.
4. Do not claim quality improvement without a baseline and a comparable rerun.
