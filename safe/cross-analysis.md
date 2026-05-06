# Cross-Site Cookie Analysis

**Date:** 2026-05-06
**Status:** Architecture Review
**Classification:** Internal — Safe to Share

---

## Problem Statement

| Item | Detail |
|------|--------|
| Frontend | `https://www.aibang.com` |
| API Domain | Different domain (not `aibang.com`) |
| Cookies Required | `ajbx1_session`, `abjx2_session` |
| Symptom | Firefox blocks cookies → `"We were unable to authenticate you"` |
| Root Cause | Browser treats cookies as **cross-site (3rd party)** due to domain mismatch |

---

## Root Cause Analysis

### How Cookies Are Classified

Browsers classify cookies into two categories:

| Classification | Definition | Example |
|----------------|-----------|---------|
| **First-party** | Cookie domain matches the URL domain | `www.aibang.com` serving `aibang.com` cookies |
| **Third-party** | Cookie domain differs from URL domain | `www.aibang.com` serving `api.otherdomain.com` cookies |

### Why Browsers Block 3rd-Party Cookies

Cross-site cookies are not inherently insecure. However, they have a **reputation problem**:

- Historically used for **tracking** across sites (advertising networks)
- fingerprinting, session fixation, CSRF attacks are amplified by 3rd-party cookie contexts
- **Firefox** blocks by default (Enhanced Tracking Protection)
- **Safari** blocks by default (Intelligent Tracking Prevention)
- **Chrome** is phasing out (third-party cookie deprecation, now pushed to 2025+)

> **Note:** Even if frontend and API share a base domain (e.g., `aibang.com` vs `api.aibang.com`), the browser uses the **Public Suffix List (PSL)** and exact domain comparison. `api.aibang.com` is NOT considered the same site as `www.aibang.com` — they are subdomains of the same second-level domain, but browsers treat them as cross-site.

### The Real Fix: Cookie Attributes

The correct solution is to set proper `SameSite` attributes, not to architect around domain manipulation:

```
Set-Cookie: ajbx1_session=abc123; SameSite=Lax; Secure; HttpOnly
Set-Cookie: abjx2_session=def456; SameSite=Lax; Secure; HttpOnly
```

| Attribute | Value | Effect |
|-----------|-------|--------|
| `SameSite=Strict` | Cookies only sent on same-site requests | Too restrictive for this use case |
| `SameSite=Lax` | Cookies sent on same-site + safe cross-site top-level navigations (GET) | ✅ Recommended for this use case |
| `SameSite=None` | Cookies sent on all cross-site requests | ⚠️ Requires `Secure` (HTTPS); blocked by Firefox if not set |
| `Secure` | Cookies only sent over HTTPS | Required for `SameSite=None` |
| `HttpOnly` | Cookies inaccessible to JavaScript | ✅ Recommended (prevents XSS theft) |

---

## Option Evaluation

### Option 1: Domain Alignment

**Proposal:** Align FQDNs so browser considers cookies first-party.

**Implementation:** Redirect API calls through a subdomain of `aibang.com` (e.g., `api.aibang.com`).

| Criterion | Assessment |
|-----------|-----------|
| **Effectiveness** | ✅ Would work if API is hosted at `*.aibang.com` |
| **Browser Reliability** | ⚠️ **Fragile.** Browsers use PSL + exact domain match. Similar FQDNs are NOT automatically treated as same-site. `api.aibang.com` and `www.aibang.com` are cross-site. |
| **AIBANG Internal Domains** | ❌ Cannot guarantee internal domains can be aligned to `aibang.com` |
| **Security** | ⚠️ Does not address the underlying cookie attribute issue |
| **Complexity** | Medium (DNS + routing changes) |
| **Future-Proof** | ❌ Relying on domain similarity is not a documented browser behavior |

**Verdict:** **Not recommended as primary solution.** This approach misunderstands how browsers classify same-site vs cross-site. Subdomain similarity does not make cookies first-party.

---

### Option 2: Single Nginx Proxy (Recommended)

**Proposal:** Route ALL traffic (frontend + API) through one nginx proxy. Browser sees same origin for all cookies.

**Implementation:**
```
Browser → nginx proxy (same origin for frontend and API)
         ├── /        → Frontend static content
         ├── /api/*   → Forward to API backend
         └── Set-Cookie: (on all responses from proxy)
```

| Criterion | Assessment |
|-----------|-----------|
| **Effectiveness** | ✅ Solves the problem definitively — all requests from one origin |
| **Browser Reliability** | ✅ No dependency on fragile domain similarity heuristics |
| **Static Content Load** | ⚠️ Proxy handles all static content |
| **Caching Mitigation** | ✅ Enable nginx caching for static assets (CSS, JS, images, fonts) |
| **API Performance** | ✅ WebSocket/HTTP/2 multiplexing can be handled upstream |
| **AIBANG Internal Compatibility** | ✅ Works regardless of API domain |
| **Future-Proof** | ✅ Aligns with browser cookie security trends |

**Performance Mitigation for Static Content:**

```nginx
# Enable caching for static assets
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=static_cache:10m max_size=1g;

server {
    location / {
        # Static content — cache aggressively
        location ~* \.(css|js|images?|fonts?|ico|svg|woff2?)$ {
            proxy_pass http://frontend;
            proxy_cache static_cache;
            proxy_cache_valid 200 1d;
            add_header X-Cache-Status $upstream_cache_status;
        }

        # API requests — no caching
        location /api/ {
            proxy_pass http://api-backend;
            proxy_buffering off;
        }
    }
}
```

---

## Recommended Approach: Option 2 + Proper Cookie Attributes

**Do not rely on nginx alone.** Combine Option 2 with correct `SameSite` cookie attributes on the backend:

### Step 1: Configure Nginx Proxy (Option 2)

- Single entry point for frontend and API
- Unified origin from browser's perspective
- All `Set-Cookie` headers issued from same origin

### Step 2: Fix Cookie Attributes (Essential)

Even with a single proxy, ensure cookies have correct attributes:

```nginx
# In nginx proxy configuration
proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly";
```

Or fix at the **API backend** directly:

```
Set-Cookie: ajbx1_session=abc123; SameSite=Lax; Secure; HttpOnly; Path=/
Set-Cookie: abjx2_session=def456; SameSite=Lax; Secure; HttpOnly; Path=/
```

### Step 3: Verify with Firefox

Test with Firefox's default settings (Enhanced Tracking Protection ON):

```bash
# From a Linux host with Firefox + X:
firefox --headless https://www.aibang.com

# Or check cookie storage:
devtools → Application → Cookies
```

---

## Decision Matrix

| Criteria | Option 1 (Domain Align) | Option 2 (Nginx Proxy) |
|----------|:----------------------:|:---------------------:|
| Solves root cause | ❌ | ✅ |
| Works with AIBANG internal APIs | ❌ | ✅ |
| Browser-compatible | ⚠️ | ✅ |
| Future-proof | ❌ | ✅ |
| Static content impact | N/A | ⚠️ (mitigated by caching) |
| Implementation complexity | Medium | Medium |
| Recommended | ❌ | ✅ |

---

## Implementation Checklist

- [ ] Deploy nginx proxy at single origin (e.g., `www.aibang.com`)
- [ ] Route `/api/*` to API backend via `proxy_pass`
- [ ] Configure `proxy_cookie_path` with `SameSite=Lax; Secure; HttpOnly`
- [ ] Enable nginx caching for static assets
- [ ] Verify cookies are set with correct attributes (browser DevTools)
- [ ] Test authentication flow in Firefox (default settings)
- [ ] Test in Chrome and Safari for regression
- [ ] Document cookie domain and attribute requirements for API team

---

## References

- [SameSite Cookies Explained](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite)
- [Chrome Third-Party Cookie Deprecation](https://www.chromium.org/updates/privacy-sandbox)
- [Public Suffix List](https://publicsuffix.org/)
- [SameSite=Lax vs SameSite=None](https://web.dev/samesite-cookies-explained/)
