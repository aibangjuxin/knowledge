

# DNS Batch Update Tool

A script to batch add or update DNS records using your API.

## Files

- `dns-batch-update.sh` - Main script for batch DNS operations
- `dns-config.sh` - Configuration file for different environments
- `dns_records_sample.txt` - Sample DNS records file showing the expected format
- `README.md` - This documentation

## Usage

### Basic Usage

```bash
# Add DNS records from a file
./dns-batch-update.sh dns_records.txt add

# Update existing DNS records
./dns-batch-update.sh dns_records.txt update
```

### Environment-specific Usage

```bash
# Use development environment
DNS_ENV=development ./dns-batch-update.sh dns_records.txt add

# Use staging environment
DNS_ENV=staging ./dns-batch-update.sh dns_records.txt update
```

## DNS Records File Format

Create a text file with one DNS record per line in the format:
```
record_name record_value
```

Example:
```
# Comments start with #
web01 192.168.1.10
api 192.168.1.20



# Knowledge Base Repository

This repository contains infrastructure configurations and automation tools for DNS management and Kubernetes deployments.

## Directory Structure

### `/ali/ali-dns/` - DNS Management Tools
Automated DNS record management for Alibaba Cloud DNS services.

**Key Files:**
- `dns-batch-update.sh` - Main script for batch DNS operations
- `dns-config.sh` - Environment configuration management
- `dns_records_sample.txt` - Example DNS records format
- `ali-dns-create-and-update.md` - API documentation

**Quick Usage:**
```bash
cd ali/ali-dns
./dns-batch-update.sh dns_records.txt add
```

### `/nginx/ingress-control/` - Kubernetes Ingress Configuration
Kubernetes ingress controller setup and DNS mapping configurations.

**Key Files:**
- `deploy.yaml` - Ingress controller deployment
- `coredns-custom.yaml` - Custom CoreDNS configuration
- `dns-mapping.yaml` - Service DNS mappings
- `k3s-install.md` - K3s installation guide

## DNS Batch Update Tool

### Overview
The DNS batch update tool allows you to manage DNS records in bulk by reading from a simple text file format. It supports both adding new records and updating existing ones across different environments.

### Features
- ✅ Batch processing from text files
- ✅ Multi-environment support (dev/staging/prod)
- ✅ Add and update operations
- ✅ Colored output and error handling
- ✅ Rate limiting for API protection
- ✅ Comment support in record files

### Quick Start

1. **Navigate to the DNS tools directory:**
   ```bash
   cd ali/ali-dns
   ```

2. **Configure your environment (edit `dns-config.sh`):**
   ```bash
   # Update API endpoints and tokens
   export DNS_API_BASE_URL="https://your-domain/api/v1"
   export DNS_TOKEN="your-api-token"
   export DNS_DOMAIN_NAME="your.domain.com"
   ```

3. **Create a DNS records file:**
   ```bash
   # Format: record_name record_value
   web01 192.168.1.10
   api 192.168.1.20
   db01 192.168.1.30
   ```

4. **Run the script:**
   ```bash
   # Add new records
   ./dns-batch-update.sh my_records.txt add
   
   # Update existing records
   ./dns-batch-update.sh my_records.txt update
   
   # Use different environment
   DNS_ENV=development ./dns-batch-update.sh my_records.txt add
   ```

### DNS Records File Format

Create a text file with one record per line:
```
# Comments start with #
record_name record_value

# Examples:
web01 192.168.1.10
web02 192.168.1.11
api-prod 192.168.1.20
db-master 192.168.1.30
```

### Environment Configuration

The tool supports multiple environments through the `DNS_ENV` variable:

- **Production** (default): Uses main API endpoints
- **Development**: `DNS_ENV=development`
- **Staging**: `DNS_ENV=staging`

### API Integration

The script works with REST APIs that support:
- `POST /api/v1/add-global-zone-record` - Add new DNS records
- `POST /api/v1/update-global-zone-record` - Update existing records

Each record creates: `record_name.domain_name -> record_value`

### Examples

**Basic usage:**
```bash
./dns-batch-update.sh production_servers.txt add
```

**Development environment:**
```bash
DNS_ENV=development ./dns-batch-update.sh dev_servers.txt add
```

**Update existing records:**
```bash
./dns-batch-update.sh updated_ips.txt update
```

## Kubernetes Ingress Setup

The `/nginx/ingress-control/` directory contains configurations for:
- Nginx ingress controller deployment
- Custom CoreDNS configurations for internal DNS resolution
- Service mappings for external name resolution
- K3s cluster setup instructions

## Getting Started

1. Clone this repository
2. Navigate to the appropriate directory for your task
3. Follow the specific README instructions in each subdirectory
4. Configure environment variables as needed
5. Run the automation scripts

## Support

For DNS management issues, check the API documentation in `ali/ali-dns/ali-dns-create-and-update.md`.
For Kubernetes issues, refer to the deployment configurations in `nginx/ingress-control/`.