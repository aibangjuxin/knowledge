# Distroless Container Images

> GoogleContainerTools/distroless — production-grade minimal runtime images, **no shell, no package manager, no busybox**. Pair with multistage builds (see `multi-stage.md`) to ship just your app + its runtime dependencies.

---

## TL;DR

| What | One-liner |
|------|-----------|
| **What is it** | Minimal container images from Google that contain **only your app + language runtime + libc** — no shell, no apt, no busybox |
| **Why use it** | Smallest CVE surface in production · image 2–50 MiB (vs 124 MiB Debian) · provenance is "just what you need" |
| **When to use** | Final runtime stage of a multistage build · production K8s workloads · anything where `kubectl exec` debugging is OK to lose |
| **When NOT to use** | You need a shell to debug in-prod · one-shot scripts that `apt install` at runtime · legacy apps needing libc6 + many .so files |
| **Maintained by** | GoogleContainerTools · bazel-built · auto-tracks Debian upstream for CVEs |
| **Registry** | `gcr.io/distroless/*` (served from Artifact Registry under the hood, see [FAQ](#faq)) |

**Official repo:** https://github.com/GoogleContainerTools/distroless

---

## 1. What is Distroless?

> *"Distroless images contain only your application and its runtime dependencies. They do not contain package managers, shells or any other programs you would expect to find in a standard Linux distribution."* — [distroless README](https://github.com/GoogleContainerTools/distroless)

The name is a **meme** (like "serverless" doesn't mean "no servers"): **"distroless" doesn't mean "no OS"** — there's still a Linux kernel ABI, libc, ca-certificates, timezone data, and (for most flavors) a `/etc/passwd` with a `nonroot` user. What's missing is everything else.

| Layer | Debian | Alpine | Distroless |
|-------|:------:|:------:|:----------:|
| Linux kernel ABI | ✓ | ✓ | ✓ |
| libc | ✓ (glibc) | ✓ (musl) | ✓ (glibc, matching Debian) |
| ca-certificates | ✓ | ✓ | ✓ |
| `/etc/passwd` users | ✓ | ✓ | ✓ (just `nonroot` by default) |
| Package manager (`apt`/`apk`) | ✓ | ✓ | ✗ |
| Shell (`bash`/`sh`/`ash`) | ✓ | ✓ | ✗ (except `:debug` flavor) |
| Busybox utils (`ls`, `cat`, `wget`) | ✗ | ✓ | ✗ (except `:debug`) |
| `curl`, `wget`, `ps`, `vi` | ✗ (in slim) / ✓ (full) | ✓ | ✗ |

**The pitch:** if your image has no shell, no `apt`, no `curl`, an attacker who lands a shell-escape RCE has **nothing to escalate with** — no `wget` to pull a payload, no `sh` to spawn. CVE scanners also stop nagging you about bash CVEs from 2014 that don't exist in your image.

---

## 2. Available Images

> Updated 2026-06. Always check the [official README](https://github.com/GoogleContainerTools/distroless) — Debian releases are deprecated ~1 year after upstream EOL.

### Debian 13 (trixie) — current stable, recommended

| Image | What's inside | Typical use |
|-------|---------------|-------------|
| `gcr.io/distroless/static-debian13` | Just libc + ca-certs + tzdata | **Go** apps with `CGO_ENABLED=0`, Rust static binaries, any truly static ELF |
| `gcr.io/distroless/base-nossl-debian13` | static + libssl | Apps that need OpenSSL but not much else |
| `gcr.io/distroless/base-debian13` | base + `libgcc_s`, `ld-linux` | Anything dynamically linked to glibc but no runtime (Python, custom C/C++) |
| `gcr.io/distroless/cc-debian13` | base + C++ runtime (`libstdc++`, `libgcc_s`) | C++ apps, `cgo` Go apps |
| `gcr.io/distroless/java-base-debian13` | cc + `java` binary only (no JDK tools) | Java apps — but you usually want a language-specific image below |
| `gcr.io/distroless/java17-debian13` | JRE 17 + Java base | Java 17 apps |
| `gcr.io/distroless/java21-debian13` | JRE 21 + Java base | Java 21 apps |
| `gcr.io/distroless/nodejs22-debian13` | Node 22 + npm-less runtime | Node.js 22 apps |
| `gcr.io/distroless/nodejs24-debian13` | Node 24 + npm-less runtime | Node.js 24 apps |
| `gcr.io/distroless/nodejs26-debian13` | Node 26 + npm-less runtime | Node.js 26 apps |
| `gcr.io/distroless/python3-debian13` | Python 3 + pip-less runtime | Python apps |

### Tag suffixes — always use them in production

| Tag suffix | Meaning |
|------------|---------|
| `:latest` (or untagged) | Currently `:debian13`. **Pin explicitly** to avoid silent Debian-version bumps. |
| `:nonroot` | Runs as UID 65532 (user `nonroot`). Use this for K8s — `runAsNonRoot: true` works out of the box. |
| `:debug` | Adds busybox shell. **For local debugging only**, never ship to prod. |
| `:debug-nonroot` | Both. |
| Architecture suffixes | `:latest-amd64`, `:latest-arm64`, etc. for direct pulls (otherwise you get the multi-arch index). |

**Recommended pinning pattern:**

```dockerfile
FROM gcr.io/distroless/static-debian13:nonroot
# ^ locks both Debian version AND user — survives any future rename
```

---

## 3. Image Size Comparison

| Image | Size | Ratio vs Debian |
|-------|-----:|----------------:|
| `gcr.io/distroless/static-debian13` | **~2 MiB** | 2% |
| `gcr.io/distroless/base-debian13` | ~12 MiB | 10% |
| `gcr.io/distroless/python3-debian13` | ~50 MiB | 40% |
| `gcr.io/distroless/java17-debian13` | ~180 MiB | 145% (Debian OpenJDK is bigger) |
| `alpine:3.20` | ~5 MiB | 4% |
| `debian:bookworm-slim` | ~75 MiB | 60% |
| `debian:bookworm` | ~124 MiB | 100% |

**Why not just Alpine?** Alpine uses **musl libc** instead of glibc — Python wheels with C extensions (`numpy`, `cryptography`, `grpcio`) often break or need recompilation. Distroless keeps **glibc** matching the upstream Debian you built your app against. Translation: distroless = glibc-compatible + smaller + no shell.

---

## 4. Multistage Build Patterns

> See `multi-stage.md` for the general multistage pattern; this section is distroless-specific.

### 4.1 Go (the canonical example)

```dockerfile
# syntax=docker/dockerfile:1.7
# ---- build stage ----
FROM golang:1.22-bookworm AS build
WORKDIR /src

# Cache dependencies separately (don't bust cache on .go file changes)
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0 → static binary → fits in static-debian13 (no glibc needed)
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/app

# ---- runtime stage ----
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/app /app
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

**Result:** ~10 MiB final image. No shell, no package manager, no CVEs from busybox.

### 4.2 Python

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim-bookworm AS build
WORKDIR /app

# Install build deps for any wheels that need compiling
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libffi-dev \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# Now run from the wheels in a slim env to harvest site-packages
FROM python:3.12-slim-bookworm AS harvest
COPY --from=build /wheels /wheels
RUN pip install --no-cache-dir --no-deps --prefix=/install /wheels/*.whl \
 && find /install -name '__pycache__' -type d -exec rm -rf {} +

# ---- runtime stage ----
FROM gcr.io/distroless/python3-debian13:nonroot
COPY --from=harvest /install /usr/local
COPY app.py /app/
USER nonroot
WORKDIR /app
ENTRYPOINT ["python3", "/app/app.py"]
```

**Gotcha:** distroless `python3` image has **no pip** — you must install everything in the build stage. No `pip install -e .`, no `--upgrade pip`. Vendor your wheels.

### 4.3 Java

```dockerfile
# syntax=docker/dockerfile:1.7
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml ./
RUN mvn -B dependency:go-offline    # cache deps
COPY src ./src
RUN mvn -B package -DskipTests

# ---- runtime stage ----
FROM gcr.io/distroless/java21-debian13:nonroot
COPY --from=build /src/target/app.jar /app.jar
USER nonroot
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

**Gotcha:** if your JVM uses `-agentlib:*` (e.g. JFR, async-profiler), the agent `.so` must be present. Copy it into the distroless image manually if needed.

### 4.4 Node.js

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:22-bookworm-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build && npm prune --omit=dev

# ---- runtime stage ----
FROM gcr.io/distroless/nodejs22-debian13:nonroot
COPY --from=build /app /app
WORKDIR /app
USER nonroot
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

**Gotcha:** the `nodejs` image has the **node binary + libc + npm-less node_modules**. If your app uses native modules (`bcrypt`, `sharp`, `node-sqlite3`), they must be built in a stage with matching glibc, then copied across. Mismatched glibc = SIGSEGV at startup with no useful error.

---

## 5. Critical Gotchas

These are the foot-guns that bite every team the first time:

### 5.1 ❌ Shell-style ENTRYPOINT silently fails

```dockerfile
# WRONG — docker/containerd prefix with /bin/sh, which doesn't exist
ENTRYPOINT myapp

# CORRECT — exec form, container runs myapp directly (PID 1)
ENTRYPOINT ["myapp"]
```

If you write `ENTRYPOINT myapp` and `myapp` needs args, you'll get an obscure exit code 127 with no error message because there's no shell to interpret anything.

### 5.2 ❌ No shell → `RUN` / shell tricks don't work

You obviously can't `RUN apt install` — the image has no apt. You also can't do `RUN echo "hello" > /file` (no echo, no `>`, no `/bin/sh`). Workarounds:

```dockerfile
# Build these into a build stage, copy across
COPY wrapper.sh /wrapper.sh

# Or: use a non-shell heredoc trick
RUN ["/bin/sh", "-c", "echo hello > /tmp/x"]   # only works if base has /bin/sh
```

If you find yourself wanting `RUN echo` or `RUN curl | sh`, **you're using the wrong base image**. Step back to a build stage, do it there, copy the artifact across.

### 5.3 ❌ `kubectl exec` will not give you a shell

```
$ kubectl exec -it my-pod -- /bin/sh
error: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "...": ExecProcessError: exec /bin/sh: no such file or directory
```

**Three options:**
1. Use `:debug-nonroot` image in non-prod for troubleshooting.
2. Add a `debug` sidecar to prod pods that has busybox.
3. Use `kubectl debug` (ephemeral debug container — K8s 1.23+) with a different image:
   ```bash
   kubectl debug -it my-pod --image=nicolaka/netshoot --target=mycontainer
   ```

### 5.4 ❌ `ldd` doesn't exist either

`ldd` is itself a shell script (`#!/bin/sh`) — it's not in distroless. If you need it for debugging missing `.so` files:

```bash
# From a host that has glibc, copy the binary into a debug container:
docker run --rm -it --entrypoint=/bin/sh gcr.io/distroless/cc-debian13:debug -c \
  "ldd /app/myapp"
```

Or use `readelf -d myapp | grep NEEDED` to see what shared libs it wants.

### 5.5 ❌ glibc version mismatch between build and runtime

If you build on `debian:bookworm` (glibc 2.36) and run on `static-debian13` (glibc 2.38 → Debian 13/trixie), your dynamic binary **will not run** even though both have "glibc". The distroless image's glibc must be ≥ your build host's glibc. Pin your build stage to the same Debian major version as the distroless image:

```dockerfile
# Both Debian 13 — match
FROM debian:13-slim AS build       # glibc 2.38
FROM gcr.io/distroless/cc-debian13:nonroot AS runtime
```

### 5.6 ✅ Verification: cosign-signed

All distroless images are signed keylessly with [cosign](https://github.com/sigstore/cosign). Verify before deploying:

```bash
cosign verify gcr.io/distroless/static-debian13:nonroot \
  --certificate-oidc-issuer https://accounts.google.com \
  --certificate-identity keyless@distroless.iam.gserviceaccount.com
```

Expected output (truncated):
```
Verification for gcr.io/distroless/static-debian13:nonroot --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified against trusted roots
```

CI gate example (fail the build if signature is missing):
```bash
cosign verify gcr.io/distroless/static-debian13:nonroot \
  --certificate-oidc-issuer https://accounts.google.com \
  --certificate-identity keyless@distroless.iam.gserviceaccount.com \
  || { echo "DISTROLESS IMAGE NOT SIGNED — REFUSING TO BUILD"; exit 1; }
```

### 5.7 ✅ Auto-tracking Debian CVEs

Distroless auto-rebuilds when Debian ships a security update via a [GitHub Actions workflow](https://github.com/GoogleContainerTools/distroless/blob/main/.github/workflows/update-deb-package-snapshots.yml). You don't need to track upstream — just `docker pull` periodically or use `:latest`.

---

## 6. FAQ

**Q: Why does it still use `gcr.io` instead of `pkg.dev`?**
A: The serving infrastructure has moved to Artifact Registry under the hood; the `gcr.io` hostname is kept for backward compatibility. No action needed.

**Q: Can I `apt install` extra packages at build time?**
A: Not in the runtime stage (no apt). Two paths:
- **Build stage:** install into the build stage, copy artifacts (`.so`, configs, CA bundles) into distroless at final stage.
- **Bazel:** `rules_distroless` lets you compose a custom distroless image with specific Debian packages. See [GoogleContainerTools/rules_distroless](https://github.com/GoogleContainerTools/rules_distroless).

**Q: Does it run on arm64 / Graviton / Apple Silicon?**
A: Yes — the tags `:latest`, `:nonroot`, etc. resolve to multi-arch indexes. Pin via `:latest-arm64` if you want single-arch for a smaller pull.

**Q: How does it compare to `chainguard/static` or `cgr.dev/chainguard/*`?**
A: Chainguard images are similar in philosophy (distroless + auto-rebuild on CVEs) but add SBOM attestation, SLSA L3 provenance, and zero-CVE guarantees on some tiers. Trade-off: Chainguard is a paid product; distroless is free + community. For most teams, distroless is enough.

**Q: Can I run as root?**
A: Yes, but **don't**. Use `:nonroot` + K8s `runAsNonRoot: true` + `securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: [ALL] } }`. The whole point of distroless is defense-in-depth; running as root defeats it.

**Q: What's the difference between `:debug` and pulling busybox into a sidecar?**
A: `:debug` adds busybox to **your** image — not great for prod (more CVEs, more attack surface). Sidecar debug container (K8s ephemeral debug) keeps prod clean and only attaches the shell when you actively need it. Prefer sidecar.

**Q: Why is my Java image 180 MiB? Distroless is supposed to be tiny!**
A: That's the **JRE**, not the OS. JRE 21 is ~150 MiB on its own. Distroless saved you ~50 MiB of OS cruft, but you can't shrink the JVM. If size matters, consider `eclipse-temurin:21-jre-alpine` (uses Alpine, ~180 MiB total) or `GraalVM native-image` (compiled-to-native, ~50 MiB but harder to build).

---

## 7. Decision Tree

```
Need a container image for a service
│
├─ Need a shell for ad-hoc ops?  ─── YES ──→ :debug variant (non-prod only) or keep busybox base
│   └─ NO
│
├─ Static binary (Go with CGO_ENABLED=0, Rust musl, C with -static)?  ──→ static-debian13:nonroot
│
├─ Dynamic binary needing OpenSSL?  ──→ base-nossl-debian13:nonroot
│
├─ Dynamic binary / C++ / cgo?  ──→ cc-debian13:nonroot
│
├─ Java app?  ──→ java17-debian13 / java21-debian13:nonroot
│
├─ Node.js app with native modules?  ──→ nodejsXX-debian13:nonroot (match build stage glibc!)
│
└─ Python app with C-extension wheels?  ──→ python3-debian13:nonroot (harvest site-packages from a build stage)
```

---

## 8. See Also

- `multi-stage.md` — multistage build pattern (the "build in fat, run in thin" idiom)
- `Dockerfile.md` — deeper Dockerfile patterns & layer-cache optimization
- `multistage-build-analysis.md` — existing POC: reduced image from 588 MB → 47.7 MB (used Alpine; consider distroless for next iteration)
- `multistage-build-concepts.md` — concept summary + ZulJava legacy Dockerfile
- Official: https://github.com/GoogleContainerTools/distroless
- Cosign verification docs: https://docs.sigstore.dev/cosign/verify/
- Who uses it: Kubernetes (since v1.15), Knative, Tekton, Teleport, BloodHound, K8gb