# DNS Verification Tool - Docker Service

This directory contains the source code to run the **Internal DNS Verification Tool** as a Docker container.
This allows the team to run the tool without manually installing Python or configuring scripts.

## Prerequisites
- [Docker](https://www.docker.com/) installed on your machine.

## Quick Start

### 1. Build the Image
Navigate to this directory and run:
```bash
docker build -t dns-verify-tool .
```

### 2. Run the Service
Run the container, mapping port 8000:
```bash
docker run -d -p 8000:8000 --name dns-tool dns-verify-tool
```

### 3. Access the Tool
Open your browser to:
[http://localhost:8000/Intra-verify-domain.html](http://localhost:8000/Intra-verify-domain.html)

## Sharing with the Team

### Option A: Share Source Code
Simply share this directory (Git repo). Members run `docker build` themselves.

### Option B: Share Image (Registry)
1. Tag the image:
   ```bash
   docker tag dns-verify-tool my-registry.com/team-sre/dns-verify-tool:v1
   ```
2. Push to your internal registry:
   ```bash
   docker push my-registry.com/team-sre/dns-verify-tool:v1
   ```
3. Team members run:
   ```bash
   docker run -p 8000:8000 my-registry.com/team-sre/dns-verify-tool:v1
   ```

## Troubleshooting
**Issue**: Tool says "Query Failed" or "Private" IPs are not resolving.

**Cause**: Docker runs in its own network namespace. By default, it uses the host's DNS settings, but VPNs can sometimes interfere.

**Fix**: Try running with host networking (Linux only) or specify DNS servers:
```bash
docker run -p 8000:8000 --dns 10.0.0.1 dns-verify-tool
```
