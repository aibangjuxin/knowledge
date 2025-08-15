# Container Security Remediation Strategies

## 🎯 Remediation Approach Matrix

Based on your documentation and common violation scenarios, here's a systematic approach to fixing container security issues:

## 📊 Violation Categories & Solutions

### 1. Base Image Vulnerabilities

#### Problem: Ubuntu 20.04 with Known CVEs
As mentioned in `appd-violation.md`, using Ubuntu 20.04 as a base image can introduce security violations.

**Detection Commands:**
```bash
# Check current base image
docker history your-image:latest | head -5

# Scan base image specifically
trivy image ubuntu:20.04
```

**Remediation Options:**

**Option A: Upgrade Base Image**
```dockerfile
# ❌ Problematic
FROM ubuntu:20.04

# ✅ Better - Latest LTS
FROM ubuntu:22.04

# ✅ Best - Minimal variant
FROM ubuntu:22.04-slim
```

**Option B: Use Alpine Linux**
```dockerfile
# ✅ Minimal attack surface
FROM alpine:3.18

# Install required packages
RUN apk add --no-cache \
    ca-certificates \
    curl \
    && rm -rf /var/cache/apk/*
```

**Option C: Use Distroless Images**
```dockerfile
# Multi-stage build with distroless runtime
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y build-essential
COPY . /app
WORKDIR /app
RUN make build

FROM gcr.io/distroless/base-debian11
COPY --from=builder /app/binary /
ENTRYPOINT ["/binary"]
```

### 2. Package Manager Vulnerabilities

#### Problem: Outdated System Packages

**Detection:**
```bash
# Scan for OS package vulnerabilities
trivy image --scanners os your-image:latest
```

**Remediation:**
```dockerfile
# ❌ Problematic - No version pinning
RUN apt-get update && apt-get install -y curl

# ✅ Better - With cleanup
RUN apt-get update && \
    apt-get install -y curl=7.81.0-1ubuntu1.4 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ✅ Best - Multi-stage with minimal runtime
FROM ubuntu:22.04 AS installer
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM ubuntu:22.04-slim
COPY --from=installer /usr/bin/curl /usr/bin/curl
COPY --from=installer /usr/lib/x86_64-linux-gnu/libcurl* /usr/lib/x86_64-linux-gnu/
```

### 3. Application Dependencies

#### Problem: Vulnerable Node.js/Python/Java Dependencies

**Node.js Example:**
```dockerfile
# ❌ Problematic
FROM node:18
COPY package.json .
RUN npm install

# ✅ Better
FROM node:18-alpine
COPY package*.json ./
RUN npm ci --only=production && \
    npm audit fix --audit-level=high && \
    npm cache clean --force

# ✅ Best - Multi-stage with security scanning
FROM node:18-alpine AS deps
COPY package*.json ./
RUN npm ci --only=production && \
    npm audit fix --audit-level=high

FROM node:18-alpine AS scanner
COPY --from=deps /node_modules ./node_modules
COPY package*.json ./
RUN npx audit-ci --moderate

FROM node:18-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001
COPY --from=deps --chown=nextjs:nodejs /node_modules ./node_modules
COPY --chown=nextjs:nodejs . .
USER nextjs
```

**Python Example:**
```dockerfile
# ❌ Problematic
FROM python:3.9
COPY requirements.txt .
RUN pip install -r requirements.txt

# ✅ Better
FROM python:3.9-slim
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip check

# ✅ Best - With security scanning
FROM python:3.9-slim AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install safety && \
    safety check

FROM python:3.9-slim AS runtime
RUN adduser --disabled-password --gecos '' appuser
COPY --from=deps /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY --chown=appuser:appuser . /app
WORKDIR /app
USER appuser
```

### 4. Init Container Violations

Based on `appd-violation.md`, init containers with vulnerable base images can cause compliance issues.

**Problem: AppDynamics Init Container with Ubuntu 20.04**
```yaml
# ❌ Problematic init container
initContainers:
- name: appd-init
  image: your-registry/appd-init:ubuntu20.04
  command: ["cp", "-r", "/opt/appdynamics/.", "/opt/appdynamics-java"]
```

**Solution A: Rebuild with Secure Base Image**
```dockerfile
# New AppD init container Dockerfile
FROM ubuntu:22.04-slim AS appd-base
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM appd-base
COPY appdynamics/ /opt/appdynamics/
RUN chmod +x /opt/appdynamics/bin/*
CMD ["cp", "-r", "/opt/appdynamics/.", "/opt/appdynamics-java"]
```

**Solution B: Use Distroless for Init Container**
```dockerfile
FROM gcr.io/distroless/base-debian11
COPY appdynamics/ /opt/appdynamics/
CMD ["cp", "-r", "/opt/appdynamics/.", "/opt/appdynamics-java"]
```

## 🔧 Automated Remediation Scripts

### 1. Base Image Update Script
```bash
#!/bin/bash
# update-base-images.sh

# Define image mappings
declare -A IMAGE_UPDATES=(
    ["ubuntu:20.04"]="ubuntu:22.04-slim"
    ["node:16"]="node:18-alpine"
    ["python:3.8"]="python:3.11-slim"
)

# Find and update Dockerfiles
find . -name "Dockerfile*" -type f | while read dockerfile; do
    echo "Processing $dockerfile..."
    
    for old_image in "${!IMAGE_UPDATES[@]}"; do
        new_image="${IMAGE_UPDATES[$old_image]}"
        
        if grep -q "FROM $old_image" "$dockerfile"; then
            echo "  Updating $old_image -> $new_image"
            sed -i.bak "s|FROM $old_image|FROM $new_image|g" "$dockerfile"
        fi
    done
done
```

### 2. Dependency Update Script
```bash
#!/bin/bash
# update-dependencies.sh

# Update Node.js dependencies
if [ -f "package.json" ]; then
    echo "Updating Node.js dependencies..."
    npm audit fix --audit-level=high
    npm update
fi

# Update Python dependencies
if [ -f "requirements.txt" ]; then
    echo "Updating Python dependencies..."
    pip-review --local --auto
    safety check
fi

# Update Maven dependencies
if [ -f "pom.xml" ]; then
    echo "Updating Maven dependencies..."
    mvn versions:use-latest-versions
    mvn org.owasp:dependency-check-maven:check
fi
```

### 3. Multi-Stage Dockerfile Generator
```python
#!/usr/bin/env python3
# generate-secure-dockerfile.py

import sys
import os

def generate_nodejs_dockerfile(app_name):
    return f"""# Multi-stage secure Node.js Dockerfile for {app_name}
FROM node:18-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && \\
    npm audit fix --audit-level=high && \\
    npm cache clean --force

FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:18-alpine AS runtime
RUN addgroup -g 1001 -S nodejs && \\
    adduser -S {app_name} -u 1001

WORKDIR /app
COPY --from=deps --chown={app_name}:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown={app_name}:nodejs /app/dist ./dist
COPY --chown={app_name}:nodejs package.json ./

USER {app_name}
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
"""

def generate_python_dockerfile(app_name):
    return f"""# Multi-stage secure Python Dockerfile for {app_name}
FROM python:3.11-slim AS deps
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \\
    pip install safety && \\
    safety check

FROM python:3.11-slim AS runtime
RUN adduser --disabled-password --gecos '' {app_name}

WORKDIR /app
COPY --from=deps /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY --chown={app_name}:{app_name} . .

USER {app_name}
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["python", "app.py"]
"""

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 generate-secure-dockerfile.py <language> <app_name>")
        sys.exit(1)
    
    language = sys.argv[1].lower()
    app_name = sys.argv[2]
    
    if language == "nodejs":
        dockerfile_content = generate_nodejs_dockerfile(app_name)
    elif language == "python":
        dockerfile_content = generate_python_dockerfile(app_name)
    else:
        print(f"Unsupported language: {language}")
        sys.exit(1)
    
    with open("Dockerfile.secure", "w") as f:
        f.write(dockerfile_content)
    
    print(f"Generated secure Dockerfile for {language} application: {app_name}")
```

## 🔄 Remediation Workflow

### 1. Immediate Response (Critical Vulnerabilities)
```bash
#!/bin/bash
# emergency-patch.sh

CRITICAL_IMAGES=$(trivy image --format json your-registry/app:latest | jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | .PkgName' | sort -u)

if [ ! -z "$CRITICAL_IMAGES" ]; then
    echo "CRITICAL vulnerabilities found. Initiating emergency patch..."
    
    # Create hotfix branch
    git checkout -b hotfix/security-$(date +%Y%m%d)
    
    # Apply automated fixes
    ./update-base-images.sh
    ./update-dependencies.sh
    
    # Rebuild and test
    docker build -t temp-fix .
    trivy image --exit-code 1 --severity CRITICAL temp-fix
    
    if [ $? -eq 0 ]; then
        echo "Critical vulnerabilities resolved. Creating PR..."
        git add .
        git commit -m "Security hotfix: Resolve critical vulnerabilities"
        git push origin hotfix/security-$(date +%Y%m%d)
    fi
fi
```

### 2. Scheduled Maintenance (Regular Updates)
```bash
#!/bin/bash
# scheduled-maintenance.sh

# Run weekly via cron
echo "Starting scheduled security maintenance..."

# Update base images
./update-base-images.sh

# Update dependencies
./update-dependencies.sh

# Run comprehensive scan
trivy image --format json --output security-report-$(date +%Y%m%d).json your-registry/app:latest

# Generate remediation report
python3 generate-remediation-report.py security-report-$(date +%Y%m%d).json

# Create maintenance PR if changes detected
if [ -n "$(git status --porcelain)" ]; then
    git checkout -b maintenance/security-$(date +%Y%m%d)
    git add .
    git commit -m "Scheduled security maintenance: Update dependencies and base images"
    git push origin maintenance/security-$(date +%Y%m%d)
fi
```

## 📋 Remediation Checklist

### Pre-Remediation
- [ ] Identify all affected images/containers
- [ ] Assess business impact of changes
- [ ] Create backup/rollback plan
- [ ] Set up test environment

### During Remediation
- [ ] Update base images to latest secure versions
- [ ] Update application dependencies
- [ ] Implement multi-stage builds where applicable
- [ ] Add security scanning to CI/CD pipeline
- [ ] Configure non-root user execution

### Post-Remediation
- [ ] Run comprehensive security scan
- [ ] Verify application functionality
- [ ] Update documentation
- [ ] Monitor for new vulnerabilities
- [ ] Schedule regular maintenance

## 🎯 Success Metrics

### Key Performance Indicators
1. **Vulnerability Reduction Rate**: % decrease in total vulnerabilities
2. **Critical Vulnerability TTR**: Time to resolve critical issues
3. **Build Success Rate**: % of builds passing security gates
4. **Compliance Score**: % of images meeting security policies
5. **Automation Coverage**: % of remediation tasks automated

### Monitoring Dashboard
```yaml
# Example Grafana dashboard configuration
dashboard:
  title: "Container Security Remediation"
  panels:
    - title: "Vulnerability Trends"
      type: "graph"
      targets:
        - expr: "container_vulnerabilities_total"
    
    - title: "Remediation Time"
      type: "stat"
      targets:
        - expr: "avg(vulnerability_resolution_time_hours)"
    
    - title: "Policy Compliance"
      type: "gauge"
      targets:
        - expr: "container_policy_compliance_percentage"
```