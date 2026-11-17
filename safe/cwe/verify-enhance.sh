#!/bin/bash

set -euo pipefail

DEFAULT_CVE="CVE-2025-8941"
CVE_ID="${1:-$DEFAULT_CVE}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

print_header() {
    echo "=============================================="
    echo "       CVE Vulnerability Verification"
    echo "=============================================="
    echo "CVE ID: $CVE_ID"
    echo "Time:  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "----------------------------------------------"
}

fetch_curl() {
    local url="$1"
    curl -s --connect-timeout 15 --max-time 30 -L -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "$url"
}

fetch_json() {
    local url="$1"
    curl -s --connect-timeout 15 --max-time 30 -H "Accept: application/json" "$url"
}

parse_nvd_cve() {
    local cve_id="$1"

    echo -e "\n${BLUE}==> NVD (National Vulnerability Database)${NC}"
    echo "--------------------------------------------"

    local nvd_response
    nvd_response=$(fetch_json "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=$cve_id")

    if echo "$nvd_response" | grep -q '"vulnerabilities"'; then
        local cvss_v31=$(echo "$nvd_response" | sed -n 's/.*"cvssV31":"\([^"]*\)".*/\1/p')
        local base_score=$(echo "$nvd_response" | sed -n 's/.*"baseScore":\([0-9.]*\).*/\1/p' | head -1)
        local base_severity=$(echo "$nvd_response" | sed -n 's/.*"baseSeverity":"\([^"]*\)".*/\1/p' | head -1)
        local status=$(echo "$nvd_response" | sed -n 's/.*"vulnStatus":"\([^"]*\)".*/\1/p' | head -1)
        local published=$(echo "$nvd_response" | sed -n 's/.*"published":"\([^"]*\)".*/\1/p' | head -1 | cut -d'.' -f1)
        local last_modified=$(echo "$nvd_response" | sed -n 's/.*"lastModified":"\([^"]*\)".*/\1/p' | head -1 | cut -d'.' -f1)

        if [ -n "$base_score" ]; then
            echo "CVSS v3.1 Score: ${base_score} (${base_severity:-N/A})"
            [ -n "$cvss_v31" ] && echo "CVSS Vector: $cvss_v31"
        else
            local cvss_score=$(echo "$nvd_response" | sed -n 's/.*"baseScore":\([0-9.]*\).*/\1/p' | head -1)
            [ -n "$cvss_score" ] && echo "CVSS Score: ${cvss_score}" || echo "CVSS 分数: 未知"
        fi

        echo -e "\n状态: ${status:-未知}"
        echo "发布日期: ${published:-未知}"
        echo "最后更新: ${last_modified:-未知}"

        local description=$(echo "$nvd_response" | sed -n 's/.*"descriptions":\[{"lang":"en","value":"\([^"]*\)".*/\1/p' | head -1)
        description=$(echo "$description" | sed 's/\\n/\n/g')
        if [ -n "$description" ]; then
            echo -e "\n描述:"
            echo "$description" | fold -s -w 80 | sed 's/^/    /'
        fi

        local cwe=$(echo "$nvd_response" | sed -n 's/.*"value":"CWE-\([^"]*\)".*/\1/p' | head -1)
        [ -n "$cwe" ] && echo -e "\nCWE: CWE-$cwe"

        local refs=$(echo "$nvd_response" | grep -oE '"url":"[^"]+' | cut -d'"' -f4 | head -8)
        if [ -n "$refs" ]; then
            echo -e "\n参考链接:"
            echo "$refs" | while IFS= read -r ref; do
                echo "  - $ref"
            done
        fi
        success "NVD 数据获取成功"
    else
        warn "NVD 数据获取失败或 CVE 不存在于 NVD"
    fi
}

parse_ubuntu_cve() {
    local html="$1"
    local cve_id="$2"

    echo -e "\n${BLUE}==> Ubuntu Security CVE Details${NC}"
    echo "--------------------------------------------"

    local title=$(echo "$html" | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' | head -1)
    [ -n "$title" ] && echo "标题: $title"

    echo -e "\n${BLUE}--> 漏洞描述${NC}"
    local desc_line=$(echo "$html" | grep -n '<h2 id="description"' | cut -d':' -f1 | head -1)
    if [ -n "$desc_line" ]; then
        local description=$(echo "$html" | sed -n "$((desc_line + 3)),$((desc_line + 4))p" | sed 's/<[^>]*>//g' | grep -v '^$' | tr '\n' ' ' | sed 's/^ *//;s/  */ /g')
        if [ -n "$description" ] && [ ${#description} -gt 50 ]; then
            echo "$description" | fold -s -w 80 | sed 's/^/    /'
        else
            echo "    未找到详细描述 (请查看 NVD)"
        fi
    else
        echo "    未找到详细描述 (请查看 NVD)"
    fi

    echo -e "\n${BLUE}--> CVSS 信息${NC}"
    local cvss_score=$(echo "$html" | grep -iE 'cvss.*[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [ -n "$cvss_score" ] && echo "CVSS 分数: $cvss_score" || echo "CVSS 分数: 未知 (请查看 NVD)"

    echo -e "\n${BLUE}--> Ubuntu 版本修复状态${NC}"
    echo "--------------------------------------------"

    local table_data=$(echo "$html" | tr '\n' ' ' | sed 's/<tr/\nTR/g' | grep '^TR')
    local current_package=""
    local found=0

    while IFS= read -r row; do
        [ -z "$row" ] && continue

        if echo "$row" | grep -q '<th.*rowspan.*>'; then
            current_package=$(echo "$row" | sed 's/.*<th[^>]*>\s*\([^<]*\)\s*<\/th>.*/\1/' | sed 's/^ *//;s/  *//g')
        fi

        local release=$(echo "$row" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        local codename=$(echo "$row" | grep -oE 'u-text--muted">[^<]*' | sed 's/u-text--muted">//' | head -1)

        local status_text=""
        if echo "$row" | grep -qi 'Vulnerable'; then
            status_text="Vulnerable"
        elif echo "$row" | grep -qi 'Not affected'; then
            status_text="Not affected"
        elif echo "$row" | grep -qi 'Fixed'; then
            status_text="Fixed"
        elif echo "$row" | grep -qi 'Deferred'; then
            status_text="Deferred"
        elif echo "$row" | grep -qi 'DNE\|not in release\|does not exist'; then
            status_text="Not in release"
        fi

        if [ -n "$status_text" ] && [ -n "$release" ]; then
            found=1
            local status_icon="❓"
            case "$status_text" in
                Vulnerable) status_icon="⚠️ " ;;
                Fixed) status_icon="✅ " ;;
                "Not affected") status_icon="🟢 " ;;
                Deferred) status_icon="🔴 " ;;
                "Not in release") status_icon="⬜ " ;;
                *) status_icon="❓ " ;;
            esac
            local line="$status_icon${release} LTS"
            [ -n "$codename" ] && line="$line ($codename)"
            [ -n "$current_package" ] && line="$line [${current_package}]"
            line="$line - $status_text"
            echo "$line"
        fi
    done <<< "$table_data"

    [ $found -eq 0 ] && {
        echo "状态数据:"
        echo "$html" | sed 's/<[^>]*>/ /g' | tr -s ' \n' | grep -iE 'vulnerable|fixed|deferred|not affected' | head -15 | while IFS= read -r line; do
            [ -n "$line" ] && echo "  - $line"
        done
    }

    echo -e "\n${BLUE}--> 修复状态总结${NC}"
    if echo "$html" | grep -qi 'DNE\|does not exist\|not in'; then
        echo "🔴 Ubuntu 不存在此 CVE"
    elif echo "$html" | grep -qi 'vulnerable.*deferred\|fix.*deferred'; then
        echo "🔴 修复被推迟"
    elif echo "$html" | grep -qi 'vulnerable'; then
        echo "⚠️  存在漏洞"
    elif echo "$html" | grep -qi 'fixed'; then
        echo "✅ 已有修复版本"
    else
        echo "❓ 状态未明确"
    fi
}

search_ubuntu_notices() {
    local cve_id="$1"

    echo -e "\n${BLUE}==> Ubuntu Security Notices${NC}"
    echo "--------------------------------------------"

    local search_num=$(echo "$cve_id" | cut -d'-' -f2,3)
    local notices_html
    notices_html=$(fetch_curl "https://ubuntu.com/security/notices?q=${search_num}%3E${cve_id}")

    if echo "$notices_html" | grep -qi "$cve_id\|USN-[0-9]"; then
        local usn_numbers=$(echo "$notices_html" | grep -oE 'USN-[0-9]+-[0-9]+' | sort -u | head -5)
        if [ -n "$usn_numbers" ]; then
            echo "找到相关安全公告:"
            echo "$usn_numbers" | while IFS= read -r usn; do
                echo "  - https://ubuntu.com/security/notices/$usn"
            done
            success "找到 Ubuntu 安全公告"
        else
            warn "未找到详细公告链接"
        fi
    else
        warn "未找到相关 Ubuntu 安全公告"
    fi
}

main() {
    print_header

    local cve_url="https://ubuntu.com/security/$CVE_ID"
    info "获取 Ubuntu CVE 详情: $cve_url"

    local html_response
    html_response=$(fetch_curl "$cve_url")

    if [ -z "$html_response" ]; then
        error "无法获取 CVE 数据"
        exit 1
    fi

    if echo "$html_response" | grep -qi '404\|Page not found\|does not exist'; then
        error "CVE $CVE_ID 不存在或尚未公开"
        parse_nvd_cve "$CVE_ID"
        exit 1
    fi

    parse_ubuntu_cve "$html_response" "$CVE_ID"

    echo -e "\n${BLUE}==> NVD 详细数据${NC}"
    parse_nvd_cve "$CVE_ID"

    search_ubuntu_notices "$CVE_ID"

    echo -e "\n=============================================="
    echo "检查完成: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo ""
        echo "用法: $0 [CVE-ID]"
        echo "示例: $0 CVE-2024-1234"
        echo "默认: $DEFAULT_CVE"
    fi
}

main "$@"