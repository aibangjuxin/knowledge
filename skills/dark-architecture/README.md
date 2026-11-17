# Dark Architecture Diagrams

> Dark-themed (slate-950 background) variant for architecture diagrams.

## Skill: `dark-architecture`

**Entry point:** `SKILL.md`

## Usage

```python
# Load skill
skill_view(name='dark-architecture')

# Then generate using assets/template.html as base
```

## Contents

| File | Purpose |
|------|---------|
| `SKILL.md` | Full skill: design system, colors, layout rules, output spec |
| `assets/template.html` | Base HTML template with dark theme + SVG patterns |
| `LICENSE` | MIT |

## Design System (Summary)

- **Background:** `#020617` (slate-950) with dot grid pattern
- **Font:** JetBrains Mono (monospace, technical)
- **Colors:**
  - cyan `#22d3ee` → Frontend / Gateway components
  - emerald `#34d399` → Backend / Business services
  - violet `#a78bfa` → Control plane / istiod
  - amber `#fbbf24` → GCP / Cloud services
  - rose `#fb7185` → Security / Auth
  - orange `#fb923c` → Message bus / Event

## Output Target

Diagrams generated with this skill are saved to:
```
knowledge/gcp/asm/diagram/
```

## See Also

- `diagram-design/` — Light-themed parent skill (multiple diagram types)
