# Prompt Refiner v1.1

`prompt-refiner` converts a short description or a rough draft into a structured, safe prompt. It is a generator by default, not an automatic executor.

## When to use it

Use it for requests such as:

- “Polish this prompt for a GKE audit.”
- “Turn this incident note into a debugging prompt.”
- “Generate a reusable prompt to review Terraform changes.”

Do not invoke it for a direct task request unless the user asks to first create or improve a prompt.

## Modes

| Mode | Result |
| --- | --- |
| `generate` | A final reusable prompt only; default. |
| `plan` | An execution plan and risk notes, without changes. |
| `execute` | Runs an explicitly authorized task under the host agent’s normal safeguards. |

## Principles

- Ask only for blocking information; use visible placeholders for unknown identifiers.
- Do not invent project IDs, cluster names, locations, credentials, or permissions.
- Follow the user’s language; retain native command and configuration syntax.
- Preserve user-supplied constraints, especially read-only boundaries and output format.
- Self-check the generated prompt before returning it.

## Examples

See [examples/cluster-comparison.md](examples/cluster-comparison.md) for a GKE comparison prompt, [references/gcp-gke.md](references/gcp-gke.md) for GKE-specific guardrails, and `eval/` for regression cases and quality metrics.

## Maintenance

Each domain reference declares `last_verified`. Review it at least every six months, and prefer stable workflow rules over a brittle list of API fields.
