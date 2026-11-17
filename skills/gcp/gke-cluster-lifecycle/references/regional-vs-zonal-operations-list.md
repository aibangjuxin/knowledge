# Bug Analysis: `--zone=-` Fails for Regional Clusters

## Symptom

`gcloud container clusters list --zone=-` returns empty for a **regional** cluster, and all subsequent `operations list` calls using `--zone=-` also fail silently.

## Root Cause

`--zone=-` tells gcloud to search all **zones** (e.g., `us-central1-a`, `europe-west2-b`), but regional clusters like `dev-lon-cluster-xxxxxx` live at the **region** level (`europe-west2`), not in any zone scope. The flag mismatch produces zero matches.

## Fix Pattern

Always resolve the cluster's `location` field from `clusters list` first, then determine the correct flag:

```bash
LOC=$(gcloud container clusters list --project=$PROJECT \
    --format="value(name,location)" | grep "^${CLUSTER}" | awk '{print $2}')

if [[ "$LOC" =~ ^[a-z]+-[a-z]+\d+-[a-z]$ ]]; then
    LOC_FLAG="--zone=$LOC"      # zonal cluster
else
    LOC_FLAG="--region=$LOC"    # regional cluster
fi
```

## gcloud Location Flag Reference

| Cluster type | `clusters list` location value | Correct gcloud flag |
|---|---|---|
| Regional | `europe-west2` | `--region=europe-west2` |
| Zonal | `europe-west2-a` | `--zone=europe-west2-a` |
| Multi-zone query (all zones) | — | `--zone=-` |
| Multi-region query (all regions) | — | `--region=-` |

## The Bug in the Original Script

```bash
# Original (WRONG for regional clusters):
location_flag="--zone=-"  # always uses zones, never regions

# Fixed:
if [[ -n "$LOCATION" ]]; then
    location_flag="--zone=$LOCATION"   # or --region=, depending
else
    location_flag="--region=-"         # default to regions for multi-cluster scope
fi
```

## Secondary Bug: `awk 'NR==N'` for Multi-field value() Output

```bash
# WRONG: Fragile — field boundaries break if any field contains whitespace
info=$(gcloud container clusters describe "$cluster" \
    --format="value(currentMasterVersion,currentNodeVersion,location,status)")
master_ver=$(echo "$info" | awk 'NR==1')   # breaks

# CORRECT: Use JSON and jq
info=$(gcloud container clusters describe "$cluster" \
    --format="json(currentMasterVersion,currentNodeVersion,location,status)")
master_ver=$(echo "$info" | jq -r '.currentMasterVersion')
```

## Lessons

1. **`--zone=-` is not universal** — regional clusters need `--region=-`
2. **Auto-infer location** from `clusters list` before calling `describe` or `operations list`
3. **Prefer jq over awk** for parsing multi-field gcloud output — avoids whitespace edge cases
4. **Project ID vs display name** — display name `aibang` ≠ actual project ID `aibang-12345678-ajbx-dev`; always use the actual ID