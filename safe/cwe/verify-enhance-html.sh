#!/usr/bin/env python3
"""
CVE Vulnerability Verification Script
Uses BeautifulSoup for robust HTML parsing, far superior to sed/grep.

Dependencies: python3 (built-in), beautifulsoup4, requests
Install: pip3 install beautifulsoup4 requests

Usage:
    python3 verify-enhance-html.sh CVE-2026-31431
"""

import sys
import re
import json
import argparse
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# Check for requests
try:
    import requests
except ImportError:
    requests = None

# Check for beautifulsoup4
try:
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: beautifulsoup4 not installed")
    print("Run: pip3 install beautifulsoup4 requests")
    sys.exit(1)


# ─── Color output ────────────────────────────────────────────────
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    NC = '\033[0m'


def info(msg):
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {msg}")


def warn(msg):
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")


def error(msg):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")


def success(msg):
    print(f"{Colors.GREEN}[OK]{Colors.NC} {msg}")


def section(title):
    print(f"\n{Colors.BOLD}{'=' * 56}{Colors.NC}")
    print(f"{Colors.BOLD}  {title}{Colors.NC}")
    print(f"{Colors.BOLD}{'=' * 56}{Colors.NC}")


def subsection(title):
    print(f"\n{Colors.BLUE}==> {title}{Colors.NC}")
    print(f"{Colors.BLUE}{'-' * 50}{Colors.NC}")


# ─── HTTP requests ───────────────────────────────────────────────
def fetch_url(url, headers=None, json_mode=False):
    """Generic URL fetcher with timeout"""
    default_headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json' if json_mode else 'text/html,application/xhtml+xml',
    }
    if headers:
        default_headers.update(headers)

    try:
        if requests:
            r = requests.get(url, headers=default_headers, timeout=30, allow_redirects=True)
            r.raise_for_status()
            return r.text
        else:
            req = Request(url, headers=default_headers)
            with urlopen(req, timeout=30) as resp:
                return resp.read().decode('utf-8')
    except HTTPError as e:
        if e.code == 404:
            return None
        raise
    except Exception as e:
        raise


# ─── NVD API parsing ────────────────────────────────────────────
def parse_nvd(cve_id):
    """Fetch CVE data from NVD API"""
    subsection("NVD (National Vulnerability Database)")

    url = f"https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={cve_id}"

    try:
        data_str = fetch_url(url, headers={'Accept': 'application/json'}, json_mode=True)
        if not data_str:
            warn(f"NVD API returned no data for: {cve_id}")
            return {}

        data = json.loads(data_str)
        vulns = data.get('vulnerabilities', [])

        if not vulns:
            warn(f"{cve_id} not found in NVD")
            return {}

        item = vulns[0].get('cve', {})

        # Extract description
        descriptions = item.get('descriptions', [])
        description_en = next(
            (d['value'] for d in descriptions if d.get('lang') == 'en'),
            None
        )

        # Extract CVSS
        metrics = item.get('metrics', {})
        cvss_v31 = metrics.get('cvssMetricV31', [])
        cvss_v30 = metrics.get('cvssMetricV30', [])
        cvss_v2 = metrics.get('cvssMetricV2', [])

        cvss_data = None
        cvss_version = None
        base_score = None
        base_severity = None
        vector_string = None

        if cvss_v31:
            cvss_data = cvss_v31[0].get('cvssData', {})
            cvss_version = '3.1'
        elif cvss_v30:
            cvss_data = cvss_v30[0].get('cvssData', {})
            cvss_version = '3.0'
        elif cvss_v2:
            cvss_data = cvss_v2[0].get('cvssData', {})
            cvss_version = '2.0'

        if cvss_data:
            base_score = cvss_data.get('baseScore')
            base_severity = cvss_data.get('baseSeverity') or cvss_data.get('baseSeverity')
            vector_string = cvss_data.get('vectorString')

        # Extract CWE
        weaknesses = item.get('weaknesses', [])
        cwe_id = None
        for w in weaknesses:
            for desc in w.get('description', []):
                val = desc.get('value', '')
                if val.startswith('CWE-'):
                    cwe_id = val
                    break

        # Extract references
        references = item.get('references', [])[:8]
        ref_urls = [r['url'] for r in references]

        # Status
        vuln_status = item.get('vulnStatus', 'Unknown')
        published = item.get('published', '')[:10]
        last_modified = item.get('lastModified', '')[:10]

        # Print results
        print(f"  CVE ID:       {Colors.BOLD}{cve_id}{Colors.NC}")

        if base_score is not None:
            severity_color = Colors.RED if base_score >= 7 else Colors.YELLOW if base_score >= 4 else Colors.GREEN
            print(f"  CVSS {cvss_version} Score: {Colors.BOLD}{severity_color}{base_score}{Colors.NC} ({base_severity or 'N/A'})")
            if vector_string:
                print(f"  Vector:       {vector_string}")
        else:
            print(f"  CVSS Score:   {Colors.YELLOW}Unknown{Colors.NC}")

        print(f"  Status:       {vuln_status}")
        print(f"  Published:    {published}")
        print(f"  Modified:     {last_modified}")

        if description_en:
            print(f"\n  {Colors.BOLD}Description:{Colors.NC}")
            for i in range(0, len(description_en), 70):
                print(f"    {description_en[i:i+70]}")

        if cwe_id:
            print(f"\n  CWE:          {Colors.CYAN}{cwe_id}{Colors.NC}")

        if ref_urls:
            print(f"\n  {Colors.BOLD}References (top 5):{Colors.NC}")
            for ref in ref_urls[:5]:
                print(f"    {Colors.CYAN}{ref}{Colors.NC}")

        success(f"NVD data fetched successfully")
        return {
            'cve_id': cve_id,
            'base_score': base_score,
            'base_severity': base_severity,
            'cvss_version': cvss_version,
            'vector_string': vector_string,
            'description': description_en,
            'cwe_id': cwe_id,
            'status': vuln_status,
            'published': published,
            'references': ref_urls,
        }

    except json.JSONDecodeError:
        warn("NVD API returned invalid JSON — possible rate limit")
        return {}
    except Exception as e:
        warn(f"NVD request failed: {e}")
        return {}


# ─── MITRE CVE page parsing ──────────────────────────────────────
def parse_mitre(cve_id):
    """Parse MITRE CVE detail page"""
    subsection("MITRE CVE Record")

    url = f"https://www.cve.org/CVERecord?id={cve_id}"

    try:
        html = fetch_url(url)
        if not html:
            warn(f"{cve_id} not found on MITRE")
            return {}

        soup = BeautifulSoup(html, 'html.parser')

        # Extract title/description
        description = None
        desc_elem = soup.select_one('meta[name="description"]')
        if desc_elem:
            description = desc_elem.get('content', '')

        if not description:
            desc_div = soup.find('meta', {'property': 'og:description'})
            if desc_div:
                description = desc_div.get('content', '')

        # Extract CVE title
        title = None
        h1 = soup.find('h1')
        if h1:
            title = h1.get_text(strip=True)

        print(f"  CVE ID:  {Colors.BOLD}{cve_id}{Colors.NC}")
        if title and title != cve_id:
            print(f"  Title:   {title}")

        if description:
            print(f"\n  {Colors.BOLD}Description:{Colors.NC}")
            for i in range(0, len(description), 70):
                print(f"    {description[i:i+70]}")

        # Extract CNA info
        cna_elem = soup.find('cna')
        if cna_elem:
            cna = cna_elem.get('org', '')
            print(f"  CNA:     {Colors.CYAN}{cna}{Colors.NC}")

        success(f"MITRE page parsed successfully")
        return {'url': url}

    except Exception as e:
        warn(f"MITRE parse failed: {e}")
        return {}


# ─── Ubuntu CVE page parsing ──────────────────────────────────────
def parse_ubuntu(cve_id):
    """Parse Ubuntu CVE detail page (using CSS Selector)"""
    subsection("Ubuntu CVE Details")

    url = f"https://ubuntu.com/security/{cve_id}"

    try:
        html = fetch_url(url)
        if not html:
            warn(f"{cve_id} not found on Ubuntu")
            return {}

        soup = BeautifulSoup(html, 'html.parser')

        # Check 404
        if soup.find(string=re.compile(r'Page not found|404', re.I)):
            warn(f"CVE does not exist on Ubuntu")
            return {}

        # Extract CVE title
        title_elem = soup.select_one('h1')
        title = title_elem.get_text(strip=True) if title_elem else None
        if title:
            print(f"  Title: {title}")

        # Extract description
        desc_elem = soup.find('meta', {'name': 'description'})
        if desc_elem:
            desc = desc_elem.get('content', '').strip()
            if desc and len(desc) > 30:
                print(f"\n  {Colors.BOLD}Description:{Colors.NC}")
                for i in range(0, len(desc), 70):
                    print(f"    {desc[i:i+70]}")

        # Extract CVSS score
        cvss_elem = soup.find(string=re.compile(r'CVSS.*?[0-9]+\.[0-9]+'))
        if cvss_elem:
            match = re.search(r'([0-9]+\.[0-9]+)', cvss_elem)
            if match:
                score = match.group(1)
                score_color = Colors.RED if float(score) >= 7 else Colors.YELLOW if float(score) >= 4 else Colors.GREEN
                print(f"\n  CVSS Score: {Colors.BOLD}{score_color}{score}{Colors.NC}")

        # Parse Ubuntu version status table
        # Ubuntu page structure: each main row has package name in col 1, nested table in col 2 (each row = one Ubuntu release)
        main_table = soup.select_one('table.cve-table')
        if main_table:
            main_rows = main_table.select('tbody > tr')
            if not main_rows:
                main_rows = main_table.find_all('tr')

            all_releases = []
            for row in main_rows:
                # Main row first column: package name
                first_cell = row.select_one('td:first-child, th:first-child')
                package = first_cell.get_text(strip=True) if first_cell else ''

                # Nested table inside second column: each row is one Ubuntu version
                nested_table = row.select_one('td:nth-child(2) table')
                if nested_table:
                    nested_rows = nested_table.select('tbody > tr, tr')
                    for nrow in nested_rows:
                        cells = nrow.find_all('td', recursive=False)
                        if len(cells) < 2:
                            continue
                        codename_text = cells[0].get_text(strip=True)
                        status_text = cells[1].get_text(strip=True)
                        all_releases.append((package, codename_text, status_text))
                else:
                    # Fallback: direct td access
                    cells = row.find_all('td', recursive=False)
                    if len(cells) >= 3:
                        all_releases.append((package, cells[1].get_text(strip=True), cells[2].get_text(strip=True)))

            if all_releases:
                print(f"\n  {Colors.BOLD}Ubuntu Release Status:{Colors.NC}")
                print(f"  {'Package':<24} {'Release':<18} {'Status':<20}")
                print(f"  {'-'*24} {'-'*18} {'-'*20}")

                for package, codename, status_text in all_releases[:30]:
                    sl = status_text.lower()
                    if 'vulnerable' in sl:
                        icon = f"{Colors.RED}!{Colors.NC}"
                    elif 'fixed' in sl:
                        icon = f"{Colors.GREEN}+{Colors.NC}"
                    elif 'not affected' in sl or 'not-affected' in sl:
                        icon = f"{Colors.GREEN}o{Colors.NC}"
                    elif 'deferred' in sl:
                        icon = f"{Colors.RED}x{Colors.NC}"
                    elif 'DNE' in sl or 'not in release' in sl:
                        icon = f"{Colors.YELLOW}-{Colors.NC}"
                    else:
                        icon = f"{Colors.YELLOW}?{Colors.NC}"

                    if len(codename) > 16:
                        codename = codename[:15] + '...'
                    if len(package) > 22:
                        package = package[:21] + '...'
                    print(f"  {icon} {package:<22} {codename:<16} {status_text:<18}")

        # Summary status
        page_text = soup.get_text()
        if re.search(r'Does not exist', page_text):
            status_summary = f"{Colors.RED}x Ubuntu: CVE does not exist{Colors.NC}"
        elif re.search(r'vulnerable.*?deferred|fix.*?deferred', page_text, re.I):
            status_summary = f"{Colors.RED}x Fix deferred{Colors.NC}"
        elif re.search(r'vulnerable', page_text, re.I):
            status_summary = f"{Colors.RED}! Vulnerable{Colors.NC}"
        elif re.search(r'fixed', page_text, re.I):
            status_summary = f"{Colors.GREEN}+ Fix available{Colors.NC}"
        else:
            status_summary = f"{Colors.YELLOW}? Status unclear{Colors.NC}"

        print(f"\n  {Colors.BOLD}Summary:{Colors.NC} {status_summary}")
        success(f"Ubuntu page parsed successfully")
        return {'url': url}

    except Exception as e:
        warn(f"Ubuntu parse failed: {e}")
        return {}


# ─── Main ───────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description='CVE Vulnerability Verification Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s CVE-2026-31431
  %(prog)s CVE-2024-1234 --nvd-only
  %(prog)s --nvd-only CVE-2025-9999
        """
    )
    parser.add_argument('cve_id', nargs='?', default='CVE-2025-8941',
                        help='CVE ID (e.g., CVE-2026-31431)')
    parser.add_argument('--nvd-only', action='store_true',
                        help='Query NVD API only')
    parser.add_argument('--mitre-only', action='store_true',
                        help='Query MITRE only')
    parser.add_argument('--ubuntu-only', action='store_true',
                        help='Query Ubuntu only')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Quiet mode')

    args = parser.parse_args()
    cve_id = args.cve_id.upper()

    if not re.match(r'^CVE-\d{4}-\d{4,}$', cve_id):
        error(f"Invalid CVE ID format: {cve_id}")
        print("Format: CVE-YYYY-NNNNN (e.g., CVE-2026-31431)")
        sys.exit(1)

    # Header
    print(f"\n{Colors.BOLD}{'=' * 56}{Colors.NC}")
    print(f"{Colors.BOLD}  CVE Vulnerability Verification{Colors.NC}")
    print(f"{Colors.BOLD}{'=' * 56}{Colors.NC}")
    print(f"  CVE ID:   {Colors.BOLD}{cve_id}{Colors.NC}")
    print(f"  Time:     {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  {'-' * 56}")

    results = {}

    # MITRE
    if not args.nvd_only and not args.ubuntu_only:
        results['mitre'] = parse_mitre(cve_id)

    # Ubuntu
    if not args.nvd_only and not args.mitre_only:
        results['ubuntu'] = parse_ubuntu(cve_id)

    # NVD (always query)
    if not args.mitre_only and not args.ubuntu_only:
        results['nvd'] = parse_nvd(cve_id)
    elif args.nvd_only:
        results['nvd'] = parse_nvd(cve_id)

    # Footer
    print(f"\n{Colors.BOLD}{'=' * 56}{Colors.NC}")
    print(f"  Done: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  {'-' * 56}")
    if not args.quiet:
        print(f"  {Colors.BOLD}Sources:{Colors.NC}")
        print(f"    - MITRE:  https://www.cve.org/CVERecord?id={cve_id}")
        print(f"    - NVD:    https://nvd.nist.gov/vuln/detail/{cve_id}")
        print(f"    - Ubuntu: https://ubuntu.com/security/{cve_id}")
    print(f"{Colors.BOLD}{'=' * 56}{Colors.NC}")


if __name__ == '__main__':
    main()
