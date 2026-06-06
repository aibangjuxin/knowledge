---
name: gcp-tls-cert-keypair-validation
description: Verify a local cert.pem and key.pem actually form a matched keypair (offline keypair validation, not server-side chain validation). Captures the MD5-of-PEM pitfall that gives false negatives, the modulus-based correct algorithm, PEM format disambiguation (PKCS#1 vs PKCS#8), the "REDACTED" display-tool quirk that hides real keys, and the orphan keypair matrix check pattern. Load when you have a cert file and a key file and need to confirm they are the same keypair before uploading to a Load Balancer / Cloud Armor / Cloud CDN, or when triaging a "HTTPS not working after switching certs" situation.
---

# TLS Cert + Key Pair Validation (Local Keypair Check)

## When to use

- You have a `cert.pem` and a `key.pem` on disk and need to confirm they form a **matched keypair** before uploading to GCP (`gcloud compute ssl-certificates create ... --certificate=... --private-key=...`) or to Cloudflare / nginx / Envoy
- You have N certs and M keys and need to know which cert+key form a pair (the **orphan detection matrix**)
- You just received a `key.pem` from a colleague and want to verify it's the right one before shipping to production
- You are debugging a `SSL certificate problem` on a GLB / ILB and suspect a cert/key mismatch is the cause (it almost always is when `--certificate` and `--private-key` are uploaded separately)

This skill is **offline keypair validation** — it does NOT cover server-side chain validation (use `gcp-tls-troubleshooting` for that).

## The two correct algorithms (in order of preference)

### Algorithm 1 — Modulus comparison (most robust, format-agnostic)

The mod value is the same regardless of PEM format. Use this.

```bash
diff <(openssl x509 -in cert.pem -noout -modulus 2>/dev/null) \
     <(openssl rsa -in key.pem -noout -modulus 2>/dev/null) >/dev/null \
  && echo "✓ matched" || echo "✗ NOT matched"
```

**Pros**: no PEM-format gotchas, works for RSA / EC / Ed25519, byte-for-byte exact.

**Cons**: requires both files to be parseable by openssl at all. If the cert or key is malformed, both sides will be empty strings and the diff will silently pass — add a size check:

```bash
CERT_MOD=$(openssl x509 -in cert.pem -noout -modulus 2>/dev/null)
KEY_MOD=$(openssl rsa -in key.pem -noout -modulus 2>/dev/null)
[[ -z "$CERT_MOD" || -z "$KEY_MOD" ]] && { echo "parse failed"; exit 1; }
diff <(echo "$CERT_MOD") <(echo "$KEY_MOD") >/dev/null \
  && echo "✓ matched" || echo "✗ NOT matched"
```

### Algorithm 2 — Public-key PEM diff (works only if both are in the same format)

```bash
diff <(openssl x509 -in cert.pem -noout -pubkey 2>/dev/null) \
     <(openssl rsa -in key.pem -pubout 2>/dev/null) >/dev/null \
  && echo "✓ matched" || echo "✗ NOT matched"
```

**Pitfall**: this looks like it should work, and it does for native RSA keys where both outputs are PEM, but the **PEM headers differ** between `x509 -pubkey` (PKCS#8 — `BEGIN PUBLIC KEY`) and `rsa -pubout` (PKCS#1 — `BEGIN RSA PUBLIC KEY`). The PEM body (base64 of the same modulus + exponent) is identical, but the headers cause `diff` to report a mismatch even when the keypair is valid.

**Workaround** if you must use this form: convert both sides to the same format first.

## The MD5 pitfall (DO NOT do this)

```bash
# ❌ WRONG — gives false negatives due to PEM header differences
C=$(openssl x509 -in cert.pem -noout -pubkey 2>/dev/null | openssl md5 | awk '{print $2}')
K=$(openssl rsa -in key.pem -pubout 2>/dev/null | openssl md5 | awk '{print $2}')
[[ "$C" == "$K" ]] && echo "✓ matched" || echo "✗ NOT matched"
```

**Why it's wrong**: `x509 -pubkey` and `rsa -pubout` output PEM with different headers (PKCS#8 vs PKCS#1). The body is the same but the headers aren't. MD5 hashing the entire PEM file → different MD5 → false "not matched" even when the keypair is real and paired.

**Diagnosis recipe** when you suspect this is biting you:

```bash
# What do the two pubkey PEMs actually look like?
openssl x509 -in cert.pem -noout -pubkey 2>/dev/null | head -1
openssl rsa  -in key.pem  -pubout        2>/dev/null | head -1
# Expected: first shows "BEGIN PUBLIC KEY", second shows "BEGIN RSA PUBLIC KEY"
# If both say the same header, MD5 is fine; if they differ, MD5 will lie.
```

Use **modulus comparison (Algorithm 1)** instead. Always.

## PEM format disambiguation

| PEM header | Format | Used by | What to convert with |
|------------|--------|---------|----------------------|
| `-----BEGIN PUBLIC KEY-----` | PKCS#8 SubjectPublicKeyInfo (X.509 standard) | `openssl x509 -pubkey`, modern key tools | already in canonical form |
| `-----BEGIN RSA PUBLIC KEY-----` | PKCS#1 (legacy RSA-only) | `openssl rsa -RSAPublicKey_out` and `-pubout` | `openssl rsa -RSAPublicKey_in` to convert to PKCS#8 |
| `-----BEGIN EC PUBLIC KEY-----` | PKCS#1 EC variant | `openssl ec -pubout` | `openssl ec -pubin` |
| `-----BEGIN CERTIFICATE-----` | X.509 certificate | cert files | n/a (this is the cert, not a key) |
| `-----BEGIN PRIVATE KEY-----` | PKCS#8 unencrypted private key (RSA / EC / other) | `openssl req -x509 -newkey rsa:2048 -nodes` etc. | already in canonical form |
| `-----BEGIN RSA PRIVATE KEY-----` | PKCS#1 unencrypted RSA private key | older tools, sometimes `openssl genrsa` | convert with `openssl rsa -in` (auto-detects) |
| `-----BEGIN ENCRYPTED PRIVATE KEY-----` | PKCS#8 encrypted private key | `openssl genrsa -aes256` etc. | needs `-passin` to decrypt |

`openssl rsa` command auto-detects input format (PKCS#1, PKCS#8, encrypted) so you rarely need to convert by hand for keys. For pubkey PEMs, use modulus comparison (Algorithm 1) and ignore the format entirely.

## Orphan keypair matrix check

When you have N certs and M keys and need to know which cert+key form a pair (typical after a folder rename, cert rotation, or handoff from a colleague):

```bash
CERT_DIR="/path/to/certs"
declare -A C_PUB
for f in "$CERT_DIR"/*.pem "$CERT_DIR"/*.crt; do
    [[ -f "$f" ]] || continue
    N=$(basename "$f")
    C_PUB[$N]=$(openssl x509 -in "$f" -noout -modulus 2>/dev/null \
                | sha256sum | cut -d' ' -f1)
done
declare -A K_PUB
for f in "$CERT_DIR"/*.key "$CERT_DIR"/*.pem; do
    [[ -f "$f" ]] || continue
    N=$(basename "$f")
    K_PUB[$N]=$(openssl rsa -in "$f" -noout -modulus 2>/dev/null \
                | sha256sum | cut -d' ' -f1)
done
for c in "${!C_PUB[@]}"; do
    for k in "${!K_PUB[@]}"; do
        [[ "${C_PUB[$c]}" == "${K_PUB[$k]}" ]] \
            && echo "  ✓ MATCH: $c  ↔  $k"
    done
done
echo "  (no output = all orphan / no valid pair)"
```

**Why SHA-256 not MD5**: the modulus string is the same regardless of cert/key format, so the hash of the modulus string is also the same. SHA-256 is preferred over MD5 only because it's less collision-prone and reads cleaner in a large matrix.

**Adjacent technique** — also useful alongside the pair check:

```bash
# Quick visual inventory
for f in *.pem *.crt *.key; do
    [[ -f "$f" ]] || continue
    echo "=== $f ==="
    if head -1 "$f" | grep -q "BEGIN CERTIFICATE"; then
        openssl x509 -in "$f" -noout -subject -dates -ext subjectAltName
    elif head -1 "$f" | grep -q "BEGIN.*PRIVATE KEY"; then
        openssl rsa -in "$f" -noout -text 2>/dev/null | head -1
        openssl rsa -in "$f" -noout -modulus 2>/dev/null | head -c 30
        echo "..."
    fi
done
```

## Display tool quirk: "[REDACTED PRIVATE KEY]" can be misleading

`read_file`, `cat`, and some other file-display tools may render a PEM key file as just the literal text `[REDACTED PRIVATE KEY]` on the first line followed by blank lines, **even when the file actually contains a valid PKCS#8 private key in subsequent lines**.

**Symptoms**:
- `cat key.pem` shows only `[REDACTED PRIVATE KEY]\n`
- `head -3 key.pem` shows the same
- `wc -c key.pem` shows 1700+ bytes (way more than the 27-byte text)
- `openssl rsa -in key.pem -noout -modulus` works and returns a real modulus

**Why**: some tools (notably GitGuardian, GitHub secret scanning) insert `[REDACTED PRIVATE KEY]` as a placeholder marker when displaying redacted keys. The actual key data is still in the file, just hidden by the display layer.

**Diagnosis recipe**:

```bash
# Trust the bytes, not the display
wc -l key.pem          # real line count (30 for a 2048-bit RSA PKCS#8)
wc -c key.pem          # real byte count
head -c 5 key.pem | od -c   # first 5 raw bytes (should be "-----")

# Look at actual PEM body
sed -n '/[REDACTED PRIVATE KEY]/p' key.pem | sed '1d;$d' | base64 -d | head -c 50 | od -c
# This skips the marker line and footer, base64-decodes the body, and shows raw ASN.1

# Most reliable: pipe the file through asn1parse after base64-decoding
grep -v "^\[REDACTED" key.pem | grep -v "^----" | base64 -d > /tmp/key.der
openssl asn1parse -inform DER -in /tmp/key.der | head -5
# Expected: a valid ASN.1 tree with OBJECT rsaEncryption
```

**Once confirmed the key is real**, the modulus-based Algorithm 1 will work fine — display rendering is purely cosmetic.

## SAN wildcard matching rule (when uploading certs to a GLB)

Cloudflare Origin certs and self-signed certs often cover `*.parent.example.com` and you want to use them on `tenant.parent.example.com`. The X.509 wildcard rule (RFC 6125):

| SAN in cert | Matches | Does NOT match |
|-------------|---------|----------------|
| `*.abjx.uk` | `tenant.abjx.uk`, `api.abjx.uk` (one label) | `tenant.api.abjx.uk` (multi-level), `abjx.uk` (apex), `*.abjx.uk` (literal) |
| `*.taobao.abjx.uk` | `tenant.taobao.abjx.uk`, `x.taobao.abjx.uk` | `abjx.uk`, `*.abjx.uk`, `tenant.api.taobao.abjx.uk` |
| `abjx.uk` (apex) | `abjx.uk` only | any subdomain |
| Multiple SANs (e.g. `*.abjx.uk` + `*.taobao.abjx.uk` + `abjx.uk`) | union of what each individual SAN covers | — |

**The rule**: a wildcard `*` in the leftmost label matches **any single label** (not zero, not multiple). It does **not** match the bare apex.

So if your FQDN is `tenant.taobao.abjx.uk`, the cert's SAN list **must** include either:
- `*.taobao.abjx.uk` (direct match), or
- A literal `tenant.taobao.abjx.uk` entry

`*.abjx.uk` does **not** cover `tenant.taobao.abjx.uk` — that's a label-below-wildcard scenario the wildcard rule explicitly disallows.

**Verification command**:

```bash
# After uploading cert to GCP, check that the GLB is actually serving the right SAN
openssl s_client -connect <GLB_IP>:443 -servername <YOUR_FQDN> 2>/dev/null \
    | openssl x509 -noout -subject -ext subjectAltName
# Verify YOUR_FQDN is in the SAN list
```

## Key + algorithm + size sanity checks

A matched keypair can still be the wrong one if the algorithm or key size differ from what the GLB / nginx / Envoy expects. Before uploading:

```bash
# Key algorithm and size
openssl rsa -in key.pem -noout -text 2>/dev/null | head -1
# Expected: "Private-Key: (2048 bit, 2 primes)" or similar
# If you see "rsaEncryption" with 4096 bit, it's RSA-4096 — might be incompatible with older load balancers

# Cert algorithm and key size (from cert)
openssl x509 -in cert.pem -noout -text 2>/dev/null | grep -A 1 "Public Key Algorithm"
# Should also say RSA-2048 (or whatever your key is)

# Quick size match check
KEY_BITS=$(openssl rsa -in key.pem -noout -text 2>/dev/null \
          | grep -oE "Private-Key: \([0-9]+ bit" | grep -oE "[0-9]+")
CERT_BITS=$(openssl x509 -in cert.pem -noout -text 2>/dev/null \
           | grep -oE "Public-Key: [0-9]+ bit" | grep -oE "[0-9]+")
[[ "$KEY_BITS" == "$CERT_BITS" ]] && echo "✓ size match ($KEY_BITS bit)" || echo "✗ size mismatch: key=$KEY_BITS cert=$CERT_BITS"
```

**Mismatch symptoms** at upload time (e.g. `gcloud compute ssl-certificates create`):
- `Invalid value for field resource.privateKey: ... RSA modulus size mismatch`
- `Key size 4096 not supported for SSL Certificate`
- Silent failures on older GCP LB types that cap at 2048-bit

## Common failure mode in this environment

In the user's GCP/ingress work, the typical flow is:
1. Cloudflare dashboard → SSL/TLS → Origin Server → generate a Cloudflare Origin cert (covers `*.abjx.uk` / `*.taobao.abjx.uk`)
2. Save the cert and the auto-generated key to `cert/`
3. **Months later** the cert is rotated, the key is regenerated, and now the two saved files are no longer paired
4. Upload cert+key to GKE Regional External HTTPS LB → TLS handshake fails silently because the key doesn't match the cert

**Prevention**: after every cert/key generation/rotation, run Algorithm 1 (modulus diff) and store the result in a `cert.sha256` or `cert.ok` sidecar file. A quick `find cert/ -name "*.sha256" | xargs -I {} bash -c "test -s {}"` will surface orphan pairs.

## Related skills

- `gcp-tls-troubleshooting` — **server-side** chain validation (`curl -k` works but normal curl fails). Use that for "I can't reach a service over HTTPS". Use **this** skill for "I have cert+key files, do they pair?".
- `gke-ipam` — IP planning for GKE / PSC, unrelated to certs but often adjacent in PSC NEG architecture work.
