# GKE Upgrade History Workflow

## Overview

Query GKE cluster upgrade operations via `gcloud container operations list/describe`, retrieve operation logs via Cloud Logging, and produce a version delta summary table.

## Scripts

| Script | Path | Purpose |
|--------|------|---------|
| `gke-upgrade-history.sh` | `~/git/knowledge/gcp/gke/script/` | Main tool (v2.0, portable, multi-format) |
| `verify-gke-cluster-upgrade.sh` | `~/git/knowledge/gcp/gke/script/` | Lex's original script |

## GKE Operations API Key Facts

### Operations That Carry Version Info

Only these operation types have meaningful `detail` fields with version delta:

- `UPGRADE_MASTER` — master version upgrade
- `UPGRADE_NODES` — node pool version upgrade
- `AUTO_UPGRADE_NODES` — GKE auto-upgrade

`UPDATE_CLUSTER` operations (what GKE console shows) often have **null detail/statusMessage** — they are config changes, not version upgrades.

### Filtering Operations

**Good filter (precise)**:
```
targetLink~clusters/${CLUSTER_NAME}
AND (operationType=UPGRADE_MASTER OR operationType=UPGRADE_NODES OR operationType=AUTO_UPGRADE_NODES)
```

**Why `targetLink` over `zone` alone**: avoids cross-cluster bleeding when multiple clusters exist in the same zone.

### Critical jq Pitfall: null Handling

The `//` (alternative) operator in jq does NOT filter out `null` — it only substitutes for *missing* keys. When `detail` is present-but-null in JSON, `.detail // "fallback"` returns `null`, not `"fallback"`.

**Wrong** (leaks `endTime` ISO string into detail column):
```bash
jq -r '... | .detail // .statusMessage // ""'
```

**Correct**:
```bash
jq -r '... | .detail | if . == null or . == "" then .statusMessage else . end // ""'
```

This was the root cause of `endTime` values (e.g. `2026-05-16T03:47:44.807214452Z`) appearing in the version column in the original script.

### Operation describe Output

`gcloud container operations describe <op-name> --zone=<zone> --project=<proj> --format=json` returns:

```json
{
  "name": "operation-xxxx",
  "operationType": "UPDATE_CLUSTER",
  "status": "DONE",
  "startTime": "2026-05-16T03:38:59.9555019Z",
  "endTime": "2026-05-16T03:47:44.807214452Z",
  "targetLink": "https://container.googleapis.com/.../clusters/xxx",
  "detail": null,
  "statusMessage": null
}
```

**Key insight**: Even `operations describe` JSON has no pre-upgrade version. The version delta must come from either:
1. **Cloud Logging** — query `resource.type="gke_cluster"` + operation ID (30-day retention limit)
2. **External version snapshot** — e.g. BigQuery log sink, or manual tracking table

### Cloud Logging Query (for operation logs)

```bash
gcloud logging read \
  'resource.type="gke_cluster" AND resource.labels.location="<zone>" AND "<operation-name>"' \
  --format="table(timestamp,severity,textPayload)" \
  --order=asc --limit=50
```

### macOS vs Linux Compatibility

- macOS `grep` does NOT support `-P` (PCRE). Always use Python for regex parsing in scripts.
- `date` on macOS: `date -u -v-${DAYS}d +"%Y-%m-%dT%H:%M:%SZ"`
- `date` on Linux: `date -u -d "-${DAYS} days" +"%Y-%m-%dT%H:%M:%SZ"`

## Usage

```bash
# Auto-detect project + all clusters
./gke-upgrade-history.sh

# Specific project + cluster + location
./gke-upgrade-history.sh -p PROJECT -c CLUSTER -l ZONE

# Last 30 days, JSON output
./gke-upgrade-history.sh -d 30 -f json

# Show all operation types (not just upgrades)
./gke-upgrade-history.sh -a

# Limit to 10 operations
./gke-upgrade-history.sh -n 10
```

## Output Formats

- `table` (default): colorized status, duration, version delta
- `json`: machine-readable, includes cluster name
- `csv`: for data pipelines

## Version Delta Extraction

Pattern: look for `X.Y.Z-gke.N` strings in `detail/statusMessage`, sort unique, first→last.

```bash
echo "$detail" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[+-][a-z0-9.]+' | sort -u
```

If `< 2` versions found, detail is likely null/uninformative — show truncated detail or "N/A → N/A".