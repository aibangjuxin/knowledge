# GKE Upgrade — Session Technical Notes (2026-05-30)

## Verified: Node Pool Upgrade Command

**Finding**: `gcloud container node-pools upgrade` does NOT exist. Node pool upgrade is done via `gcloud container clusters upgrade --node-pool=<POOL_NAME>`.

```bash
# ✅ Verified correct command
gcloud container clusters upgrade dev-lon-cluster-xxxxxx \
  --region=europe-west2 \
  --project=aibang-12345678-ajbx-dev \
  --node-pool=default-pool \
  --cluster-version=1.35.3-gke.1389002 \
  --async

# ❌ Verified error: "Invalid choice: 'upgrade'" when using node-pools subcommand
gcloud container node-pools upgrade default-pool ...
```

## Verified: `--node-pool` Is Value-Taking (Not a Flag)

`--node-pool` is a positional argument that **requires a value** — it is NOT a boolean flag.

```bash
# ✅ --node-pool=POOL_NAME (value attached)
--node-pool=default-pool

# ❌ --node-pool alone (no value) → "expected one argument"
--node-pool
```

## Verified: `operations wait --timeout` Not Supported

`gcloud container operations wait` accepts NO additional arguments beyond the operation ID and global flags. `--timeout` is not a valid flag.

```bash
# ❌ Error: "unrecognized arguments: --timeout=600s"
gcloud container operations wait OP_ID --region=... --project=... --timeout=600s

# ✅ Correct: background wait + foreground poll
gcloud container operations wait "$op_id" --region=$REGION --project=$PROJECT &
while true; do
  status=$(gcloud container operations describe "$op_id" \
    --region=$REGION --project=$PROJECT --format="value(status)")
  [[ "$status" == "DONE" ]] && break
  sleep 20
done
```

## Verified: Upgrade Conflict Error Message

When attempting to upgrade a cluster that already has a RUNNING operation:

```
ERROR: (gcloud.container.clusters.upgrade) ResponseError: code=400,
message=Cluster is running incompatible operation operation-1780107322768-e6f3876e-6d46-42f6-8f0c-956fc31e880c.
```

**Resolution**: Wait for the current operation to complete. Check status:

```bash
gcloud container operations describe operation-1780107322768... \
  --region=europe-west2 --project=aibang-12345678-ajbx-dev \
  --format="value(status)"
```

## Verified: Master/Node Version Constraint

- Node version must be ≤ Master version (hard GKE constraint)
- Node pool upgrade `gcloud ... --cluster-version` is mandatory — GKE does not auto-select
- If `--node-pool-version` not specified, set it to `currentMasterVersion`

## Verified: Color Codes in bash (macOS)

Escape sequences in bash heredocs or variable assignments require ANSI-C quoting (`$'\033[...]'`), NOT single quotes (`'\033[...]'`):

```bash
# ✅ Works in bash/macOS
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'

# ❌ Single quotes don't expand \033 — prints literal \033
RED='\033[0;31m'
```

## Actual Timing (dev-lon-cluster-xxxxxx, 2026-05-30)

| Operation | Operation ID | Start | Duration |
|-----------|-------------|-------|----------|
| UPGRADE_MASTER | operation-1780104945043... | 01:35:45Z | ~8m 26s |
| UPGRADE_NODES | operation-1780107322768... | 02:15:22Z | ~7+ min (still RUNNING at time of note) |