# GKE Upgrade Scripts — Session Notes

## Verified Scripts (working copies live in /Users/lex/git/gcp/Scripts/)

| Script | Path | Version | Status |
|--------|------|---------|--------|
| verify-gke-cluster-upgrade.sh | /Users/lex/git/gcp/Scripts/ | v2.1 | ✅ verified |
| upgrade-gke-cluster.sh | /Users/lex/git/gcp/Scripts/ | v1.0 | ✅ verified |
| upgrade-gke-node.sh | /Users/lex/git/gcp/Scripts/ | v1.0 | ✅ verified |

## v2.1 Key Implementation Points (verify-gke-cluster-upgrade.sh)

1. **Location inference**: `grep "^${cluster}"` (plain grep, NOT `grep -F`) to detect regional vs zonal
2. **Shell options**: `set -uo pipefail` — no `-e`, because `read` returns 1 at EOF and would kill the script
3. **macOS carriage return**: `jq -r '...' | tr -d '\r'` on all field reads
4. **Duration calc**: uses `endTime` (may be empty "" for in-progress ops)
5. **print_table()**: reads 5 fields — `start_time end_time op_type status detail`
6. **GCP API limitation**: operation record `detail` field is empty for UPGRADE_MASTER; always cross-reference `clusters describe` for actual version values

## v1.0 Key Implementation Points (upgrade-gke-cluster.sh)

1. **Specifying exact version**: `gcloud container clusters upgrade ... --cluster-version=<VERSION> --master --quiet`
2. **Regional clusters**: always use `--region=<REGION>`, not `--zone=<ZONE>`
3. **Progress monitoring**: polls `operations describe` every 30s until DONE/ABORTING/FAILED
4. **Exit codes**: 0 = success, 1 = dry-run/abort/failure, 2 = invalid args

## v1.0 Key Implementation Points (upgrade-gke-node.sh)

1. **Node upgrade commands**: 
   - Per-pool (preferred): `gcloud container node-pools upgrade <POOL> --cluster-version=<VERSION>`
   - Cluster-wide: `gcloud container clusters upgrade <CLUSTER> --node-pool --cluster-version=<VERSION>`
2. **Auto-detect target version**: if `--node-pool-version` not specified, automatically uses Master version from `clusters describe`
3. **PDB pre-flight check**: calls `kubectl get pdb --all-namespaces` and warns if no PDBs found (does not block)
4. **Surge strategy**: `surge=1, maxUnavailable=0` is the recommended production config
5. **Color codes in bash**: must use `$'...'` ANSI-C quoting for `\033` escape sequences — single-quoted `'\033...'` is literal text, not an escape. Example: `RED=$'\033[0;31m'` not `RED='\033[0;31m'`
6. **Version constraint**: Node version ≤ Master version (enforced by GKE)
7. **Operation is async**: `node-pools upgrade` returns operation ID immediately; must poll `operations wait`

## Known GCP Behavior

- UPGRADE_MASTER operation record `detail` field: **empty string** (GCP does not store version-from/to)
- `operations describe --format="json"` `endTime` field: empty `""` until operation completes
- Master upgrade does NOT automatically upgrade nodes; nodes stay on prior version until explicitly upgraded
- Node pool upgrades require Node version ≤ Master version (GKE enforced constraint)

## Node Upgrade Strategy Summary

| Strategy | surge | maxUnavailable | Downtime | Extra Cost |
|----------|-------|---------------|----------|-----------|
| Surge (recommended) | 1 | 0 | 零中断 | +1 node |
| Blue/Green | N | 0 | 零中断 | +100% nodes |
| In-Place (1.31+) | 0 | 1 | 可能有短暂 | 几乎无 |

Recommend: surge=1, maxUnavailable=0 (zero-downtime, minimal extra resources).

## Common Syntax Bug Pattern

When bash heredocs (`cat <<EOF`) contain ANSI color codes like `\033[1m`, they render as literal text on macOS because `'\033'` in single quotes is a literal backslash, not an escape character.

**Fix**: Use ANSI-C quoting `$'\033[...'` for color variable definitions, not single quotes:

```bash
# WRONG — renders as literal text in heredocs
RED='\033[0;31m'
BOLD='\033[1m'

# CORRECT — $'...' expands \033 to escape char
RED=$'\033[0;31m'
BOLD=$'\033[1m'
```

Also watch for missing closing quotes in multi-argument function calls:
```bash
# WRONG — unclosed quote, arg2 gets absorbed
wait_for_operation "$op_id "upgrade message""

# CORRECT — two separate quoted args
wait_for_operation "$op_id" "upgrade message"
```