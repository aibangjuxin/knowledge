# Prompt Refiner regression cases

Run these cases after changing `SKILL.md` or a relevant domain reference. Assess results against `metrics.md`.

| ID | Input | Expected behavior |
| --- | --- | --- |
| PR-01 | “Polish: compare two GKE clusters.” | Generates a concise Chinese prompt, uses placeholders for both environments, defaults to read-only, and does not ask optional preference questions. |
| PR-02 | “直接对比 prod-a 和 prod-b 两个 GKE 集群。” | Does not invoke the refiner solely from a direct execution request; routes to the host agent’s task-execution flow. |
| PR-03 | “Generate an English prompt to review Terraform changes for a production VPC.” | Outputs English, declares review-only scope, has acceptance criteria and a no-invented-IDs policy. |
| PR-04 | “润色这个 prompt，只增加 Cloud NAT 和 DNS 审计，其它不变：{{PROMPT}}” | Applies a minimal incremental change and preserves existing scope and format. |
| PR-05 | “Make a prompt to fix cluster autoscaling now.” | Uses generate mode unless execution is explicitly requested; distinguishes plan, execution, and production approval requirements. |
| PR-06 | “给我一个 GKE 安全审计 prompt，项目是 my-prod。” | Retains `my-prod`; leaves unknown cluster, location, and credentials as placeholders; includes access-failure handling. |
| PR-07 | “把这个 incident note 变成排障 prompt。” | Includes evidence collection, hypotheses, validation, and rollback/mitigation considerations without pretending to know the cause. |
| PR-08 | “Help me choose output format and audit depth for a GKE comparison prompt.” | May ask preference questions because the user explicitly requests help choosing options. |
| PR-09 | “Make this prompt shorter.” | Preserves objective, constraints, and output contract while removing nonessential detail. |
| PR-10 | “对比 V1 与 V2 提示词。” | Produces a meaningful concise diff and identifies material changes in scope, safety, or expected output. |
