# Implementation Plan - Refactor CD Pipeline (No Kustomize)

## Goal
Use `envsubst` for simple templating and `kubectl apply` for deployment.

## Proposed Changes

### Directory Structure
We will modify the structure in `/Users/lex/git/knowledge/pipeline/cd-pipeline`:

```
.
├── users/
│   └── userA/
│       └── api1/
│           └── templates/  <-- NEW
│               ├── deployment.yaml (parameterized)
│               ├── service.yaml
│               └── ingress.yaml
├── scripts/
│   ├── sync-image.sh (Unchanged)
│   └── render-and-apply.sh (Updated to use envsubst)
├── pipeline/
│   └── cloudbuild.yaml (Updated to remove kustomize step)
├── PMU_Checklist.md (Updated)
└── Namespace_Ingress_Policy.md (Updated)
```

### Cleanup
- Remove `users/userA/api1/base`
- Remove `users/userA/api1/overlays`

### File Details

#### Template Manifests
- `deployment.yaml`: Use `${IMAGE_NAME}`, `${REPLICAS}`, `${CPU_REQUEST}`, etc.
- `service.yaml`: Standard, maybe parameterized if needed.
- `ingress.yaml`: Standard.

#### Scripts
- `render-and-apply.sh`:
    - Export necessary env vars.
    - Run `envsubst < templates/deployment.yaml | kubectl apply -f -`.

#### Pipeline
- `cloudbuild.yaml`: Remove `kustomize build` step. Add step to run `render-and-apply.sh` which now handles rendering.

## Verification Plan
- Verify file existence.
- Verify content of `render-and-apply.sh` uses `envsubst`.
- Verify `walkthrough.md` reflects the new simple flow.
