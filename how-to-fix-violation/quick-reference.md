# Container Security Quick Reference

## 🚀 Emergency Response Commands

### Immediate Threat Assessment
```bash
# Quick vulnerability scan
trivy image --severity HIGH,CRITICAL your-image:latest

# Check running containers in Kubernetes
kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u | xargs -I {} trivy image --severity CRITICAL {}

# Google Artifact Registry scan
gcloud artifacts docker images describe \
  us-central1-docker.pkg.dev/project/repo/image@digest \
  --show-package-vulnerability \
  --format="table(package_vulnerability.vulnerabilities[].severity)"
```

### Critical Vulnerability Response
```bash
# 1. Identify affected images
trivy image --format json your-image:latest | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL") | .VulnerabilityID'

# 2. Check if vulnerability is exploitable
trivy image --format json your-image:latest | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL") | {id: .VulnerabilityID, package: .PkgName, fixed: .FixedVersion}'

# 3. Emergency patch (if available)
docker build --build-arg BASE_IMAGE=ubuntu:22.04-slim -t patched-image .
trivy image --severity CRITICAL patched-image
```

## 🔍 Detection Commands by Tool

### Trivy
```bash
# Basic image scan
trivy image nginx:latest

# Scan with specific severities
trivy image --severity HIGH,CRITICAL nginx:latest

# Generate SBOM
trivy image --format cyclonedx nginx:latest

# Scan filesystem
trivy fs --scanners vuln ./project

# Configuration scan
trivy config ./k8s-manifests/

# Exit with error on findings
trivy image --exit-code 1 --severity HIGH,CRITICAL nginx:latest
```

### Google Artifact Registry
```bash
# List vulnerabilities
gcloud artifacts docker images list-vulnerabilities \
  --project=PROJECT_ID \
  --location=LOCATION \
  --repository=REPO \
  --image=IMAGE

# Describe with vulnerabilities
gcloud artifacts docker images describe IMAGE_URL \
  --show-package-vulnerability \
  --format=json

# Get SBOM
gcloud artifacts sbom list \
  --package="LOCATION-docker.pkg.dev/PROJECT/REPO/IMAGE@DIGEST" \
  --format=json
```

### Nexus IQ
```bash
# Maven scan
mvn clean package clm:evaluate

# CLI scan
nexus-iq-cli -s http://nexus-iq:8070 -i app-id scan target/app.jar

# Jenkins integration
nexusPolicyEvaluation iqApplication: 'app-id', iqStage: 'build'
```

### Syft + Grype
```bash
# Generate SBOM
syft nginx:latest -o cyclonedx-json > sbom.json

# Scan SBOM
grype sbom:sbom.json

# Direct image scan
grype nginx:latest

# Output formats
grype nginx:latest -o json
grype nginx:latest -o table
```

## 🛠 Quick Fixes

### Base Image Updates
```dockerfile
# ❌ Vulnerable
FROM ubuntu:20.04
FROM node:16
FROM python:3.8

# ✅ Secure
FROM ubuntu:22.04-slim
FROM node:18-alpine
FROM python:3.11-slim
```

### Multi-stage Build Template
```dockerfile
# Build stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage
FROM node:18-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001
WORKDIR /app
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --chown=nextjs:nodejs . .
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```

### Secure Package Installation
```dockerfile
# Ubuntu/Debian
RUN apt-get update && \
    apt-get install -y --no-install-recommends package-name && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Alpine
RUN apk add --no-cache package-name

# Node.js
RUN npm ci --only=production && \
    npm audit fix --audit-level=high && \
    npm cache clean --force
```

## 📊 Risk Assessment Matrix

| Severity | CVSS Score | Action Required | Timeline |
|----------|------------|-----------------|----------|
| CRITICAL | 9.0-10.0 | Immediate patch/rebuild | < 24 hours |
| HIGH | 7.0-8.9 | Schedule urgent fix | < 7 days |
| MEDIUM | 4.0-6.9 | Plan for next release | < 30 days |
| LOW | 0.1-3.9 | Monitor and batch fix | Next maintenance |

## 🚨 Alert Thresholds

### Build Pipeline Gates
```yaml
# Fail build conditions
critical_vulnerabilities: 0
high_vulnerabilities: 5
policy_violations: 0
license_violations: 0
```

### Production Monitoring
```yaml
# Alert conditions
critical_in_production: 0
high_in_production: 10
new_cve_affecting_prod: immediate
compliance_violation: immediate
```

## 🔄 CI/CD Integration Snippets

### Jenkins Pipeline Stage
```groovy
stage('Security Scan') {
    parallel {
        stage('Trivy') {
            steps {
                sh 'trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE'
            }
        }
        stage('Nexus IQ') {
            steps {
                nexusPolicyEvaluation iqApplication: 'app', iqStage: 'build'
            }
        }
    }
}
```

### GitHub Actions
```yaml
- name: Run Trivy scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: '${{ env.IMAGE_NAME }}'
    format: 'sarif'
    output: 'trivy-results.sarif'
    exit-code: '1'
    severity: 'CRITICAL,HIGH'
```

### GitLab CI
```yaml
security_scan:
  stage: test
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  allow_failure: false
```

## 📋 Compliance Checklists

### Container Security Checklist
- [ ] Use specific version tags (not `latest`)
- [ ] Run as non-root user
- [ ] Use minimal base images (Alpine, Distroless)
- [ ] Multi-stage builds for smaller attack surface
- [ ] No secrets in images
- [ ] Regular base image updates
- [ ] Vulnerability scanning in CI/CD
- [ ] Runtime security monitoring

### Kubernetes Security Checklist
- [ ] Pod Security Standards enabled
- [ ] Network policies configured
- [ ] RBAC properly configured
- [ ] Secrets management (not in env vars)
- [ ] Resource limits set
- [ ] Security contexts configured
- [ ] Admission controllers enabled
- [ ] Regular security audits

## 🔧 Troubleshooting

### Common Issues

**Trivy scan fails with network error**
```bash
# Use different registry
trivy image --insecure registry.local/image:tag

# Skip DB update
trivy image --skip-update image:tag
```

**GAR scan not showing results**
```bash
# Check if Container Analysis API is enabled
gcloud services list --enabled | grep containeranalysis

# Enable if needed
gcloud services enable containeranalysis.googleapis.com
```

**Nexus IQ connection issues**
```bash
# Test connection
curl -u admin:password http://nexus-iq:8070/api/v2/applications

# Check Jenkins plugin configuration
# Verify credentials and server URL
```

**False positives in scans**
```bash
# Trivy: Use .trivyignore file
echo "CVE-2023-12345" > .trivyignore

# Grype: Use .grype.yaml config
cat > .grype.yaml << EOF
ignore:
  - vulnerability: "CVE-2023-12345"
    fix-state: "not-fixed"
EOF
```

## 📞 Emergency Contacts

### Security Incident Response
- **Security Team**: security-team@company.com
- **On-call Engineer**: +1-555-SECURITY
- **Slack Channel**: #security-incidents

### Tool Support
- **Nexus IQ**: nexus-support@company.com
- **Infrastructure**: infra-team@company.com
- **DevOps**: devops@company.com

## 📚 Additional Resources

### Documentation Links
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Google Container Analysis](https://cloud.google.com/container-analysis/docs)
- [Sonatype Nexus IQ](https://help.sonatype.com/iqserver)
- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

### Security Databases
- [National Vulnerability Database](https://nvd.nist.gov/)
- [CVE Details](https://www.cvedetails.com/)
- [Snyk Vulnerability Database](https://snyk.io/vuln/)
- [GitHub Security Advisories](https://github.com/advisories)

### Best Practices
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Container Security](https://owasp.org/www-project-container-security/)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)

---

**Last Updated**: $(date)  
**Version**: 1.0  
**Maintained by**: Security Team