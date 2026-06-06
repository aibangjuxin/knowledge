# Same-Project PSC NEG Test Setup (Regional External LB + PSC in one project)

> When you want to test a Regional External HTTPS LB → PSC NEG → Service Attachment → ILB → MIG backend, but you have **only one GCP project** (no separate B Project to provide the Service Attachment), GCP has a documented architecture limitation that makes the obvious path fail. This reference covers the limitation, workarounds, and the full execution gotcha list.

## The fundamental limitation

**Regional `EXTERNAL_MANAGED` Backend Service in scope REGION cannot use a Private Service Connect network endpoint group that is in the producer network and targets a Service Attachment.**

When the producer's Service Attachment and the consumer's PSC NEG live in the **same project + same VPC + same network**, GCP rejects the backend-attachment with:

```
Invalid value for field 'resource.backends[0]':
  EXTERNAL MANAGED Backend Service in scope REGION can not use
  Private Service Connect network endpoint group that is in producer
  network and targets Service Attachment.
```

**Why**: GCP's "different network" requirement is the security boundary that makes PSC useful — a backend in a different VPC/project can only be reached via an explicit, audited bridge (the Service Attachment). When the consumer and producer share a network, the LB could just route directly — PSC adds nothing, and the API rejects the path.

**The 4 workarounds** (for when you have only one project to test with):

| # | Workaround | What it does | Trade-off |
|---|---|---|---|
| **1** | **Create a 2nd VPC in the same project** (e.g., `ajbx-consumer-vpc` + `ajbx-producer-vpc`), put backend in producer VPC, put PSC NEG in consumer VPC, peer them. | Genuine PSC NEG flow, cross-VPC | Need to re-architect existing infra; only works if you have room in your IP plan |
| **2** | **Skip PSC entirely**: regional External LB → ILB → MIG (or GKE NEG) directly. Lose the Producer/Tenant separation. | Simplest — works in one VPC, one project | No PSC; defeats the purpose of testing the PSC pattern |
| **3** | **Use GKE + Standalone NEG** instead of PSC: deploy backend as GKE Deployment, create a Standalone NEG pointing to the GKE Service, attach to backend service. | Container-native, also one-project, also one-VPC | Different pattern than PSC; doesn't test the bridge you wanted to test |
| **4** | **Force a "different network" illusion** by using **non-overlapping VPCs** and the same trick Workaround 1 uses, but with `--network` pointing to one VPC and the SA producer in the other. | Same as #1 with less re-architecture | Same caveats as #1 |

**Reachability summary**:
- Cross-project PSC NEG → Regional External LB → ✅ works (the intended cross-project use case)
- Same-project + same-VPC PSC NEG → Regional External LB → ❌ **fails** with the above error
- Same-project + 2 different VPCs PSC NEG → Regional External LB → ✅ works
- Same-project + single VPC, no PSC → Regional External LB → ✅ works (but not testing PSC)

If the goal is to test the **PSC NEG bridge specifically** in one project, Workaround #1 is the only honest answer. The "Public Ingress — Regional External HTTPS LB" doc your user already wrote is the cross-project answer; for same-project testing, the consumer-side of that doc is the right reference but the architecture needs the 2-VPC variant.

## What the rest of the chain still requires (regardless of workaround)

Once you've picked a workaround, the **operational gotchas** below apply identically.

### Gotcha 1: No-address MIG VM cannot `apt-get install` (needs Cloud NAT or stdlib fallback)

A regional backend service → ILB → regional MIG pattern means the MIG instances have `--no-address`. They cannot reach public package mirrors (Debian's deb.debian.org, Cloud SDK, etc.) without an egress path. The startup script's `apt-get install nginx-light` will hang and fail with:

```
W: Failed to fetch https://deb.debian.org/debian/dists/bullseye/InRelease
   Cannot initiate the connection to debian.map.fastly.net:443 (2a04:4e42::644):
   connect (101: Network is unreachable)
```

**Fix A — Cloud NAT** (recommended for production):
```bash
gcloud compute routers create ${POC}-cloud-router \
    --network=${VPC} --region=${REGION}
gcloud compute routers nats create ${POC}-cloud-nat \
    --router=${POC}-cloud-router --region=${REGION} \
    --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips
```

**Fix B — Use stdlib only** (no apt, no NAT, fastest POC):
Replace the `apt-get install nginx-light` block with a `python3 -u /opt/tenant/server.py` that uses `http.server.HTTPServer` + `ssl.SSLContext` to serve HTTPS on 443. Python is always present in `debian-11` base images. See `templates/same-project-psc-test-setup/python-https-server.py` for the canonical 80-line working example (including a daemon-thread HTTP/80 listener for the GCP health check path and an HTTP/443 TLS listener for the actual cert+key).

### Gotcha 2: Regional Internal LB also requires a proxy-only subnet

The `--load-balancing-scheme=INTERNAL_MANAGED` forwarding rule will fail with:
```
An active proxy-only subnetwork is required in the same region and VPC as the forwarding rule.
```

**Fix**: a regional LB chain (Internal OR External) needs:
```bash
gcloud compute networks subnets create ${POC}-proxy \
    --network=${VPC} --region=${REGION} --range=<unique /24> \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
```

This applies even when there's no cross-region element. The `purpose=REGIONAL_MANAGED_PROXY` is mandatory for **all** modern managed proxy LBs (Regional External, Regional Internal, Cross-region Internal) — `INTERNAL_HTTPS_LOAD_BALANCER` (the old purpose) is no longer accepted. See the parent `cross-project-psc-architecture` Gotcha 5 for the migration story if your environment still has the old-purpose subnet.

### Gotcha 3: Regional MIG + regional Backend Service → use `--instance-group-region`, not `--instance-group-zone`

`gcloud compute backend-services add-backend` requires you to tell it how to find the instance group. For a **regional** MIG, the correct flag is:
```bash
gcloud compute backend-services add-backend ${POC}-bs \
    --region=${REGION} \
    --instance-group=${POC}-mig \
    --instance-group-region=${REGION}   # ← regional, not zonal
    --balancing-mode=RATE --max-rate-per-instance=100
```

If you accidentally pass `--instance-group-zone=europe-west2-a`:
```
Could not fetch resource: .../zones/.../instanceGroups/${POC}-mig not found
```

(It's looking under zonal path; the MIG lives at the regional path.) Symptom is misleading — looks like "not found" but really wrong lookup path.

### Gotcha 4: PSC NEG backend cannot have a health check on the backend service

`gcloud compute backend-services add-backend --network-endpoint-group=...` with a PSC NEG refuses if the backend service already has a `--health-checks`:
```
A backend service cannot have a healthcheck with Private Service Connect
network endpoint group backends.
```

**Why**: PSC NEG health is determined by whether the Service Attachment is reachable from the consumer network, which GCP checks automatically. The backend service doesn't need (and can't have) a separate health check.

**Fix**: don't pass `--health-checks` when creating the backend service for a PSC NEG chain. If you accidentally set one, remove it before `add-backend`:
```bash
gcloud compute backend-services update ${POC}-bs \
    --region=${REGION} \
    --health-checks="" --health-checks-region=""
```

### Gotcha 5: Cloud Armor rate-limit rule needs `--conform-action` and `--exceed-action` flags

`--action=rate-based-ban` alone is incomplete:
```
Invalid value for field 'resource.rateLimitOptions':
  Rate limit threshold, conform action, and exceed action must be specified.
```

**Fix**:
```bash
gcloud compute security-policies rules create 1000 \
    --security-policy=${POC}-armor \
    --expression="true" --action=rate-based-ban \
    --rate-limit-threshold-count=200 \
    --rate-limit-threshold-interval-sec=60 \
    --conform-action=allow \            # ← required
    --exceed-action=deny-429 \          # ← required
    --ban-duration-sec=600
```

Then bind to backend service (the only valid attach point — forwarding rule or URL map won't work):
```bash
gcloud compute backend-services update ${POC}-bs \
    --region=${REGION} --security-policy=${POC}-armor
```

### Gotcha 6: `--ip-version=IPV4` is not accepted on regional addresses

```bash
gcloud compute addresses create ${POC}-glb-ip \
    --region=${REGION} --network-tier=PREMIUM --ip-version=IPV4
# IP Version is not supported for regional addresses.
```

**Fix**: drop `--ip-version`. The default is `IPV4` and it Just Works.

### Gotcha 7: `--enable-proxy-protocol=false` is rejected on `service-attachments create`

```bash
gcloud compute service-attachments create ${POC}-sa \
    --producer-forwarding-rule=${POC}-ilb-fr \
    --enable-proxy-protocol=false   # ← rejected
```

**Fix**: don't pass the flag. Default is `false`; only pass `--enable-proxy-protocol` when you explicitly want `true`. Same for `--connection-preference` (default is `ACCEPT_AUTOMATIC`).

### Gotcha 8: `gcloud compute forwarding-rules create` may error with "default network not found"

A misleading error that appears when the **backend service** was created in a broken state (e.g., `add-backend` failed earlier). Symptom:
```
The resource 'projects/.../global/networks/default' was not found.
```

This is NOT actually about the `default` network. The forwarding-rule create logic does a sanity-check on the backend service's network, and when that sanity-check fails (because the backend service references a NEG that references a network), it surfaces the wrong error. **Fix**: clean up the chain (URL map → proxy → backend service) and rebuild.

### Gotcha 9: Forwarding rule creation requires the proxy-only subnet to be in the SAME VPC as the LB's network

If you accidentally create the proxy-only subnet in a different VPC (e.g., one used for a different test), the forwarding rule creation fails with a confusing error. The fix is to align `--network` on the proxy-only subnet and on the LB chain.

## Cert matching: always compare modulus, never raw bytes

`openssl x509 -noout -pubkey` and `openssl rsa -RSAPublicKey_out` produce **different PEM headers** for the **same** key (PKCS#8 `-----BEGIN PUBLIC KEY-----` vs PKCS#1 `-----BEGIN RSA PUBLIC KEY-----`). A byte-equal comparison (`diff`, `md5`, `sha256`) of the two outputs reports them as different.

**Use modulus comparison**:
```bash
CERT_MOD=$(openssl x509 -in cert.pem -noout -modulus | sed 's/Modulus=//')
KEY_MOD=$(openssl rsa  -in key.pem  -noout -modulus | sed 's/Modulus=//')
[[ "$CERT_MOD" == "$KEY_MOD" ]] && echo "✓ matched" || echo "✗ NOT matched"
```

This was the diagnostic gotcha that exposed the entire "orphan cert+key" red herring in this user's cert directory. Future sessions verifying cert+key should reach for modulus first, not byte-equal.

## Python HTTPS server recipe (the stdlib fallback that works without apt)

When `--no-address` VM + no Cloud NAT is the constraint (typical for fast-POC same-project testing), this Python script serves both `/healthz` (HTTP 80, for GCP LB health check) and `/` (HTTPS 443, with your cert+key) from one process:

```python
import http.server, ssl, os, sys, time, threading, socketserver

CERT = '/opt/tenant/server.crt'
KEY = '/opt/tenant/server.key'
INDEX = '<!DOCTYPE html><html><head><title>OK</title></head><body><h1>OK</h1><p>PSC NEG end-to-end test (HTTPS)</p><p>VM: {}</p></body></html>'

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a, **kw): pass
    def do_GET(self):
        if self.path == '/healthz':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(INDEX.format(os.uname().nodename).encode())

class T(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

# daemon HTTP/80 (for health check)
threading.Thread(target=lambda: T(('0.0.0.0', 80), H).serve_forever(), daemon=True).start()

# blocking HTTPS/443 (with cert)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv = T(('0.0.0.0', 443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
```

Critical import: `from socketserver import ThreadingMixIn` (NOT `from http.server import ThreadingMixIn` — that import path doesn't exist on Debian 11 / Python 3.11, and the `AttributeError: module 'http.server' has no attribute 'ThreadingMixIn'` will fail systemd into a restart loop). systemd unit file:

```ini
[Unit]
Description=Tenant Hello World HTTP+HTTPS server
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -u /opt/tenant/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The cert+key are placed in `/opt/tenant/` from a base64-encoded heredoc in the instance template's startup-script metadata:

```bash
base64 -d > /opt/tenant/server.crt <<'CERT_EOF'
<base64 of cert.pem>
CERT_EOF
base64 -d > /opt/tenant/server.key <<'KEY_EOF'
<base64 of key.pem>
KEY_EOF
chmod 600 /opt/tenant/server.key
```

## Bastion / IAP SSH access for debug

When MIG VMs are `--no-address` and have no external IP, you cannot `gcloud compute ssh` them by default. You need a firewall rule that allows IAP to forward SSH to your VM's network tag:

```bash
gcloud compute firewall-rules create ${POC}-allow-iap-ssh \
    --direction=INGRESS --action=ALLOW --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --network=${VPC} \
    --target-tags=${YOUR_MIG_TAG}     # e.g., 'tenant-backend'
```

Then `gcloud compute ssh ${MIG_INSTANCE} --tunnel-through-iap --zone=${ZONE}` works. The default `allow-ssh-from-iap` rule that ships with most environments only target-tags the bastion VM, not MIG tags — that's why default firewall config isn't enough.

For running gcloud commands from a Mac against a Private GKE cluster (or any cluster with `--enable-master-global-access` and `masterAuthorizedNetworks` set to specific IPs), the standard pattern is the IAP-tunneled bastion:

```bash
gcloud compute ssh ${BASTION_NAME} --zone=${BASTION_ZONE} --tunnel-through-iap \
    --command="gcloud container clusters get-credentials ${CLUSTER} --region=${REGION} --internal-ip"
```

This avoids needing the user's home IP added to `masterAuthorizedNetworks`. The bastion's internal IP must be in the whitelist; this is the canonical "everything through the bastion" pattern.

## IAP SSH inspect-from-MIG pattern

To debug a misbehaving MIG, the standard pattern is:

```bash
# 1. SSH into the MIG VM (after the IAP-SSH firewall rule is in place)
gcloud compute ssh ${MIG_INSTANCE} --zone=${ZONE} --tunnel-through-iap \
    --command="systemctl status ${SERVICE} --no-pager; ss -tlnp | grep -E ':(80|443) '; cat /var/log/startup.log | tail -20"
```

Note: the startup script's `exec > /var/log/startup.log 2>&1` redirects output away from the serial console. To see the actual startup output, you need to either (a) tail `/var/log/startup.log` over SSH, or (b) write the startup without the redirect so it goes to the serial console. The serial-port output (`gcloud compute instances get-serial-port-output`) will only show the kernel + systemd boot sequence, NOT the cloud-init startup script content.

## Process proliferation from Retry clicks (Hermes-related, but cross-cutting pattern)

When a user repeatedly clicks Retry on a failing operation (in this case the Hermes bootstrap, in other cases a CI pipeline, a Terraform apply, etc.), each click spawns a new long-running process while old ones persist. This causes:

- "Could not connect to [service]" — the new process tries to bind to a port already held by an old one
- Multiple instances competing for the same lock
- Memory / FD / port exhaustion

**Diagnostic**:
```bash
ps aux | grep <process-name> | grep -v grep
# Look for: multiple PIDs, similar commands, running for long durations
```

**Fix pattern**:
1. Identify the "intended" one (usually the oldest or the one explicitly restarted by the user)
2. Kill all the others
3. Have the user stop clicking Retry

For Hermes specifically: gateway instances are `python -m hermes_cli.main gateway run`, dashboard instances are `dashboard --no-open --tui --host 127.0.0.1 --port 91XX` (one per port). The pattern is: keep the 1-3 gateway processes alive (those are user workloads), kill all dashboard processes spawned by Retry clicks.

## Health check on backend service vs. backend itself

`gcloud compute backend-services get-health` checks the BACKEND level (does the NEG have healthy endpoints). For a PSC NEG, "healthy" means "the underlying Service Attachment is reachable from this consumer's network and the producer's backend is reporting healthy on its own health check". So:

- For PSC NEG backend: backend health = GCP-managed composite, no need for a separate health check
- For MIG backend: you DO need a health check on the backend service, pointing at a path the MIG can serve

These two patterns are NOT interchangeable. If you copy a `gcloud compute backend-services create` command from a MIG-based LB into a PSC NEG chain without removing `--health-checks`, you'll hit the explicit error in Gotcha 4.

## Validation command sequence (post-creation)

After a full chain is up, run these in order to confirm health before testing with curl:

```bash
# 1. PSC NEG is connected to the SA
gcloud compute network-endpoint-groups describe ${POC}-neg \
    --region=${REGION} --format="json" | jq '.pscConnectionId, .pscTargetService'
# Expect: pscConnectionId is a non-empty number

# 2. Service Attachment has a connected endpoint
gcloud compute service-attachments describe ${POC}-sa \
    --project=${PRODUCER} --region=${REGION} \
    --format="json" | jq '.connectedEndpoints'
# Expect: at least 1 entry with status=ACCEPTED

# 3. Backend service has the NEG as a backend
gcloud compute backend-services describe ${POC}-bs \
    --region=${REGION} --format="json" | jq '.backends'
# Expect: at least 1 backend with group ending in the NEG name

# 4. URL map → backend service binding
gcloud compute url-maps describe ${POC}-um --region=${REGION} \
    --format="get(defaultService)"

# 5. Target HTTPS proxy → URL map + cert
gcloud compute target-https-proxies describe ${POC}-proxy --region=${REGION} \
    --format="get(urlMap, sslCertificates)"

# 6. Forwarding rule → target HTTPS proxy + IP
gcloud compute forwarding-rules describe ${POC}-fr --region=${REGION} \
    --format="get(IPAddress, portRange, target.basename(), loadBalancingScheme)"

# 7. (For ILB chain) backend health
gcloud compute backend-services get-health ${INTERNAL_BS} --region=${REGION}
# Expect: HEALTHY (or HEALTHY for some, depends on which instances are up)
```

Then `curl -k https://${GLB_IP}/ --resolve ${DOMAIN}:443:${GLB_IP}` for the cert+hostname validation. The `--resolve` is required because the IP is regional Anycast and DNS won't naturally resolve a test domain to it.

## IAP bastion + private GKE master pattern (cross-region GKE access)

The same bastion that IAP-tunnels into for SSH can also run `gcloud container clusters get-credentials --internal-ip` against a private GKE master. The `masterAuthorizedNetworks` must whitelist the bastion's internal IP, not the user's home IP. This is the canonical pattern for accessing private GKE from a Mac without exposing the master.

For the user's environment `aibang-12345678-ajbx-dev / europe-west2 / dev-lon-cluster-xxxxxx`:
- Bastion internal IP: e.g., `192.168.0.2`
- GKE master IP: `35.189.124.66` (public, but masterAuthorizedNetworks restricts)
- `masterAuthorizedNetworks` must include `192.168.0.2/32`

```bash
gcloud container clusters update ${CLUSTER} --region=${REGION} \
    --enable-master-authorized-networks \
    --master-authorized-networks=${HOME_IP}/32,${BASTION_INTERNAL_IP}/32
```

## Templates

- `templates/same-project-psc-test-setup/python-https-server.py` — canonical Python stdlib HTTPS server: HTTP 80 + HTTPS 443, daemon-threaded, modulus-verified cert+key at startup. No apt-get install needed. Place at `/opt/tenant/server.py` on the MIG VM.
- `templates/same-project-psc-test-setup/tenant-server.service` — systemd unit file (Type=simple, Restart=always, hardened with NoNewPrivileges + ProtectSystem). Place at `/etc/systemd/system/tenant-server.service`.
- `templates/same-project-psc-test-setup/firewall-iap-ssh-mig.yaml` — the IAP-SSH-to-MIG firewall rule (target-tag=your MIG tag) that default `allow-ssh-from-iap` (target-tag=bastion) doesn't cover.

Planned but not yet written (the user's `public-ingress-external-https-lb.md` already covers most of this for the cross-project variant; for same-project + 2-VPC the script needs adaption):

- `templates/same-project-psc-test-setup/setup-public-ingress.sh` — full one-shot setup using 2-VPC variant (consumer VPC + producer VPC), Cloud NAT, MIG with the python-https-server, regional Internal LB chain, regional External LB chain, Cloud Armor, SSL cert upload. Idempotent + `LB_SCHEME` env var switchable.
- `templates/same-project-psc-test-setup/verify-public-ingress.sh` — 3-layer verify: resource existence, association, real HTTPS traffic (with `--resolve domain:443:glb_ip`).
- `templates/same-project-psc-test-setup/cleanup-public-ingress.sh` — reverse-order delete, preserving pre-existing subnets.

## See also

- `references/cross-project-psc-architecture.md` — the **cross-project** pattern this same-project pattern is a special-case variant of. The 5 critical gotchas (proxy-only subnet, region flags, Shared VPC IAM, restricted-environment bypass) all apply identically.
- The user's local `public-ingress-external-https-lb.md` — concrete application of the cross-project pattern to `aibang-12345678-ajbx-dev`. For same-project testing in this environment, the same chain applies but with the 2-VPC variant (Workaround #1) and the same-project + same-VPC limitation is the first thing to know about.
- `knowledge/gcp/psa-psc/service-attachment-region.md` — when the SA's region differs from the consumer's region, the Global Access flags apply (separate concept, not the same-project limitation).
