# CI/CD Security Integration Guide

## 🎯 Overview

This guide shows how to integrate security scanning and violation detection into your CI/CD pipeline based on your existing tools and infrastructure.

## 🔧 Tool Integration Matrix

Based on your documentation, here's how to integrate your existing tools:

| Stage | Primary Tool | Secondary Tools | Action on Violation |
|-------|-------------|-----------------|-------------------|
| **Pre-commit** | Trivy | SonarLint | Warning/Block commit |
| **Pull Request** | SonarQube | Trivy, Checkmarx | Block merge |
| **Build** | Nexus IQ | Trivy | **Fail build** |
| **Container Registry** | Google Artifact Registry | - | Automatic scan |
| **Deployment** | Binary Authorization | GAR results | Block deployment |

## 🚀 Jenkins Pipeline Integration

### Complete Security Pipeline
```groovy
pipeline {
    agent any
    
    environment {
        IMAGE_NAME = "${env.JOB_NAME}:${env.BUILD_NUMBER}"
        GAR_REGISTRY = "us-central1-docker.pkg.dev/my-project/my-repo"
        NEXUS_IQ_SERVER = "http://nexus-iq-server:8070"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Pre-build Security Scan') {
            parallel {
                stage('Dependency Check') {
                    steps {
                        script {
                            // Nexus IQ scan for dependencies
                            def report = nexusPolicyEvaluation(
                                iqApplication: 'my-app',
                                iqStage: 'build',
                                iqServer: 'nexus-iq'
                            )
                            
                            if (report.policyEvaluationResult == 'FAILURE') {
                                error "Nexus IQ policy violation detected"
                            }
                        }
                    }
                }
                
                stage('Code Quality') {
                    steps {
                        script {
                            // SonarQube scan
                            def scannerHome = tool 'SonarQubeScanner'
                            withSonarQubeEnv('SonarQube') {
                                sh "${scannerHome}/bin/sonar-scanner"
                            }
                        }
                    }
                }
            }
        }
        
        stage('Build Application') {
            steps {
                sh 'mvn clean package'
            }
        }
        
        stage('Build Container') {
            steps {
                script {
                    // Build Docker image
                    def image = docker.build("${IMAGE_NAME}")
                    
                    // Scan image with Trivy
                    sh """
                        trivy image --exit-code 1 --severity HIGH,CRITICAL ${IMAGE_NAME}
                    """
                }
            }
        }
        
        stage('Push to Registry') {
            when {
                expression { currentBuild.result != 'FAILURE' }
            }
            steps {
                script {
                    docker.withRegistry("https://${GAR_REGISTRY}", 'gcr:my-project') {
                        def image = docker.image("${IMAGE_NAME}")
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }
        
        stage('Wait for GAR Scan') {
            steps {
                script {
                    // Wait for Google Artifact Registry scan to complete
                    sleep(time: 2, unit: 'MINUTES')
                    
                    // Check GAR scan results
                    sh """
                        gcloud artifacts docker images describe \\
                            ${GAR_REGISTRY}/${IMAGE_NAME} \\
                            --show-package-vulnerability \\
                            --format=json > gar-scan-results.json
                    """
                    
                    // Parse results and fail if critical vulnerabilities found
                    def scanResults = readJSON file: 'gar-scan-results.json'
                    def criticalVulns = scanResults.package_vulnerability?.vulnerabilities?.findAll { 
                        it.severity == 'CRITICAL' 
                    }
                    
                    if (criticalVulns && criticalVulns.size() > 0) {
                        error "Critical vulnerabilities found in container image"
                    }
                }
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
                expression { currentBuild.result != 'FAILURE' }
            }
            steps {
                script {
                    // Deploy with Binary Authorization
                    sh """
                        kubectl set image deployment/my-app \\
                            my-app=${GAR_REGISTRY}/${IMAGE_NAME}
                    """
                }
            }
        }
    }
    
    post {
        always {
            // Archive scan results
            archiveArtifacts artifacts: '*-scan-results.json', allowEmptyArchive: true
            
            // Generate security report
            sh 'python3 scripts/generate-security-report.py'
            publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'reports',
                reportFiles: 'security-report.html',
                reportName: 'Security Report'
            ])
        }
        
        failure {
            // Send alert on security failure
            slackSend(
                channel: '#security-alerts',
                color: 'danger',
                message: "Security scan failed for ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            )
        }
    }
}
```

## 🔄 GitHub Actions Integration

### Security Workflow
```yaml
name: Container Security Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: us-central1-docker.pkg.dev
  PROJECT_ID: my-project
  REPOSITORY: my-repo
  IMAGE_NAME: my-app

jobs:
  security-scan:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
    
    - name: Set up JDK 11
      uses: actions/setup-java@v3
      with:
        java-version: '11'
        distribution: 'temurin'
    
    - name: Cache Maven dependencies
      uses: actions/cache@v3
      with:
        path: ~/.m2
        key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}
    
    - name: Run Nexus IQ Scan
      run: |
        mvn clean package
        # Assuming Nexus IQ CLI is available
        nexus-iq-cli -s ${{ secrets.NEXUS_IQ_URL }} \
                     -a ${{ secrets.NEXUS_IQ_AUTH }} \
                     -i my-app \
                     scan target/*.jar
    
    - name: SonarQube Scan
      uses: sonarqube-quality-gate-action@master
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    
    - name: Build Docker image
      run: |
        docker build -t $IMAGE_NAME:$GITHUB_SHA .
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: '${{ env.IMAGE_NAME }}:${{ github.sha }}'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v2
      if: always()
      with:
        sarif_file: 'trivy-results.sarif'
    
    - name: Authenticate to Google Cloud
      if: github.ref == 'refs/heads/main'
      uses: google-github-actions/auth@v1
      with:
        credentials_json: ${{ secrets.GCP_SA_KEY }}
    
    - name: Configure Docker for GAR
      if: github.ref == 'refs/heads/main'
      run: |
        gcloud auth configure-docker $REGISTRY
    
    - name: Push to Google Artifact Registry
      if: github.ref == 'refs/heads/main'
      run: |
        docker tag $IMAGE_NAME:$GITHUB_SHA $REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:$GITHUB_SHA
        docker tag $IMAGE_NAME:$GITHUB_SHA $REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:latest
        docker push $REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:$GITHUB_SHA
        docker push $REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:latest
    
    - name: Wait and check GAR scan results
      if: github.ref == 'refs/heads/main'
      run: |
        sleep 120  # Wait for GAR scan to complete
        
        gcloud artifacts docker images describe \
          $REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:$GITHUB_SHA \
          --show-package-vulnerability \
          --format=json > gar-results.json
        
        # Check for critical vulnerabilities
        CRITICAL_COUNT=$(jq '[.package_vulnerability.vulnerabilities[]? | select(.severity=="CRITICAL")] | length' gar-results.json)
        
        if [ "$CRITICAL_COUNT" -gt 0 ]; then
          echo "❌ Found $CRITICAL_COUNT critical vulnerabilities"
          exit 1
        else
          echo "✅ No critical vulnerabilities found"
        fi

  deploy:
    needs: security-scan
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - name: Deploy to GKE
      run: |
        # Deploy with Binary Authorization enabled
        kubectl set image deployment/my-app \
          my-app=$REGISTRY/$PROJECT_ID/$REPOSITORY/$IMAGE_NAME:$GITHUB_SHA
```

## 🔍 Pre-commit Hooks

### Security Pre-commit Configuration
```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: trivy-scan
        name: Trivy security scan
        entry: bash -c 'if [ -f Dockerfile ]; then trivy config .; fi'
        language: system
        pass_filenames: false
        
      - id: dependency-check
        name: Dependency vulnerability check
        entry: bash -c 'if [ -f package.json ]; then npm audit --audit-level high; fi'
        language: system
        pass_filenames: false
        
      - id: dockerfile-lint
        name: Dockerfile security lint
        entry: hadolint
        language: system
        files: Dockerfile.*
        
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
```

### Installation Script
```bash
#!/bin/bash
# install-pre-commit-hooks.sh

# Install pre-commit
pip install pre-commit

# Install security tools
# Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Hadolint
wget -O /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
chmod +x /usr/local/bin/hadolint

# Install hooks
pre-commit install

echo "Pre-commit security hooks installed successfully!"
```

## 📊 Policy Configuration

### Nexus IQ Policy Example
```json
{
  "policyName": "Container Security Policy",
  "threatLevel": 7,
  "conditions": [
    {
      "conditionTypeId": "SecurityVulnerabilityCondition",
      "conditionIndex": 0,
      "conditionData": {
        "value": "7.0-10.0"
      }
    },
    {
      "conditionTypeId": "LicenseCondition", 
      "conditionIndex": 1,
      "conditionData": {
        "licenseIds": ["GPL-2.0", "GPL-3.0", "AGPL-3.0"]
      }
    }
  ],
  "actions": [
    {
      "actionTypeId": "Fail",
      "target": "build"
    }
  ]
}
```

### Binary Authorization Policy
```yaml
# binary-authorization-policy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: binary-authorization-policy
data:
  policy.yaml: |
    defaultAdmissionRule:
      requireAttestationsBy:
      - projects/PROJECT_ID/attestors/vulnerability-attestor
      evaluationMode: REQUIRE_ATTESTATION
      enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    
    clusterAdmissionRules:
      us-central1.my-cluster:
        requireAttestationsBy:
        - projects/PROJECT_ID/attestors/vulnerability-attestor
        evaluationMode: REQUIRE_ATTESTATION
        enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
```

## 🚨 Alert Configuration

### Slack Integration
```python
# slack-alerts.py
import json
import requests
import sys

def send_security_alert(webhook_url, scan_results):
    """Send security scan results to Slack"""
    
    critical_count = len([v for v in scan_results.get('vulnerabilities', []) 
                         if v.get('severity') == 'CRITICAL'])
    high_count = len([v for v in scan_results.get('vulnerabilities', []) 
                     if v.get('severity') == 'HIGH'])
    
    if critical_count > 0:
        color = "danger"
        message = f"🚨 CRITICAL: {critical_count} critical vulnerabilities found!"
    elif high_count > 5:
        color = "warning" 
        message = f"⚠️ WARNING: {high_count} high severity vulnerabilities found"
    else:
        color = "good"
        message = f"✅ Security scan passed with {high_count} high severity issues"
    
    payload = {
        "attachments": [
            {
                "color": color,
                "title": "Container Security Scan Results",
                "text": message,
                "fields": [
                    {
                        "title": "Critical",
                        "value": str(critical_count),
                        "short": True
                    },
                    {
                        "title": "High", 
                        "value": str(high_count),
                        "short": True
                    }
                ]
            }
        ]
    }
    
    response = requests.post(webhook_url, json=payload)
    return response.status_code == 200

if __name__ == "__main__":
    webhook_url = sys.argv[1]
    results_file = sys.argv[2]
    
    with open(results_file, 'r') as f:
        scan_results = json.load(f)
    
    send_security_alert(webhook_url, scan_results)
```

## 📈 Monitoring and Metrics

### Security Metrics Collection
```python
# security-metrics.py
import json
import time
from datetime import datetime
from google.cloud import monitoring_v3

class SecurityMetrics:
    def __init__(self, project_id):
        self.project_id = project_id
        self.client = monitoring_v3.MetricServiceClient()
        self.project_name = f"projects/{project_id}"
    
    def record_scan_metrics(self, scan_results):
        """Record security scan metrics to Cloud Monitoring"""
        
        # Count vulnerabilities by severity
        severity_counts = {}
        for vuln in scan_results.get('vulnerabilities', []):
            severity = vuln.get('severity', 'UNKNOWN')
            severity_counts[severity] = severity_counts.get(severity, 0) + 1
        
        # Create time series data
        now = time.time()
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/vulnerabilities"
        series.resource.type = "global"
        
        for severity, count in severity_counts.items():
            point = monitoring_v3.Point()
            point.value.int64_value = count
            point.interval.end_time.seconds = int(now)
            
            series.metric.labels["severity"] = severity
            series.points = [point]
            
            self.client.create_time_series(
                name=self.project_name,
                time_series=[series]
            )
    
    def record_build_result(self, success, scan_duration):
        """Record build success/failure metrics"""
        
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/build_results"
        series.resource.type = "global"
        
        point = monitoring_v3.Point()
        point.value.int64_value = 1 if success else 0
        point.interval.end_time.seconds = int(time.time())
        
        series.metric.labels["result"] = "success" if success else "failure"
        series.points = [point]
        
        self.client.create_time_series(
            name=self.project_name,
            time_series=[series]
        )

# Usage in CI/CD pipeline
if __name__ == "__main__":
    metrics = SecurityMetrics("my-project-id")
    
    # Load scan results
    with open("scan-results.json", "r") as f:
        results = json.load(f)
    
    metrics.record_scan_metrics(results)
    
    # Record build success (example)
    metrics.record_build_result(success=True, scan_duration=120)
```

## 🔄 Continuous Improvement

### Weekly Security Review Script
```bash
#!/bin/bash
# weekly-security-review.sh

echo "=== Weekly Security Review $(date) ==="

# Collect metrics from last week
START_DATE=$(date -d '7 days ago' '+%Y-%m-%d')
END_DATE=$(date '+%Y-%m-%d')

echo "Analyzing security scans from $START_DATE to $END_DATE"

# Query build failures due to security
SECURITY_FAILURES=$(grep -r "security scan failed" /var/log/jenkins/ | wc -l)
echo "Security-related build failures: $SECURITY_FAILURES"

# Top vulnerable images
echo "Top 5 images with most vulnerabilities:"
find /var/log/security-scans/ -name "*.json" -newer $(date -d '7 days ago' '+%Y-%m-%d') \
  -exec jq -r '.image + " " + (.vulnerabilities | length | tostring)' {} \; \
  | sort -k2 -nr | head -5

# Generate recommendations
echo "=== Recommendations ==="
echo "1. Update base images for top vulnerable containers"
echo "2. Review and update security policies"
echo "3. Schedule dependency updates for affected applications"

# Send report
mail -s "Weekly Security Review" security-team@company.com < weekly-report.txt
```

This comprehensive CI/CD integration guide provides you with the tools and processes needed to implement security scanning throughout your development pipeline, leveraging your existing tools like Nexus IQ, Google Artifact Registry, SonarQube, and Checkmarx.