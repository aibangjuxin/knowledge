# GCE Disaster Recovery Validation

This directory contains scripts to validate disaster recovery capabilities for Google Cloud Engine (GCE) Managed Instance Groups (MIG).

## Files

- `gce-dr-validation.sh` - Main DR validation script
- `run-dr-test.sh` - Wrapper script with configuration loading
- `dr-config.env` - Configuration file template
- `dr-instance.sh` - Original script (kept for reference)
- `dr-mig-zone-test.md` - Documentation and background

## Quick Start

1. **Configure your environment:**
   ```bash
   cp dr-config.env dr-config.env.local
   # Edit dr-config.env.local with your actual values
   ```

2. **Run the DR validation:**
   ```bash
   ./run-dr-test.sh
   ```

## What the Script Tests

### 1. Zone Distribution Validation
- Tests if MIG can distribute instances across multiple zones
- Validates auto-scaling behavior across zones

### 2. Zone Failure Simulation
- Simulates zone failure by deleting instances in a specific zone
- Verifies that MIG recreates instances in remaining available zones
- Confirms no instances remain in the "failed" zone

### 3. Auto-scaling Integration
- Temporarily disables autoscaler for controlled testing
- Option to restore autoscaler settings after testing

## Test Scenarios

The script performs these DR validation steps:

1. **Initial State Check** - Shows current instance distribution
2. **Scale-Up Test** - Increases instance count to test zone distribution
3. **Zone Failure Simulation** - Deletes instances from one zone
4. **Recovery Validation** - Confirms instances are recreated in other zones
5. **Configuration Restoration** - Optional restore to original state

## Configuration

### Required Variables
```bash
MIG_NAME="your-mig-name"           # Name of your MIG
REGION="europe-west2"              # GCP region
PROJECT_ID="your-project-id"       # GCP project ID
```

### Optional Variables
```bash
INITIAL_SIZE=2                     # Starting number of instances
SCALE_UP_SIZE=4                    # Target size for scale-up test
TARGET_CPU_UTIL=0.9               # CPU utilization target for autoscaler
COOL_DOWN_PERIOD="180s"           # Autoscaler cool-down period
ZONE_TO_SIMULATE_FAILURE="europe-west2-a"  # Zone to simulate failure
```

## Prerequisites

1. **GCP CLI installed and authenticated:**
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Regional MIG with multi-zone distribution:**
   - Your MIG should be regional (not zonal)
   - Should have distribution policy across multiple zones

3. **Appropriate IAM permissions:**
   - `compute.instanceGroups.update`
   - `compute.instances.delete`
   - `compute.autoscalers.update`

## Usage Examples

### Basic DR Test
```bash
# Using configuration file
./run-dr-test.sh

# Direct execution with environment variables
MIG_NAME="my-app-mig" REGION="us-central1" PROJECT_ID="my-project" ./gce-dr-validation.sh
```

### Advanced Usage
```bash
# Test specific zone failure
ZONE_TO_SIMULATE_FAILURE="us-central1-b" ./run-dr-test.sh

# Custom scaling parameters
INITIAL_SIZE=3 SCALE_UP_SIZE=6 ./run-dr-test.sh
```

## Expected Output

The script provides colored output showing:
- ✅ **SUCCESS**: Operations completed successfully
- ⚠️ **WARNING**: Non-critical issues or informational messages  
- ❌ **ERROR**: Critical failures that need attention
- ℹ️ **INFO**: General information and progress updates

### Sample Output
```
========================================
GCE Disaster Recovery Validation Script
========================================

[INFO] Configuration:
  MIG Name: my-app-mig
  Region: europe-west2
  Project: my-project-123

[INFO] Initial MIG State
==================================================
INSTANCE         ZONE            STATUS
my-app-mig-abc   europe-west2-a  RUNNING
my-app-mig-def   europe-west2-b  RUNNING

[SUCCESS] ✓ Zone europe-west2-b has 1 instance(s)
[SUCCESS] ✓ Zone europe-west2-c has 1 instance(s)
[SUCCESS] ✓ No instances in simulated failed zone (europe-west2-a)

[SUCCESS] DR validation PASSED: Instances successfully redistributed to available zones
```

## Troubleshooting

### Common Issues

1. **MIG not found:**
   - Verify MIG name and region are correct
   - Ensure you have proper permissions

2. **Instances not redistributing:**
   - Check if MIG has multi-zone distribution policy
   - Verify zones have available capacity

3. **Autoscaler issues:**
   - Ensure autoscaler exists before trying to disable
   - Check autoscaler permissions

### Debug Mode
Add `set -x` to the beginning of the script for detailed execution logging.

## Safety Notes

- This script modifies your MIG configuration temporarily
- Always test in non-production environments first
- The script includes restoration options to return to original state
- Monitor your instances during testing to ensure expected behavior

## Integration with CI/CD

You can integrate this script into your CI/CD pipeline for automated DR testing:

```yaml
# Example GitHub Actions step
- name: Run DR Validation
  run: |
    cd test/dr-instance
    export MIG_NAME="${{ secrets.MIG_NAME }}"
    export PROJECT_ID="${{ secrets.GCP_PROJECT_ID }}"
    export REGION="europe-west2"
    ./gce-dr-validation.sh
```

# summary
reated a comprehensive DR validation solution for your GCE instances. Here's what I've built for you:

🎯 New Optimized Scripts
1. gce-dr-validation.sh - Main DR validation script
Comprehensive testing: Scale-up validation + zone failure simulation
Smart autoscaler handling: Temporarily disables/restores autoscaler
Visual feedback: Color-coded output with clear success/failure indicators
Zone distribution analysis: Shows before/after instance distribution
Configurable parameters: Easy to customize for different environments
2. run-dr-test.sh - Easy-to-use wrapper
Configuration management: Loads settings from config file
Validation checks: Ensures required parameters are set
Error handling: Clear error messages for missing configuration
3. dr-config.env - Configuration template
Environment variables: All customizable parameters in one place
Documentation: Comments explaining each setting
Flexible: Override any setting as needed
4. README.md - Complete documentation
Usage instructions: Step-by-step guide
Configuration examples: Multiple usage scenarios
Troubleshooting: Common issues and solutions
🚀 Key Improvements Over Original Script
Enhanced DR Testing:

Tests both scale-up distribution AND zone failure recovery
Validates that instances don't return to "failed" zones
Comprehensive zone distribution analysis
Better User Experience:

Color-coded output for easy reading
Progress indicators and clear status messages
Interactive prompts for restoration
Production Ready:

Proper error handling and validation
Configuration file support
Safety checks and restoration options
Flexible Configuration:

Environment variable support
Easy customization for different regions/projects
Configurable timing and scaling parameters
📋 Quick Usage
# 1. Configure your environment
cp dr-config.env dr-config.env.local
# Edit with your MIG_NAME, PROJECT_ID, REGION

# 2. Run the DR test
./run-dr-test.sh
The script will automatically:

✅ Show initial instance distribution
✅ Test scale-up across zones
✅ Simulate zone failure by deleting instances
✅ Verify instances recreate in remaining zones
✅ Offer to restore original configuration
This gives you a complete, automated way to validate that your GCE instances can properly handle zone failures and auto-scale across regions as expected for DR scenarios.