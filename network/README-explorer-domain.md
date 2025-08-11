# Domain Explorer Script

A comprehensive shell script for domain reconnaissance and analysis.

## Features

The `explorer-domain.sh` script provides extensive domain analysis including:

### 1. Basic Domain Information
- Domain format validation
- Clean domain extraction

### 2. DNS Resolution
- A Records (IPv4)
- AAAA Records (IPv6)
- CNAME Records
- MX Records (Mail Exchange)
- NS Records (Name Servers)
- TXT Records
- SOA Record (Start of Authority)
- Complete DNS information

### 3. IP Address Analysis
- Primary IP identification
- Reverse DNS lookup
- IP geolocation (using ipinfo.io)
- Traceroute analysis

### 4. Port Scanning
- Common ports scan (21,22,23,25,53,80,110,143,443,993,995,8080,8443)
- Service version detection
- OS detection (when available)

### 5. Web Server Analysis
- HTTP/HTTPS response headers
- Status codes and redirects
- Robots.txt check
- Sitemap.xml check

### 6. SSL/TLS Certificate Analysis
- Certificate details and chain
- Certificate expiry dates
- SSL cipher suites analysis

### 7. Domain Reputation & Security
- WHOIS information
- DNSSEC validation
- CAA records
- Security headers analysis (HSTS, CSP, X-Frame-Options, etc.)

### 8. Performance Analysis
- Ping tests
- Page load time metrics
- DNS lookup timing

### 9. Subdomain Enumeration
- Common subdomain discovery
- IP resolution for found subdomains

### 10. Additional Network Information
- Network routing information
- DNS propagation across multiple servers

### 11. Comprehensive Summary
- Complete analysis summary
- Report file generation

## Usage

```bash
# Make the script executable
chmod +x explorer-domain.sh

# Run the script
./explorer-domain.sh <domain>

# Examples
./explorer-domain.sh www.baidu.com
./explorer-domain.sh google.com
./explorer-domain.sh https://github.com
```

## Output

The script provides:
- **Colored console output** for easy reading
- **Detailed report file** saved as `domain_report_<domain>_<timestamp>.txt`
- **Progress indicators** and status messages
- **Error handling** with timeout protection

## Dependencies

The script automatically detects and uses available tools:

### Required (usually pre-installed):
- `dig` - DNS lookup utility
- `bash` - Shell interpreter

### Optional (enhances functionality):
- `nmap` - Network port scanner
- `curl` - HTTP client
- `openssl` - SSL/TLS toolkit
- `whois` - Domain registration lookup
- `ping` - Network connectivity test
- `traceroute` - Network path analysis
- `nc` (netcat) - Network utility

### Installation of optional tools:

**macOS (using Homebrew):**
```bash
brew install nmap curl openssl whois
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install nmap curl openssl whois iputils-ping traceroute netcat-openbsd
```

**CentOS/RHEL:**
```bash
sudo yum install nmap curl openssl whois iputils traceroute nc
```

## Sample Output

```
================================
DOMAIN EXPLORATION REPORT
================================
Domain: www.baidu.com
Timestamp: 2025-01-11 10:30:45
Report file: domain_report_www.baidu.com_20250111_103045.txt

================================
1. BASIC DOMAIN INFORMATION
================================
✓ Domain format is valid
Clean domain: www.baidu.com

================================
2. DNS RESOLUTION
================================

--- A Records (IPv4) ---
Running: IPv4 resolution
36.152.44.95
36.152.44.96
✓ IPv4 resolution completed

--- MX Records (Mail Exchange) ---
Running: MX records
10 mx.maillb.baidu.com.
10 mx1.baidu.com.
10 mx50.baidu.com.
✓ MX records completed

[... continues with detailed analysis ...]
```

## Security Considerations

- The script performs **passive reconnaissance** only
- **No intrusive scanning** or exploitation attempts
- Respects **rate limits** and timeouts
- Uses **publicly available information** only

## Troubleshooting

### Common Issues:

1. **Permission denied**: Make sure the script is executable
   ```bash
   chmod +x explorer-domain.sh
   ```

2. **Command not found**: Install missing dependencies
   ```bash
   # Check which tools are available
   which nmap curl openssl whois
   ```

3. **Timeout errors**: Some networks may block certain requests
   - The script includes timeout protection
   - Results may vary based on network configuration

4. **DNS resolution fails**: Check your internet connection and DNS settings

## Advanced Usage

### Custom timeout values:
The script uses reasonable timeouts, but you can modify them in the source code if needed.

### Batch processing:
```bash
# Process multiple domains
for domain in google.com facebook.com twitter.com; do
    ./explorer-domain.sh "$domain"
    sleep 5  # Be respectful to target servers
done
```

### Integration with other tools:
The generated report files can be processed by other security tools or imported into analysis frameworks.

## License

This script is provided as-is for educational and legitimate security testing purposes only. Users are responsible for complying with applicable laws and regulations.