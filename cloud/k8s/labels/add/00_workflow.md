# Automation Workflow: Batch Add Labels to Deployments

This document outlines the automated process for adding `eidnumber` and `bidnumber` labels to Kubernetes Deployments based on BigQuery data.

**Constraints:**
- Environment: Shell (Bash) + jq
- Input: BigQuery Data
- Target: Kubernetes Deployments (Multiple Namespaces)

## Workflow Steps

### 1. Data Preparation
- **Script**: `01_export_data.sh`
- **Action**: Exports data from BigQuery to a local JSON file (`raw_data.json`).
- **Note**: Since we cannot connect to BigQuery directly in this environment, this script contains the `bq` command you should run. For testing purposes, it can also generate a dummy `raw_data.json`.

### 2. Generate Mapping
- **Script**: `02_generate_mapping.sh`
- **Action**: Converts `raw_data.json` into a key-value mapping file (`mapping.json`) using `jq`.
- **Format**: `{"api-name": {"eidnumber": "...", "bidnumber": "..."}}`

### 3. Backup
- **Script**: `03_backup.sh`
- **Action**: Backs up all current Deployments to a YAML file (`backup_deployments_<timestamp>.yaml`) before making any changes.

### 4. Apply Labels (Dry Run & Execute)
- **Script**: `04_apply_labels.sh`
- **Action**: 
    1. Iterates through all Deployments in the cluster.
    2. Parses the Deployment name to extract the "API Name" (removes version and `-deployment` suffix).
    3. Looks up the API Name in `mapping.json`.
    4. If matched, patches the Deployment with `eidnumber` and `bidnumber`.
    5. Logs results to `logs/`.
- **Modes**: Supports a `-d` or `--dry-run` flag to preview changes without applying them.

### 5. Verification
- **Script**: `05_verify.sh`
- **Action**: Checks a sample of modified Deployments to ensure labels were added correctly.

### 6. Rollback (If needed)
- **Script**: `06_rollback.sh`
- **Action**: Reverts changes using the backup file or by removing specific labels.

## Directory Structure

```
.
├── 00_workflow.md
├── 01_export_data.sh
├── 02_generate_mapping.sh
├── 03_backup.sh
├── 04_apply_labels.sh
├── 05_verify.sh
├── 06_rollback.sh
├── raw_data.json (Generated)
├── mapping.json (Generated)
└── logs/
    ├── success.log
    ├── failed.log
    └── unmatched.log
```
