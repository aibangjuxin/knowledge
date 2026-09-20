# ELI5 Worked Examples

Real ELI5 files produced for Lex, kept here as structural templates.
When a new /eli5 request comes in, pick the example whose topic shape
matches and copy its panel order, not its wording.

## File index

| File | Topic class | Notes |
|------|-------------|-------|
| `psc-eli5.html` (in `~/git/knowledge/gcp/psa-psc/`) | Multi-party system with forward + reverse + ownership | Canonical example of all 6 panels in use |

## Why PSC is the canonical example

PSC has every ingredient the skill is designed to surface:

1. **Two independent actors** (producer VPC, consumer VPC) — fits the
   "trigger" panel naturally.
2. **A clear mechanism** (Service Attachment → PSC NEG → private IP) —
   fits the "middle" panel with two sub-concepts (door + mailbox).
3. **An accept list** — gives the "reverse direction" panel a concrete
   owner + change-control story (IAM accept list, VPC Flow Logs audit).
4. **A crisp outcome** (private, approved, audited, no peering) — fits
   the outcome panel in one sentence.

If the new topic has fewer than 3 of these ingredients, drop the
optional "who controls it" aside. If it has all 4, the 6-panel layout
will land naturally.

## Common panel-mapping mistakes to avoid

- **Forward + reverse confused with "input vs output"**: forward is
  the data-flow direction (request travels); reverse is the
  governance direction (who set this up, who can revoke it, where is
  it logged). Don't write two forward panels and call the second one
  "reverse".
- **"Trigger" panel becoming "definition"**: the trigger is the actor
  who initiates the action, NOT a definition of the technology.
  Bad: "PSC is a way to connect VPCs privately." Good: "Your app
  needs to talk to a managed service without going through the
  public internet."
- **Outcome panel listing features**: the outcome is one sentence
  about the END STATE, not a feature recap. Reserve feature lists
  for the "middle" panel.