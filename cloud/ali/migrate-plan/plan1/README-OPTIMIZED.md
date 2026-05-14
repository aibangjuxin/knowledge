# Kubernetes Ingress Migration Tool - Optimized Version

## Overview

This is an optimized version of the Kubernetes Ingress migration script with enhanced error handling, performance improvements, and production-ready features.

## Key Improvements

### 🚀 Performance Enhancements
- **Parallel Processing**: Batch migrations now support parallel execution (configurable via `--parallel`)
- **JQ-based Parsing**: Faster JSON parsing using `jq` instead of text processing
- **Caching**: Temporary caching of kubectl queries to reduce API calls
- **Optimized Queries**: Single kubectl call to fetch all ingresses, then filter locally

### 🛡️ Enhanced Error Handling
- **Comprehensive Error Traps**: Using `set -eEuo pipefail` for strict error handling
- **Automatic Rollback**: Failed migrations can automatically rollback (configurable)
- **Retry Logic**: Exponential backoff retry for transient failures
- **Backup Integrity**: SHA256 checksums for backup verification

### ✅ Validation & Safety
- **Input Validation**: Strict regex validation for hostnames and Kubernetes names
- **Dry-Run Mode**: Preview all changes before applying with `--dry-run`
- **Health Checks**: Automatic health verification after migration
- **Dependency Checks**: Validates required tools before execution

### 📊 Better Monitoring
- **Structured Logging**: Support for JSON output (`--json`) for log aggregation
- **Verbose Mode**: Detailed debug logging with `--verbose`
- **Color-Coded Output**: Clear visual feedback for different log levels
- **Migration Records**: CSV tracking of all migrations with timestamps

### 🔧 Additional Features
- **Force Mode**: Re-migrate already migrated services with `--force`
- **Configurable Timeouts**: Customizable health check and connection timeouts
- **Cleanup on Exit**: Automatic cleanup of temporary files
- **Extended Annotations**: Rich metadata in migrated resources

## Installation

```bash
# Make the script executable
chmod +x k8s-ingress-migration-optimized.sh

# Create required directories
mkdir -p logs backups

# Install dependencies (macOS)
brew install kubectl jq curl coreutils

# Install dependencies (Linux)
apt-get install kubectl jq curl coreutils  # Debian/Ubuntu
yum install kubectl jq curl coreutils      # RHEL/CentOS
```

## Usage Examples

### Basic Migration

```bash
# Single host migration
./k8s-ingress-migration-optimized.sh switch \
  api.old.example.com \
  api.new.example.com

# Check migration status
./k8s-ingress-migration-optimized.sh status api.old.example.com

# Rollback if needed
./k8s-ingress-migration-optimized.sh rollback api.old.example.com
```

### Batch Migration

```bash
# Dry-run to preview changes
./k8s-ingress-migration-optimized.sh --dry-run batch migration-config.csv

# Execute batch migration with parallel processing
./k8s-ingress-migration-optimized.sh --parallel 10 batch migration-config.csv

# View all migration records
./k8s-ingress-migration-optimized.sh list
```

### Advanced Options

```bash
# Verbose mode with dry-run
./k8s-ingress-migration-optimized.sh -v --dry-run switch \
  api.old.example.com api.new.example.com

# Force re-migration with JSON logging
./k8s-ingress-migration-optimized.sh --force --json switch \
  api.old.example.com api.new.example.com

# Batch migration without health checks
./k8s-ingress-migration-optimized.sh --no-health-check batch config.csv

# Migration without automatic rollback
./k8s-ingress-migration-optimized.sh --no-rollback switch \
  api.old.example.com api.new.example.com
```

## Configuration File Format

The CSV configuration file for batch migrations should follow this format:

```csv
# Comments start with #
old_host,new_host
api1.old.example.com,api1.new.example.com
api2.old.example.com,api2.new.example.com
```

## Directory Structure

```
.
├── k8s-ingress-migration-optimized.sh  # Main script
├── migration-config.csv                 # Batch configuration
├── migration-records.csv                # Migration history
├── logs/                                # Log files
│   └── migration_YYYYMMDD_HHMMSS.log
└── backups/                            # Backup files
    └── YYYYMMDD_HHMMSS/
        ├── namespace_ingress_HHMMSS.yaml
        └── namespace_ingress_HHMMSS.yaml.sha256
```

## Environment Variables

- `KUBECONFIG`: Path to kubeconfig file
- `MIGRATION_LOG_DIR`: Override default log directory
- `MIGRATION_BACKUP_DIR`: Override default backup directory

## Features Comparison

| Feature | Original Script | Optimized Script |
|---------|----------------|------------------|
| Error Handling | Basic | Advanced with traps |
| Parallel Processing | No | Yes (configurable) |
| Dry-Run Mode | No | Yes |
| Input Validation | Basic | Comprehensive |
| Health Checks | Simple | Detailed with timeout |
| Backup Verification | No | SHA256 checksums |
| JSON Logging | No | Yes |
| Retry Logic | No | Exponential backoff |
| Auto Rollback | No | Yes (configurable) |
| Performance | Sequential | Parallel + Caching |

## Troubleshooting

### Common Issues

1. **kubectl not found**
   - Ensure kubectl is installed and in PATH
   - Verify with: `which kubectl`

2. **Connection to cluster failed**
   - Check KUBECONFIG environment variable
   - Verify cluster access: `kubectl cluster-info`

3. **Permission denied**
   - Ensure script has execute permissions
   - Check Kubernetes RBAC permissions

4. **Health check failures**
   - Increase timeout: Modify `DEFAULT_HEALTH_CHECK_TIMEOUT`
   - Skip health checks: Use `--no-health-check`

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
./k8s-ingress-migration-optimized.sh -v --dry-run switch \
  api.old.example.com api.new.example.com 2>&1 | tee debug.log
```

## Safety Considerations

1. **Always test with dry-run first**: Use `--dry-run` to preview changes
2. **Start with single migrations**: Test individual hosts before batch operations
3. **Monitor logs**: Check `logs/` directory for detailed execution logs
4. **Verify backups**: Ensure backups are created before proceeding
5. **Test rollback procedure**: Verify rollback works in your environment

## Performance Tips

1. **Parallel Processing**: Adjust `--parallel` based on cluster capacity
2. **Batch Size**: Split large migrations into smaller batches
3. **Off-Peak Hours**: Run migrations during low-traffic periods
4. **Resource Monitoring**: Monitor cluster resources during migration

## License

This script is provided as-is for educational and operational purposes.

## Support

For issues or questions, please check the logs first and ensure all dependencies are properly installed.
