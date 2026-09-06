# Shell Scripts Collection

Generated on: 2026-09-06 18:48:33
Directory: /Users/lex/git/gcp/ingress/public-mtls-global-ingress/cert

## `inspect-certs-linux.sh`

```bash
#!/usr/bin/env bash
# inspect-certs-linux.sh
#
# Author: Lex
#
# Description:
#   Parse every PEM certificate under a directory and print CN / SAN / Issuer /
#   validity period / EKU / CA flag. Targets GNU bash 4+ with GNU coreutils and
#   openssl (any Linux distro with a sane userspace).
#
# Usage:
#   ./inspect-certs-linux.sh           # parse the directory this script lives in
#   ./inspect-certs-linux.sh <dir>     # parse a specified directory
#
# Differences from inspect-certs.sh (macOS):
#   - Targets GNU bash 4+ (default on modern Linux distros); no macOS BWK awk
#     workaround needed.
#   - All other parsing logic is unchanged: openssl x509 -noout output is piped
#     through grep/sed, so behavior is identical where OpenSSL emits the same
#     format (it does for x509 -subject, -issuer, -ext subjectAltName,
#     -ext extendedKeyUsage, -ext basicConstraints).
#   - All comments and output glyphs are ASCII-only so the script renders
#     correctly on terminals without a UTF-8 locale.
set -euo pipefail

CERT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [[ ! -d "$CERT_DIR" ]]; then
  echo "ERROR: directory does not exist: $CERT_DIR" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

# Split "CN = foo, O = bar, OU = baz" into multi-line key=value
print_dn() {
  local label="$1" dn="$2"
  echo "  $label:"
  if [[ -z "$dn" ]]; then
    echo "    (empty)"
    return
  fi
  echo "$dn" | tr ',' '\n' | sed 's/^ *//' | awk '{ printf "    %-6s %s\n", " ", $0 }'
}

# Parse a single PEM block (one full
# -----BEGIN CERTIFICATE-----...-----END CERTIFICATE----- sequence).
inspect_block() {
  local label="$1" pem="$2"

  local subject issuer start end serial
  subject=$(printf '%s' "$pem" | openssl x509 -noout -subject   2>/dev/null | sed 's/^subject= *//')
  issuer=$(printf  '%s' "$pem" | openssl x509 -noout -issuer    2>/dev/null | sed 's/^issuer= *//')
  start=$(printf   '%s' "$pem" | openssl x509 -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
  end=$(printf     '%s' "$pem" | openssl x509 -noout -enddate   2>/dev/null | sed 's/^notAfter=//')
  serial=$(printf  '%s' "$pem" | openssl x509 -noout -serial    2>/dev/null | sed 's/^serial=//')

  # Primary CN (may be empty)
  local cn
  cn=$(echo "$subject" | grep -oE 'CN *= *[^,]+' | head -1 | sed 's/^CN *= *//' | sed 's/[[:space:]]*$//')
  [[ -z "$cn" ]] && cn="(no CN)"

  # SAN -- use openssl's dedicated extension output, far more stable than
  # parsing -text. OpenSSL prints all SAN entries on a single line separated
  # by commas, e.g.
  #   DNS:foo.example, URI:spiffe://ns/workload, URI:spiffe://ns/other, IP Address:10.0.0.1
  # NOTE: openssl renders IP SANs as "IP Address:1.2.3.4" (not "IP:..."),
  # so we match both. The regex matches each entry non-greedily up to the
  # next comma, so multiple URIs / DNS / IPs / emails are all captured
  # (one match per entry).
  local san_text san_dns san_ip san_uri san_email
  san_text=$(printf '%s' "$pem" | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)
  san_dns=$(echo   "$san_text" | { grep -oE 'DNS:[^,]+'             || true; } | sed 's/^DNS://'           | paste -sd' ' -)
  # Strip the "Address" word openssl inserts between "IP" and the address
  # (e.g. "IP Address:10.0.0.1").
  san_ip=$(echo    "$san_text" | { grep -oE 'IP( Address)?:[^,]+'     || true; } | sed -E 's/^IP( Address)?://' | paste -sd' ' -)
  san_uri=$(echo   "$san_text" | { grep -oE 'URI:[^,]+'             || true; } | sed 's/^URI://'           | paste -sd' ' -)
  san_email=$(echo "$san_text" | { grep -oE 'email:[^,]+'           || true; } | sed 's/^email://'         | paste -sd' ' -)
  # Trim any trailing whitespace introduced by paste
  san_dns="${san_dns## }"; san_ip="${san_ip## }"
  san_uri="${san_uri## }"; san_email="${san_email## }"

  # EKU
  local eku_text eku
  eku_text=$(printf '%s' "$pem" | openssl x509 -noout -ext extendedKeyUsage 2>/dev/null || true)
  eku=$(echo "$eku_text" | tail -1 | sed 's/^[[:space:]]*//')
  if [[ "$eku" == extendedKeyUsage* ]]; then eku=""; fi

  # CA flag (true if basicConstraints CA:TRUE is set)
  local is_ca="Leaf"
  if printf '%s' "$pem" | openssl x509 -noout -ext basicConstraints 2>/dev/null | grep -q "CA:TRUE"; then
    is_ca="CA"
  fi

  echo "  -------------------------------------------------"
  echo "  > $label   [$is_ca]"
  echo "    CN:      $cn"
  echo "    Serial:  $serial"
  echo "    Valid:   $start  ->  $end"
  print_dn "Subject" "$subject"
  print_dn "Issuer " "$issuer"
  echo "    SAN:"
  if [[ -z "$san_dns$san_ip$san_uri$san_email" ]]; then
    echo "      (none)"
  else
    [[ -n "$san_dns"   ]] && echo "      DNS:   $san_dns"
    [[ -n "$san_ip"    ]] && echo "      IP:    $san_ip"
    [[ -n "$san_uri"   ]] && echo "      URI:   $san_uri"
    [[ -n "$san_email" ]] && echo "      Email: $san_email"
  fi
  if [[ -n "$eku" ]]; then echo "    EKU:    $eku"; fi
}

# -----------------------------------------------------------------------------
# Main flow
# -----------------------------------------------------------------------------

echo "================================================================"
echo "  Cert Inspector - $CERT_DIR"
echo "================================================================"

shopt -s nullglob
files=( "$CERT_DIR"/*.pem "$CERT_DIR"/*.crt )
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERROR: no .pem or .crt files in directory" >&2
  exit 1
fi

# Sort for stable output across runs
IFS=$'\n' files=($(printf '%s\n' "${files[@]}" | sort))
unset IFS

file_count=0
cert_count=0
for f in "${files[@]}"; do
  file_count=$((file_count + 1))
  echo ""
  echo "+- File: $f"

  # Split PEM into individual certificate blocks using a pure-bash split
  # (no awk/\0 dependency -- works identically on GNU and BWK awk, and this
  # approach is portable anyway).
  blocks=()
  current=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    current+="$line"$'\n'
    if [[ "$line" == *-----END\ CERTIFICATE-----* ]]; then
      blocks+=("$current")
      current=""
    fi
  done < "$f"

  if [[ ${#blocks[@]} -eq 0 ]]; then
    echo "|  (no CERTIFICATE block found)"
    echo "+-"
    continue
  fi

  total=${#blocks[@]}
  for i in "${!blocks[@]}"; do
    pem="${blocks[$i]}"
    cert_count=$((cert_count + 1))

    if [[ $total -eq 1 ]]; then
      label="$(basename "$f")"
    else
      case $i in
        0)                      role="leaf (end-entity cert)" ;;
        $(( total - 1 )))       role="root CA" ;;
        *)                      role="intermediate CA (#$((i+1)))" ;;
      esac
      label="$(basename "$f")  [cert #$((i+1))/$total -- $role]"
    fi

    inspect_block "$label" "$pem"
  done

  echo "+-"
done

echo ""
echo "================================================================"
echo "  Done: parsed $file_count file(s), $cert_count certificate(s)."
echo "================================================================"

```

## `inspect-certs.sh`

```bash
#!/usr/bin/env bash
# inspect-certs.sh — 解析 cert/ 目录下所有 PEM 证书的 CN / SAN / Issuer / 有效期 / EKU
#
# 用法: ./inspect-certs.sh           # 解析脚本所在目录
#       ./inspect-certs.sh <dir>     # 解析指定目录
set -euo pipefail

CERT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [[ ! -d "$CERT_DIR" ]]; then
  echo "❌ 目录不存在: $CERT_DIR" >&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# 工具函数
# ──────────────────────────────────────────────────────────────────────────────

# 把 "CN = foo, O = bar, OU = baz" 拆成多行 key=value
print_dn() {
  local label="$1" dn="$2"
  echo "  $label:"
  if [[ -z "$dn" ]]; then
    echo "    (empty)"
    return
  fi
  echo "$dn" | tr ',' '\n' | sed 's/^ *//' | awk '{ printf "    %-6s %s\n", " ", $0 }'
}

# 解析单个 PEM block(一段完整的 -----BEGIN CERTIFICATE-----...-----END CERTIFICATE-----)
inspect_block() {
  local label="$1" pem="$2"

  local subject issuer start end serial
  subject=$(printf '%s' "$pem" | openssl x509 -noout -subject   2>/dev/null | sed 's/^subject= *//')
  issuer=$(printf  '%s' "$pem" | openssl x509 -noout -issuer    2>/dev/null | sed 's/^issuer= *//')
  start=$(printf   '%s' "$pem" | openssl x509 -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
  end=$(printf     '%s' "$pem" | openssl x509 -noout -enddate   2>/dev/null | sed 's/^notAfter=//')
  serial=$(printf  '%s' "$pem" | openssl x509 -noout -serial    2>/dev/null | sed 's/^serial=//')

  # 主 CN(可能为空)
  local cn
  cn=$(echo "$subject" | grep -oE 'CN *= *[^,]+' | head -1 | sed 's/^CN *= *//' | sed 's/[[:space:]]*$//')
  [[ -z "$cn" ]] && cn="(no CN)"

  # SAN —— 用 openssl 专门的扩展输出,比解析 -text 稳得多
  local san_text san_dns san_ip san_uri san_email
  san_text=$(printf '%s' "$pem" | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)
  san_dns=$(echo   "$san_text" | { grep -oE 'DNS:[^,]*'   || true; } | sed 's/^DNS://'   | paste -sd' ' -)
  san_ip=$(echo    "$san_text" | { grep -oE 'IP:[^,]*'    || true; } | sed 's/^IP://'    | paste -sd' ' -)
  san_uri=$(echo   "$san_text" | { grep -oE 'URI:[^,]*'   || true; } | sed 's/^URI://'   | paste -sd' ' -)
  san_email=$(echo "$san_text" | { grep -oE 'email:[^,]*' || true; } | sed 's/^email://' | paste -sd' ' -)

  # EKU
  local eku_text eku
  eku_text=$(printf '%s' "$pem" | openssl x509 -noout -ext extendedKeyUsage 2>/dev/null || true)
  eku=$(echo "$eku_text" | tail -1 | sed 's/^[[:space:]]*//')
  if [[ "$eku" == extendedKeyUsage* ]]; then eku=""; fi

  # 是否 CA
  local is_ca="Leaf"
  if printf '%s' "$pem" | openssl x509 -noout -ext basicConstraints 2>/dev/null | grep -q "CA:TRUE"; then
    is_ca="CA"
  fi

  echo "  ────────────────────────────────────────────────"
  echo "  ▸ $label   [$is_ca]"
  echo "    CN:      $cn"
  echo "    Serial:  $serial"
  echo "    Valid:   $start  →  $end"
  print_dn "Subject" "$subject"
  print_dn "Issuer " "$issuer"
  echo "    SAN:"
  if [[ -z "$san_dns$san_ip$san_uri$san_email" ]]; then
    echo "      (none)"
  else
    [[ -n "$san_dns"   ]] && echo "      DNS:   $san_dns"
    [[ -n "$san_ip"    ]] && echo "      IP:    $san_ip"
    [[ -n "$san_uri"   ]] && echo "      URI:   $san_uri"
    [[ -n "$san_email" ]] && echo "      Email: $san_email"
  fi
  if [[ -n "$eku" ]]; then echo "    EKU:    $eku"; fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 主流程
# ──────────────────────────────────────────────────────────────────────────────

echo "══════════════════════════════════════════════════════════════════"
echo "  Cert Inspector — $CERT_DIR"
echo "══════════════════════════════════════════════════════════════════"

shopt -s nullglob
files=( "$CERT_DIR"/*.pem "$CERT_DIR"/*.crt )
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "❌ 目录下没有 .pem 或 .crt 文件" >&2
  exit 1
fi

# 排序让输出稳定
IFS=$'\n' files=($(printf '%s\n' "${files[@]}" | sort))
unset IFS

file_count=0
cert_count=0
for f in "${files[@]}"; do
  file_count=$((file_count + 1))
  echo ""
  echo "┌─ File: $f"

  # 拆 PEM 成单个证书 block(纯 bash 切,避免 macOS BWK awk 不支持 \0 的坑)
  blocks=()
  current=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    current+="$line"$'\n'
    if [[ "$line" == *-----END\ CERTIFICATE-----* ]]; then
      blocks+=("$current")
      current=""
    fi
  done < "$f"

  if [[ ${#blocks[@]} -eq 0 ]]; then
    echo "│  (no CERTIFICATE block found)"
    echo "└─"
    continue
  fi

  total=${#blocks[@]}
  for i in "${!blocks[@]}"; do
    pem="${blocks[$i]}"
    cert_count=$((cert_count + 1))

    if [[ $total -eq 1 ]]; then
      label="$(basename "$f")"
    else
      case $i in
        0)                      role="leaf (end-entity cert)" ;;
        $(( total - 1 )))       role="root CA" ;;
        *)                      role="intermediate CA (#$((i+1)))" ;;
      esac
      label="$(basename "$f")  [cert #$((i+1))/$total — $role]"
    fi

    inspect_block "$label" "$pem"
  done

  echo "└─"
done

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  完成:解析了 $file_count 个文件,$cert_count 张证书。"
echo "══════════════════════════════════════════════════════════════════"

```

