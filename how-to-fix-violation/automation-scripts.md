# Automation Scripts for Container Security

## 🎯 Overview

This collection of automation scripts helps you detect, analyze, and fix container security violations systematically. Based on your existing tools and documentation, these scripts integrate with Nexus IQ, Google Artifact Registry, Trivy, and other security tools.

## 🔍 Detection Scripts

### 1. Comprehensive Security Scanner
```bash
#!/bin/bash
# comprehensive-scan.sh
# Unified security scanning script

set -e

# Configuration
REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/my-project/my-repo}"
NEXUS_IQ_URL="${NEXUS_IQ_URL:-http://nexus-iq-server:8070}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
REPORT_DIR="./security-reports"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS] IMAGE_NAME"
    echo "Options:"
    echo "  -r, --registry REGISTRY    Container registry URL"
    echo "  -o, --output DIR          Output directory for reports"
    echo "  -s, --slack WEBHOOK       Slack webhook URL for alerts"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 my-app:latest"
    echo "  $0 -r gcr.io/project/repo -o /tmp/reports my-app:v1.0.0"
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -o|--output)
            REPORT_DIR="$2"
            shift 2
            ;;
        -s|--slack)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            IMAGE_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$IMAGE_NAME" ]; then
    error "Image name is required"
    usage
    exit 1
fi

# Create report directory
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_PREFIX="${REPORT_DIR}/${IMAGE_NAME//\//_}_${TIMESTAMP}"

log "Starting comprehensive security scan for: $IMAGE_NAME"

# 1. Trivy Scan
log "Running Trivy vulnerability scan..."
trivy image --format json --output "${REPORT_PREFIX}_trivy.json" "$IMAGE_NAME" || {
    error "Trivy scan failed"
    exit 1
}

# 2. Generate SBOM
log "Generating Software Bill of Materials..."
if command -v syft &> /dev/null; then
    syft "$IMAGE_NAME" -o cyclonedx-json > "${REPORT_PREFIX}_sbom.json"
    
    # Scan SBOM with Grype if available
    if command -v grype &> /dev/null; then
        log "Scanning SBOM with Grype..."
        grype "sbom:${REPORT_PREFIX}_sbom.json" -o json > "${REPORT_PREFIX}_grype.json"
    fi
else
    warn "Syft not found, skipping SBOM generation"
fi

# 3. Check Google Artifact Registry (if image is in GAR)
if [[ "$IMAGE_NAME" == *"docker.pkg.dev"* ]]; then
    log "Checking Google Artifact Registry scan results..."
    
    # Get image digest
    DIGEST=$(gcloud artifacts docker images list "$IMAGE_NAME" --format="value(digest)" | head -1)
    
    if [ -n "$DIGEST" ]; then
        gcloud artifacts docker images describe "${IMAGE_NAME}@${DIGEST}" \
            --show-package-vulnerability \
            --format=json > "${REPORT_PREFIX}_gar.json" 2>/dev/null || {
            warn "Could not retrieve GAR scan results"
        }
    fi
fi

# 4. Analyze results and generate summary
log "Analyzing scan results..."

python3 << EOF
import json
import sys
from pathlib import Path

def analyze_trivy_results(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
        
        vulnerabilities = []
        for result in data.get('Results', []):
            vulnerabilities.extend(result.get('Vulnerabilities', []))
        
        severity_counts = {}
        for vuln in vulnerabilities:
            severity = vuln.get('Severity', 'UNKNOWN')
            severity_counts[severity] = severity_counts.get(severity, 0) + 1
        
        return severity_counts, vulnerabilities
    except Exception as e:
        print(f"Error analyzing Trivy results: {e}")
        return {}, []

def generate_summary_report(trivy_file, output_file):
    severity_counts, vulnerabilities = analyze_trivy_results(trivy_file)
    
    # Calculate risk score
    risk_score = (
        severity_counts.get('CRITICAL', 0) * 10 +
        severity_counts.get('HIGH', 0) * 7 +
        severity_counts.get('MEDIUM', 0) * 4 +
        severity_counts.get('LOW', 0) * 1
    )
    
    # Determine risk level
    if risk_score >= 50:
        risk_level = "CRITICAL"
    elif risk_score >= 20:
        risk_level = "HIGH"
    elif risk_score >= 10:
        risk_level = "MEDIUM"
    else:
        risk_level = "LOW"
    
    summary = {
        "image": "$IMAGE_NAME",
        "scan_timestamp": "$TIMESTAMP",
        "risk_score": risk_score,
        "risk_level": risk_level,
        "vulnerability_counts": severity_counts,
        "total_vulnerabilities": sum(severity_counts.values()),
        "critical_vulnerabilities": [
            {
                "id": v.get('VulnerabilityID'),
                "package": v.get('PkgName'),
                "version": v.get('InstalledVersion'),
                "fixed_version": v.get('FixedVersion'),
                "title": v.get('Title', '')[:100]
            }
            for v in vulnerabilities if v.get('Severity') == 'CRITICAL'
        ][:10]  # Top 10 critical vulnerabilities
    }
    
    with open(output_file, 'w') as f:
        json.dump(summary, f, indent=2)
    
    return summary

# Generate summary
summary = generate_summary_report("${REPORT_PREFIX}_trivy.json", "${REPORT_PREFIX}_summary.json")
print(f"Risk Level: {summary['risk_level']}")
print(f"Risk Score: {summary['risk_score']}")
print(f"Total Vulnerabilities: {summary['total_vulnerabilities']}")

# Exit with appropriate code
if summary['risk_level'] in ['CRITICAL', 'HIGH']:
    sys.exit(1)
EOF

SCAN_RESULT=$?

# 5. Send alerts if configured
if [ -n "$SLACK_WEBHOOK" ] && [ $SCAN_RESULT -ne 0 ]; then
    log "Sending Slack alert..."
    
    SUMMARY=$(cat "${REPORT_PREFIX}_summary.json")
    RISK_LEVEL=$(echo "$SUMMARY" | jq -r '.risk_level')
    TOTAL_VULNS=$(echo "$SUMMARY" | jq -r '.total_vulnerabilities')
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{
            \"text\": \"🚨 Security Alert: $IMAGE_NAME\",
            \"attachments\": [{
                \"color\": \"danger\",
                \"fields\": [
                    {\"title\": \"Risk Level\", \"value\": \"$RISK_LEVEL\", \"short\": true},
                    {\"title\": \"Total Vulnerabilities\", \"value\": \"$TOTAL_VULNS\", \"short\": true}
                ]
            }]
        }" \
        "$SLACK_WEBHOOK"
fi

log "Security scan completed. Reports saved to: $REPORT_DIR"
log "Summary report: ${REPORT_PREFIX}_summary.json"

exit $SCAN_RESULT
```

### 2. Kubernetes Cluster Scanner
```bash
#!/bin/bash
# k8s-cluster-scan.sh
# Scan all running containers in Kubernetes cluster

set -e

NAMESPACE="${1:-default}"
OUTPUT_DIR="./k8s-security-reports/$(date +%Y%m%d_%H%M%S)"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

mkdir -p "$OUTPUT_DIR"

log "Scanning Kubernetes cluster for security violations..."
log "Namespace: $NAMESPACE"
log "Output directory: $OUTPUT_DIR"

# Get all unique images in the namespace
IMAGES=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u)

log "Found $(echo "$IMAGES" | wc -l) unique images to scan"

# Scan each image
for image in $IMAGES; do
    log "Scanning image: $image"
    
    # Clean image name for filename
    CLEAN_NAME=$(echo "$image" | sed 's/[^a-zA-Z0-9._-]/_/g')
    
    # Run comprehensive scan
    ./comprehensive-scan.sh -o "$OUTPUT_DIR" "$image" || {
        log "WARNING: Scan failed for $image"
        continue
    }
done

# Generate cluster summary
log "Generating cluster security summary..."

python3 << EOF
import json
import glob
import os
from pathlib import Path

output_dir = "$OUTPUT_DIR"
summary_files = glob.glob(f"{output_dir}/*_summary.json")

cluster_summary = {
    "namespace": "$NAMESPACE",
    "scan_timestamp": "$(date -Iseconds)",
    "total_images": len(summary_files),
    "risk_distribution": {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0},
    "total_vulnerabilities": 0,
    "images": []
}

for summary_file in summary_files:
    try:
        with open(summary_file, 'r') as f:
            image_summary = json.load(f)
        
        cluster_summary["risk_distribution"][image_summary["risk_level"]] += 1
        cluster_summary["total_vulnerabilities"] += image_summary["total_vulnerabilities"]
        cluster_summary["images"].append({
            "image": image_summary["image"],
            "risk_level": image_summary["risk_level"],
            "risk_score": image_summary["risk_score"],
            "vulnerability_count": image_summary["total_vulnerabilities"]
        })
    except Exception as e:
        print(f"Error processing {summary_file}: {e}")

# Sort images by risk score
cluster_summary["images"].sort(key=lambda x: x["risk_score"], reverse=True)

# Save cluster summary
with open(f"{output_dir}/cluster_summary.json", 'w') as f:
    json.dump(cluster_summary, f, indent=2)

print(f"Cluster scan completed:")
print(f"  Total images: {cluster_summary['total_images']}")
print(f"  Total vulnerabilities: {cluster_summary['total_vulnerabilities']}")
print(f"  Risk distribution: {cluster_summary['risk_distribution']}")
EOF

log "Cluster scan completed. Results saved to: $OUTPUT_DIR"
```

## 🛠 Remediation Scripts

### 3. Automated Dockerfile Fixer
```python
#!/usr/bin/env python3
# dockerfile-fixer.py
# Automatically fix common Dockerfile security issues

import re
import sys
import argparse
from pathlib import Path

class DockerfileFixer:
    def __init__(self):
        self.fixes_applied = []
        
        # Base image mappings for security updates
        self.base_image_updates = {
            'ubuntu:20.04': 'ubuntu:22.04-slim',
            'ubuntu:18.04': 'ubuntu:22.04-slim',
            'node:16': 'node:18-alpine',
            'node:14': 'node:18-alpine',
            'python:3.8': 'python:3.11-slim',
            'python:3.9': 'python:3.11-slim',
            'openjdk:8': 'openjdk:17-jre-slim',
            'openjdk:11': 'openjdk:17-jre-slim',
        }
    
    def fix_base_images(self, content):
        """Update base images to more secure versions"""
        for old_image, new_image in self.base_image_updates.items():
            pattern = f'FROM {re.escape(old_image)}'
            if re.search(pattern, content):
                content = re.sub(pattern, f'FROM {new_image}', content)
                self.fixes_applied.append(f"Updated base image: {old_image} -> {new_image}")
        
        return content
    
    def add_non_root_user(self, content):
        """Add non-root user if not present"""
        if 'USER ' not in content and 'FROM scratch' not in content:
            # Detect base image type
            if 'alpine' in content.lower():
                user_commands = """
# Create non-root user
RUN addgroup -g 1001 -S appgroup && \\
    adduser -S appuser -u 1001 -G appgroup

USER appuser
"""
            else:
                user_commands = """
# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

USER appuser
"""
            
            # Insert before CMD/ENTRYPOINT
            cmd_pattern = r'(CMD|ENTRYPOINT)'
            if re.search(cmd_pattern, content):
                content = re.sub(f'({cmd_pattern})', f'{user_commands}\\1', content, count=1)
            else:
                content += user_commands
            
            self.fixes_applied.append("Added non-root user")
        
        return content
    
    def fix_apt_commands(self, content):
        """Fix apt-get commands for security"""
        # Pattern for apt-get install without update
        apt_pattern = r'RUN apt-get install'
        if re.search(apt_pattern, content):
            content = re.sub(
                r'RUN apt-get install',
                'RUN apt-get update && apt-get install --no-install-recommends',
                content
            )
            self.fixes_applied.append("Fixed apt-get commands to include update and --no-install-recommends")
        
        # Add cleanup to apt commands
        apt_cleanup_pattern = r'(RUN apt-get update.*?install.*?)(\n|$)'
        def add_cleanup(match):
            command = match.group(1)
            if 'rm -rf /var/lib/apt/lists/*' not in command:
                return command + ' && \\\n    apt-get clean && \\\n    rm -rf /var/lib/apt/lists/*\n'
            return match.group(0)
        
        content = re.sub(apt_cleanup_pattern, add_cleanup, content, flags=re.MULTILINE | re.DOTALL)
        
        return content
    
    def add_healthcheck(self, content):
        """Add healthcheck if not present"""
        if 'HEALTHCHECK' not in content and 'FROM scratch' not in content:
            # Detect if it's a web application
            if any(port in content for port in ['EXPOSE 80', 'EXPOSE 8080', 'EXPOSE 3000']):
                healthcheck = """
# Add healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:8080/health || exit 1
"""
                # Insert before CMD/ENTRYPOINT
                cmd_pattern = r'(CMD|ENTRYPOINT)'
                if re.search(cmd_pattern, content):
                    content = re.sub(f'({cmd_pattern})', f'{healthcheck}\\1', content, count=1)
                else:
                    content += healthcheck
                
                self.fixes_applied.append("Added healthcheck")
        
        return content
    
    def fix_copy_permissions(self, content):
        """Fix COPY commands to set proper permissions"""
        copy_pattern = r'COPY (.*?) (.*?)(\n|$)'
        
        def fix_copy(match):
            source = match.group(1)
            dest = match.group(2)
            ending = match.group(3)
            
            # Skip if already has --chown
            if '--chown=' in match.group(0):
                return match.group(0)
            
            # Add --chown=appuser:appgroup if USER is set
            if 'USER ' in content:
                return f'COPY --chown=appuser:appgroup {source} {dest}{ending}'
            
            return match.group(0)
        
        new_content = re.sub(copy_pattern, fix_copy, content)
        if new_content != content:
            self.fixes_applied.append("Fixed COPY commands with proper ownership")
        
        return new_content
    
    def convert_to_multistage(self, content):
        """Convert to multi-stage build if beneficial"""
        # Simple heuristic: if there are build tools, suggest multi-stage
        build_tools = ['gcc', 'make', 'build-essential', 'npm install', 'pip install']
        
        if any(tool in content for tool in build_tools) and 'AS builder' not in content:
            # This is a complex transformation, just add a comment for now
            suggestion = """
# SUGGESTION: Consider converting to multi-stage build for smaller image size
# Example:
# FROM node:18-alpine AS builder
# ... build steps ...
# FROM node:18-alpine AS runtime
# COPY --from=builder /app/dist ./dist
"""
            content = suggestion + content
            self.fixes_applied.append("Added multi-stage build suggestion")
        
        return content
    
    def fix_dockerfile(self, dockerfile_path):
        """Apply all fixes to a Dockerfile"""
        with open(dockerfile_path, 'r') as f:
            content = f.read()
        
        original_content = content
        
        # Apply fixes
        content = self.fix_base_images(content)
        content = self.fix_apt_commands(content)
        content = self.add_non_root_user(content)
        content = self.add_healthcheck(content)
        content = self.fix_copy_permissions(content)
        content = self.convert_to_multistage(content)
        
        return content, original_content != content

def main():
    parser = argparse.ArgumentParser(description='Automatically fix Dockerfile security issues')
    parser.add_argument('dockerfile', help='Path to Dockerfile')
    parser.add_argument('--dry-run', action='store_true', help='Show changes without applying them')
    parser.add_argument('--backup', action='store_true', help='Create backup of original file')
    
    args = parser.parse_args()
    
    dockerfile_path = Path(args.dockerfile)
    if not dockerfile_path.exists():
        print(f"Error: {dockerfile_path} not found")
        sys.exit(1)
    
    fixer = DockerfileFixer()
    fixed_content, has_changes = fixer.fix_dockerfile(dockerfile_path)
    
    if not has_changes:
        print("No security issues found in Dockerfile")
        return
    
    print("Applied fixes:")
    for fix in fixer.fixes_applied:
        print(f"  - {fix}")
    
    if args.dry_run:
        print("\n--- Fixed Dockerfile (dry-run) ---")
        print(fixed_content)
    else:
        if args.backup:
            backup_path = dockerfile_path.with_suffix('.bak')
            dockerfile_path.rename(backup_path)
            print(f"Backup created: {backup_path}")
        
        with open(dockerfile_path, 'w') as f:
            f.write(fixed_content)
        
        print(f"Dockerfile updated: {dockerfile_path}")

if __name__ == '__main__':
    main()
```

### 4. Dependency Updater
```bash
#!/bin/bash
# dependency-updater.sh
# Update dependencies across different package managers

set -e

PROJECT_DIR="${1:-.}"
DRY_RUN="${2:-false}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

update_npm_dependencies() {
    if [ -f "package.json" ]; then
        log "Updating Node.js dependencies..."
        
        if [ "$DRY_RUN" = "true" ]; then
            npm outdated || true
            npm audit || true
        else
            # Update dependencies
            npm update
            
            # Fix security vulnerabilities
            npm audit fix --audit-level=high
            
            # Check for remaining issues
            npm audit --audit-level=moderate
        fi
    fi
}

update_python_dependencies() {
    if [ -f "requirements.txt" ]; then
        log "Updating Python dependencies..."
        
        if [ "$DRY_RUN" = "true" ]; then
            pip list --outdated || true
            safety check || true
        else
            # Install pip-review for updates
            pip install pip-review safety
            
            # Update dependencies
            pip-review --local --auto
            
            # Check for security issues
            safety check
            
            # Update requirements.txt
            pip freeze > requirements.txt
        fi
    fi
}

update_maven_dependencies() {
    if [ -f "pom.xml" ]; then
        log "Updating Maven dependencies..."
        
        if [ "$DRY_RUN" = "true" ]; then
            mvn versions:display-dependency-updates
            mvn org.owasp:dependency-check-maven:check
        else
            # Update dependencies
            mvn versions:use-latest-versions
            
            # Run security check
            mvn org.owasp:dependency-check-maven:check
            
            # Commit changes
            mvn versions:commit
        fi
    fi
}

update_gradle_dependencies() {
    if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
        log "Updating Gradle dependencies..."
        
        if [ "$DRY_RUN" = "true" ]; then
            ./gradlew dependencyUpdates || true
            ./gradlew dependencyCheckAnalyze || true
        else
            # This requires the gradle-versions-plugin
            ./gradlew useLatestVersions
            
            # Run security check
            ./gradlew dependencyCheckAnalyze
        fi
    fi
}

update_go_dependencies() {
    if [ -f "go.mod" ]; then
        log "Updating Go dependencies..."
        
        if [ "$DRY_RUN" = "true" ]; then
            go list -u -m all || true
            nancy sleuth || true
        else
            # Update dependencies
            go get -u ./...
            go mod tidy
            
            # Security check (requires nancy)
            if command -v nancy &> /dev/null; then
                nancy sleuth
            fi
        fi
    fi
}

# Main execution
cd "$PROJECT_DIR"

log "Starting dependency update process..."
log "Project directory: $(pwd)"
log "Dry run: $DRY_RUN"

# Update dependencies based on what's available
update_npm_dependencies
update_python_dependencies
update_maven_dependencies
update_gradle_dependencies
update_go_dependencies

log "Dependency update process completed"

# Generate summary report
if [ "$DRY_RUN" = "false" ]; then
    log "Generating update summary..."
    
    cat > dependency-update-summary.md << EOF
# Dependency Update Summary

**Date**: $(date)
**Project**: $(basename $(pwd))

## Updated Files
$(git status --porcelain | grep -E '\.(json|txt|xml|gradle|mod)$' || echo "No dependency files changed")

## Security Scan Results
- Run \`npm audit\` for Node.js projects
- Run \`safety check\` for Python projects  
- Run \`mvn org.owasp:dependency-check-maven:check\` for Maven projects
- Run \`./gradlew dependencyCheckAnalyze\` for Gradle projects

## Next Steps
1. Test the application with updated dependencies
2. Run comprehensive security scan
3. Update container images if needed
4. Deploy to staging environment for testing
EOF

    log "Summary saved to: dependency-update-summary.md"
fi
```

## 🔄 Monitoring Scripts

### 5. Continuous Monitoring Script
```bash
#!/bin/bash
# continuous-monitor.sh
# Continuous monitoring of container security

set -e

CONFIG_FILE="${1:-./monitor-config.json}"
ALERT_THRESHOLD="${2:-HIGH}"

# Default configuration
cat > "$CONFIG_FILE" << 'EOF' 2>/dev/null || true
{
  "registries": [
    "us-central1-docker.pkg.dev/my-project/my-repo",
    "gcr.io/my-project"
  ],
  "images": [
    "my-app:latest",
    "my-api:latest",
    "my-worker:latest"
  ],
  "scan_interval": 3600,
  "alert_webhook": "",
  "report_email": "security-team@company.com"
}
EOF

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

send_alert() {
    local message="$1"
    local webhook_url="$2"
    
    if [ -n "$webhook_url" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\": \"$message\"}" \
            "$webhook_url"
    fi
}

monitor_image() {
    local image="$1"
    local registry="$2"
    local full_image="${registry}/${image}"
    
    log "Monitoring image: $full_image"
    
    # Create monitoring directory
    MONITOR_DIR="./monitoring/$(date +%Y%m%d)"
    mkdir -p "$MONITOR_DIR"
    
    # Run security scan
    SCAN_FILE="${MONITOR_DIR}/${image//\//_}_$(date +%H%M%S).json"
    
    trivy image --format json --output "$SCAN_FILE" "$full_image" 2>/dev/null || {
        log "WARNING: Failed to scan $full_image"
        return 1
    }
    
    # Analyze results
    CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$SCAN_FILE")
    HIGH_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$SCAN_FILE")
    
    log "  Critical: $CRITICAL_COUNT, High: $HIGH_COUNT"
    
    # Check alert threshold
    case "$ALERT_THRESHOLD" in
        "CRITICAL")
            if [ "$CRITICAL_COUNT" -gt 0 ]; then
                return 2  # Alert needed
            fi
            ;;
        "HIGH")
            if [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ]; then
                return 2  # Alert needed
            fi
            ;;
    esac
    
    return 0
}

# Main monitoring loop
log "Starting continuous security monitoring..."
log "Configuration: $CONFIG_FILE"
log "Alert threshold: $ALERT_THRESHOLD"

if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Read configuration
REGISTRIES=$(jq -r '.registries[]' "$CONFIG_FILE")
IMAGES=$(jq -r '.images[]' "$CONFIG_FILE")
SCAN_INTERVAL=$(jq -r '.scan_interval' "$CONFIG_FILE")
ALERT_WEBHOOK=$(jq -r '.alert_webhook' "$CONFIG_FILE")

while true; do
    log "Starting monitoring cycle..."
    
    ALERTS=()
    
    # Monitor each image in each registry
    for registry in $REGISTRIES; do
        for image in $IMAGES; do
            monitor_image "$image" "$registry"
            RESULT=$?
            
            if [ $RESULT -eq 2 ]; then
                ALERTS+=("$registry/$image")
            fi
        done
    done
    
    # Send alerts if any
    if [ ${#ALERTS[@]} -gt 0 ]; then
        ALERT_MESSAGE="🚨 Security Alert: High/Critical vulnerabilities found in: ${ALERTS[*]}"
        log "$ALERT_MESSAGE"
        send_alert "$ALERT_MESSAGE" "$ALERT_WEBHOOK"
    fi
    
    log "Monitoring cycle completed. Sleeping for $SCAN_INTERVAL seconds..."
    sleep "$SCAN_INTERVAL"
done
```

### 6. Report Generator
```python
#!/usr/bin/env python3
# generate-security-report.py
# Generate comprehensive security reports

import json
import glob
import argparse
import os
from datetime import datetime, timedelta
from pathlib import Path
import jinja2

class SecurityReportGenerator:
    def __init__(self, report_dir):
        self.report_dir = Path(report_dir)
        self.template_env = jinja2.Environment(
            loader=jinja2.DictLoader({
                'html_report': self.get_html_template(),
                'markdown_report': self.get_markdown_template()
            })
        )
    
    def get_html_template(self):
        return """
<!DOCTYPE html>
<html>
<head>
    <title>Container Security Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .metric { background: #e9ecef; padding: 15px; border-radius: 5px; text-align: center; }
        .critical { background: #dc3545; color: white; }
        .high { background: #fd7e14; color: white; }
        .medium { background: #ffc107; }
        .low { background: #28a745; color: white; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .vuln-critical { background-color: #f8d7da; }
        .vuln-high { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Container Security Report</h1>
        <p><strong>Generated:</strong> {{ report_date }}</p>
        <p><strong>Period:</strong> {{ start_date }} to {{ end_date }}</p>
    </div>
    
    <div class="summary">
        <div class="metric critical">
            <h3>{{ total_critical }}</h3>
            <p>Critical Vulnerabilities</p>
        </div>
        <div class="metric high">
            <h3>{{ total_high }}</h3>
            <p>High Vulnerabilities</p>
        </div>
        <div class="metric medium">
            <h3>{{ total_medium }}</h3>
            <p>Medium Vulnerabilities</p>
        </div>
        <div class="metric low">
            <h3>{{ total_low }}</h3>
            <p>Low Vulnerabilities</p>
        </div>
    </div>
    
    <h2>Image Risk Summary</h2>
    <table>
        <thead>
            <tr>
                <th>Image</th>
                <th>Risk Level</th>
                <th>Risk Score</th>
                <th>Critical</th>
                <th>High</th>
                <th>Medium</th>
                <th>Low</th>
                <th>Last Scan</th>
            </tr>
        </thead>
        <tbody>
            {% for image in images %}
            <tr class="{% if image.risk_level == 'CRITICAL' %}vuln-critical{% elif image.risk_level == 'HIGH' %}vuln-high{% endif %}">
                <td>{{ image.name }}</td>
                <td>{{ image.risk_level }}</td>
                <td>{{ image.risk_score }}</td>
                <td>{{ image.critical_count }}</td>
                <td>{{ image.high_count }}</td>
                <td>{{ image.medium_count }}</td>
                <td>{{ image.low_count }}</td>
                <td>{{ image.last_scan }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    
    <h2>Top Critical Vulnerabilities</h2>
    <table>
        <thead>
            <tr>
                <th>CVE ID</th>
                <th>Package</th>
                <th>Severity</th>
                <th>CVSS Score</th>
                <th>Fixed Version</th>
                <th>Affected Images</th>
            </tr>
        </thead>
        <tbody>
            {% for vuln in top_vulnerabilities %}
            <tr class="vuln-critical">
                <td>{{ vuln.id }}</td>
                <td>{{ vuln.package }}</td>
                <td>{{ vuln.severity }}</td>
                <td>{{ vuln.cvss_score }}</td>
                <td>{{ vuln.fixed_version or 'N/A' }}</td>
                <td>{{ vuln.affected_images | length }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    
    <h2>Recommendations</h2>
    <ul>
        {% for recommendation in recommendations %}
        <li>{{ recommendation }}</li>
        {% endfor %}
    </ul>
</body>
</html>
        """
    
    def get_markdown_template(self):
        return """
# Container Security Report

**Generated:** {{ report_date }}  
**Period:** {{ start_date }} to {{ end_date }}

## Summary

| Severity | Count |
|----------|-------|
| Critical | {{ total_critical }} |
| High     | {{ total_high }} |
| Medium   | {{ total_medium }} |
| Low      | {{ total_low }} |

## Image Risk Summary

| Image | Risk Level | Risk Score | Critical | High | Medium | Low | Last Scan |
|-------|------------|------------|----------|------|--------|-----|-----------|
{% for image in images -%}
| {{ image.name }} | {{ image.risk_level }} | {{ image.risk_score }} | {{ image.critical_count }} | {{ image.high_count }} | {{ image.medium_count }} | {{ image.low_count }} | {{ image.last_scan }} |
{% endfor %}

## Top Critical Vulnerabilities

| CVE ID | Package | Severity | CVSS Score | Fixed Version | Affected Images |
|--------|---------|----------|------------|---------------|-----------------|
{% for vuln in top_vulnerabilities -%}
| {{ vuln.id }} | {{ vuln.package }} | {{ vuln.severity }} | {{ vuln.cvss_score }} | {{ vuln.fixed_version or 'N/A' }} | {{ vuln.affected_images | length }} |
{% endfor %}

## Recommendations

{% for recommendation in recommendations -%}
- {{ recommendation }}
{% endfor %}
        """
    
    def collect_scan_data(self, days_back=7):
        """Collect scan data from the last N days"""
        cutoff_date = datetime.now() - timedelta(days=days_back)
        
        scan_files = []
        for pattern in ['*_trivy.json', '*_summary.json']:
            scan_files.extend(glob.glob(str(self.report_dir / '**' / pattern), recursive=True))
        
        # Filter by date
        recent_files = []
        for file_path in scan_files:
            file_stat = os.stat(file_path)
            if datetime.fromtimestamp(file_stat.st_mtime) > cutoff_date:
                recent_files.append(file_path)
        
        return recent_files
    
    def analyze_scan_files(self, scan_files):
        """Analyze scan files and extract metrics"""
        images = []
        all_vulnerabilities = []
        
        for file_path in scan_files:
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)
                
                if '_summary.json' in file_path:
                    # Process summary file
                    image_data = {
                        'name': data.get('image', 'Unknown'),
                        'risk_level': data.get('risk_level', 'UNKNOWN'),
                        'risk_score': data.get('risk_score', 0),
                        'critical_count': data.get('vulnerability_counts', {}).get('CRITICAL', 0),
                        'high_count': data.get('vulnerability_counts', {}).get('HIGH', 0),
                        'medium_count': data.get('vulnerability_counts', {}).get('MEDIUM', 0),
                        'low_count': data.get('vulnerability_counts', {}).get('LOW', 0),
                        'last_scan': data.get('scan_timestamp', 'Unknown')
                    }
                    images.append(image_data)
                
                elif '_trivy.json' in file_path:
                    # Process Trivy scan file
                    for result in data.get('Results', []):
                        for vuln in result.get('Vulnerabilities', []):
                            vuln['image'] = data.get('ArtifactName', 'Unknown')
                            all_vulnerabilities.append(vuln)
            
            except Exception as e:
                print(f"Error processing {file_path}: {e}")
        
        return images, all_vulnerabilities
    
    def generate_recommendations(self, images, vulnerabilities):
        """Generate security recommendations"""
        recommendations = []
        
        # Count high-risk images
        critical_images = [img for img in images if img['risk_level'] == 'CRITICAL']
        high_images = [img for img in images if img['risk_level'] == 'HIGH']
        
        if critical_images:
            recommendations.append(f"Immediately address {len(critical_images)} images with CRITICAL risk level")
        
        if high_images:
            recommendations.append(f"Schedule updates for {len(high_images)} images with HIGH risk level")
        
        # Analyze vulnerability patterns
        vuln_packages = {}
        for vuln in vulnerabilities:
            pkg = vuln.get('PkgName', 'Unknown')
            vuln_packages[pkg] = vuln_packages.get(pkg, 0) + 1
        
        # Top vulnerable packages
        top_packages = sorted(vuln_packages.items(), key=lambda x: x[1], reverse=True)[:5]
        if top_packages:
            recommendations.append(f"Focus on updating these frequently vulnerable packages: {', '.join([pkg for pkg, _ in top_packages])}")
        
        # Base image recommendations
        base_images = set()
        for img in images:
            if 'ubuntu:20.04' in img['name'] or 'ubuntu:18.04' in img['name']:
                base_images.add('Ubuntu')
            elif 'node:14' in img['name'] or 'node:16' in img['name']:
                base_images.add('Node.js')
        
        if base_images:
            recommendations.append(f"Consider updating base images for: {', '.join(base_images)}")
        
        recommendations.append("Implement automated dependency updates in CI/CD pipeline")
        recommendations.append("Set up continuous monitoring for new vulnerabilities")
        
        return recommendations
    
    def generate_report(self, format='html', days_back=7):
        """Generate security report"""
        scan_files = self.collect_scan_data(days_back)
        images, vulnerabilities = self.analyze_scan_files(scan_files)
        
        # Calculate totals
        total_critical = sum(img['critical_count'] for img in images)
        total_high = sum(img['high_count'] for img in images)
        total_medium = sum(img['medium_count'] for img in images)
        total_low = sum(img['low_count'] for img in images)
        
        # Get top vulnerabilities
        critical_vulns = [v for v in vulnerabilities if v.get('Severity') == 'CRITICAL']
        top_vulnerabilities = sorted(critical_vulns, key=lambda x: x.get('CVSS', {}).get('nvd', {}).get('V3Score', 0), reverse=True)[:10]
        
        # Format top vulnerabilities
        formatted_vulns = []
        for vuln in top_vulnerabilities:
            formatted_vulns.append({
                'id': vuln.get('VulnerabilityID', 'N/A'),
                'package': vuln.get('PkgName', 'N/A'),
                'severity': vuln.get('Severity', 'N/A'),
                'cvss_score': vuln.get('CVSS', {}).get('nvd', {}).get('V3Score', 'N/A'),
                'fixed_version': vuln.get('FixedVersion'),
                'affected_images': [vuln.get('image', 'Unknown')]
            })
        
        # Generate recommendations
        recommendations = self.generate_recommendations(images, vulnerabilities)
        
        # Prepare template data
        template_data = {
            'report_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'start_date': (datetime.now() - timedelta(days=days_back)).strftime('%Y-%m-%d'),
            'end_date': datetime.now().strftime('%Y-%m-%d'),
            'total_critical': total_critical,
            'total_high': total_high,
            'total_medium': total_medium,
            'total_low': total_low,
            'images': sorted(images, key=lambda x: x['risk_score'], reverse=True),
            'top_vulnerabilities': formatted_vulns,
            'recommendations': recommendations
        }
        
        # Generate report
        if format == 'html':
            template = self.template_env.get_template('html_report')
            return template.render(**template_data)
        else:
            template = self.template_env.get_template('markdown_report')
            return template.render(**template_data)

def main():
    parser = argparse.ArgumentParser(description='Generate container security report')
    parser.add_argument('--report-dir', default='./security-reports', help='Directory containing scan results')
    parser.add_argument('--format', choices=['html', 'markdown'], default='html', help='Report format')
    parser.add_argument('--days', type=int, default=7, help='Number of days to include in report')
    parser.add_argument('--output', help='Output file path')
    
    args = parser.parse_args()
    
    generator = SecurityReportGenerator(args.report_dir)
    report_content = generator.generate_report(args.format, args.days)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(report_content)
        print(f"Report saved to: {args.output}")
    else:
        print(report_content)

if __name__ == '__main__':
    main()
```

These automation scripts provide a comprehensive toolkit for detecting, analyzing, and fixing container security violations. They integrate with your existing tools and can be customized for your specific environment and requirements.