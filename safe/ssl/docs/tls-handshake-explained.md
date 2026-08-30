# TLS Handshake — Explained

> What actually happens in the few hundred milliseconds after your browser
> types `https://...` and before the first byte of HTML comes back.

The TLS handshake is the protocol negotiation that turns an anonymous TCP
socket into an encrypted, integrity-protected, server-authenticated
channel — and (optionally) authenticates the client too. RFC 8446 defines
the modern version (TLS 1.3, August 2018); older TLS 1.2 still rides out
in the wild but the protocol shape is fundamentally different.[1][3]

This doc walks through (1) the **goals** the handshake achieves, (2) the
**classic TLS 1.2 handshake** step by step, (3) the **TLS 1.3 redesign** and
why it is half the round-trips, (4) the **two resumption modes** (PSK and
0-RTT), and (5) **practical verification** with `openssl s_client`.

A companion HTML flow diagram — `tls-handshake-flow.html` next to this
file — renders the message sequence as a vertical swim-lane SVG so you
can see exactly which message travels which direction in each phase.

---

## 1. Why a handshake at all

TLS is not the encryption itself — it's the **agreement** on which keys,
algorithms, and identities to use. Encryption only works *after* both
sides share a secret, and a secret shared over an open network requires
key agreement (Diffie–Hellman) or key transport (encrypt with peer's
public key).

RFC 8446 frames the goal plainly — the handshake lets "peers negotiate a
protocol version, select cryptographic algorithms, optionally
authenticate each other, and establish shared secret keying material.
Once the handshake is complete, the peers use the established keys to
protect the application-layer traffic."[1]

The handshake must solve four problems at once:

1. **Negotiate protocol version and cipher suite** — both sides may speak
   TLS 1.0/1.1/1.2/1.3, AES/ChaCha20/3DES, RSA/ECDSA, etc. (MDN: "Client
   and server agree on which version of TLS to use" and "agree on the
   cipher suite that they will use: this defines the algorithms that they
   will use for key agreement, authentication, encryption, and message
   authentication.")[2]
2. **Authenticate the server** (and optionally the client) — bind the
   peer's identity to a public key via a certificate chain signed by a
   trusted CA, so the client knows it is talking to `example.com` and
   not an MITM. MDN notes that "server authentication, in which the
   server proves who they are to the client, is a fundamental part of
   web security."[2]
3. **Establish a shared secret** that no eavesdropper can reconstruct,
   even one who records every byte of the handshake. MDN: "Client and
   server agree on a secret key that they will use to encrypt and
   decrypt messages."[2]
5. **Derive traffic keys** from that secret so subsequent application
   data can be encrypted *and* authenticated (AEAD).

MDN summarises the three guarantees TLS adds on top of TCP:

> "Encryption: the data exchanged between client and server is encrypted
> while in transit, so it can't be read by any attackers. Integrity: an
> attacker can't secretly modify data (without detection) while it is in
> transit between client and server. Authentication: client and server
> are each able to prove to the other party that they are the entity
> they claim to be."[2]

MDN also names the threat model explicitly: "In particular, HTTPS is the
defense against a manipulator in the middle (MITM) attack, in which the
attacker inserts themselves between the user's browser and the server
they are connecting to, and can read and modify the traffic
exchanged."[2]

---

## 2. The classic TLS 1.2 handshake (the one most textbooks still draw)

TLS 1.2 takes **two round-trips** between client and server before any
application data flows. The message sequence is:[3]

```
Client                              Server
   |-------- ClientHello ----------->|   ① cipher suites + random
   |<------- ServerHello ------------|   ② chosen suite + random
   |<------- Certificate ------------|   ③ server's X.509 chain
   |<------- ServerHelloDone --------|   ④ "I'm done with my half"
   |-------- ClientKeyExchange ----->|   ⑤ PreMasterSecret (or DH)
   |-------- ChangeCipherSpec ------>|   ⑥ "switching to encrypted"
   |-------- Finished (encrypted) -->|   ⑦ MAC over the whole handshake
   |<------- ChangeCipherSpec -------|   ⑧ same, server side
   |<------- Finished (encrypted) ---|   ⑨ MAC over the whole handshake
   |        (application data)       |
```

**Step by step, what's actually in each message:**

### ① ClientHello
- Highest protocol version the client speaks (e.g. `TLS 1.2`).
- 32-byte client random (nonce).
- Session ID (may be empty; lets server reuse a previous session).
- List of cipher suites the client supports, e.g.
  `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`.
- List of compression methods (usually `null`).
- Extensions: SNI (server name), supported elliptic-curve groups,
  signature algorithms, ALPN (which application protocol — `h2`,
  `http/1.1`), etc.

### ② ServerHello
- The chosen protocol version, cipher suite, compression method.
- 32-byte server random.
- Session ID (echo of client's, or new).

### ③ Certificate
- Server's X.509 certificate chain, leaf first.
- Chain must verify against a trusted root the client has.
- Certificate binds a public key + subject (DNS name) + issuer CA
  signature. As Wikipedia puts it: "The certificate contains the server
  name, the trusted certificate authority (CA) that vouches for the
  authenticity of the certificate, and the server's public encryption
  key."[3]

### ④ ServerHelloDone
- Server's cleartext half is finished.

### ⑤ ClientKeyExchange — the actual key material
Two flavours depending on the chosen cipher suite:

- **RSA key transport** (legacy, removed in TLS 1.3): the client
  generates a 48-byte `PreMasterSecret`, encrypts it with the server's
  RSA public key from the certificate, and sends the ciphertext.
- **(EC)DHE key agreement**: the client sends its ephemeral Diffie–
  Hellman public value (`ClientDHParams`). Both sides now combine their
  own DH private value with the peer's DH public value to derive the
  same `PreMasterSecret` — and crucially, no one watching the wire can
  reconstruct it (that's the discrete-log / elliptic-curve hardness).[3]

### ⑥ / ⑧ ChangeCipherSpec
- One-byte signal: "all messages I send *after* this one are encrypted
  with the just-negotiated keys."
- This message is **not** a handshake message — it's a record-layer
  marker, which is one of the design warts TLS 1.3 removed.

### ⑦ / ⑨ Finished (encrypted)
- A MAC (in TLS 1.2, HMAC over a hash of all preceding handshake
  messages) proves both sides derived the same keys.
- This is what binds the keys to the handshake transcript — without it,
  a MITM could rewrite the ClientHello and rerun the whole protocol
  silently.

### Deriving traffic keys
Both sides take:
```
master_secret = PRF(pre_master_secret, "master secret",
                    client_random || server_random)
                [0..47]
key_block     = PRF(master_secret, "key expansion",
                    server_random || client_random)
                [: length needed for keys + IVs]
```
Then split `key_block` into client_write_MAC_key,
server_write_MAC_key, client_write_key, server_write_key, plus IVs.
Every cipher suite specifies exactly how the split happens.

### 2.5 What if ServerHello never comes? (the failure path)

The previous sections all describe the **success** path: ClientHello → ServerHello
→ Certificate → ... → Finished → application data. But the whole negotiation
can fail before any of that, and the failure mode is precisely defined by
RFC.

The server picks the cipher suite in step ② by intersecting **its own enabled
list** with the client's `cipher_suites` in ClientHello. If that intersection
is empty — the server supports nothing the client offered — the server
**never sends a ServerHello**. Instead it sends a **fatal Alert** and closes
the TCP connection.

The canonical wording is in RFC 5246 §7.4.1.3 (Server Hello):

> "The server will send this message in response to a ClientHello message
> **when it was able to find an acceptable set of algorithms. If it cannot
> find such a match, it will respond with a handshake failure alert.**"[4]

Two alert descriptions cover this case. From RFC 5246 §7.2.2:

> **`handshake_failure`** (alert 40) — "Reception of a handshake_failure
> alert message indicates that the sender was unable to negotiate an
> acceptable set of security parameters given the options available.
> **This is a fatal error.**"[4]

> **`insufficient_security`** (alert 71) — "Returned instead of
> handshake_failure **when a negotiation has failed specifically because
> the server requires ciphers more secure than those supported by the
> client.** This message is always fatal."[4]

Both alerts are **fatal** (level 2): the sender must terminate the connection
after sending them. There is no recovery, no retry with different parameters
within the same TCP connection — the client must open a fresh connection
with a different ClientHello (e.g. newer JRE, different cipher list, JCE
Unlimited Strength installed).

```
Client                              Server
   |-------- ClientHello ----------->|   ① client offers cipher list
   |                                  |     [TLS_RSA_WITH_AES_128_CBC_SHA,
   |                                  |      TLS_RSA_WITH_AES_256_CBC_SHA,
   |                                  |      ... only legacy stuff]
   |                                  |
   |                                  |  server: intersect(client_list,
   |                                  |                server_enabled_list)
   |                                  |  → ∅ (no overlap)
   |                                  |
   |<------- Alert (level=fatal, -----|  ② ServerHello never sent.
   |         description=             |     RFC 5246 §7.4.1.3:
   |         handshake_failure 40     |     "respond with a handshake
   |         OR                       |      failure alert"
   |         insufficient_security 71)|
   |<------- close_notify (optional)-|  ③ server closes TCP
   X                                 X
```

**Three concrete things to notice**:

1. **No ServerHello ever goes on the wire.** The client sees: ClientHello
   out → Alert in → TCP close. No `Cipher is:` line in `openssl s_client`
   output; the line is empty or absent.
2. **The choice between alert 40 vs 71 is academic in practice.** Most
   servers (Java JSSE, Nginx, Apache) send `handshake_failure` (40) for
   both "no overlap" and "client ciphers too weak" — the dedicated
   `insufficient_security` (71) alert is technically more precise for
   the pod-curl case (server requires more secure ciphers than client
   supports) but rarely used.
3. **Application data never flows.** The whole 9-step handshake
   diagram above (steps ①–⑨) collapses at step ②. No certificate, no
   key exchange, no Finished, no HTTP request. This is why the log line
   is `Received fatal alert: handshake_failure` (no JSON body, no HTTP
   status) — the application layer was never reached.

This is the **exact failure mode in `develop/java/java-auth/pod-curl.md` §4**:
the Java client (running an old JRE with a legacy-only cipher list) sent
ClientHello to a third-party server that had been hardened to require
ECDHE/GCM/CBC-SHA256+. The intersection was empty, the server sent
`handshake_failure`, and the Java client's `SSLSocket` raised
`SSLHandshakeException: (handshake_failure) Received fatal alert:
handshake_failure` at the application layer. See that doc for the
specific Java / JRE / JCE Unlimited Strength remediation.

#### How to confirm with `openssl s_client`

Run a deliberately weak ClientHello against any server that supports only
strong ciphers (the third-party's II1711-hardened endpoint, or any server
running modern Nginx with `ssl_protocols TLSv1.2; ssl_ciphers
ECDHE+AESGCM:...`):

```bash
# Force a ClientHello with ONLY legacy RSA-CBC ciphers — the modern server
# will have nothing to pick from
openssl s_client -connect <host>:443 -tls1_2 \
    -cipher 'AES128-SHA:AES256-SHA:DES-CBC3-SHA' \
    -servername <host> </dev/null 2>&1 | grep -E 'Cipher|alert|error|handshake'

# Expected (failure-path):
#   ---
#   New, (NONE), Cipher is (NONE)
#   ---
#   4077xxx:error:...:ssl/.../statem_clnt.c:...
#     tlsv1 alert handshake failure
#   ---
#   SSL handshake has read 7 bytes and written N bytes
#     (read ≈ 7 = exactly one TLS Alert record = alert level(1) + desc(1)
#      + back-reference 7 bytes; written = size of your ClientHello)
#
# Successful path would show:
#   New, TLSv1.2, Cipher is ECDHE-RSA-AES128-GCM-SHA256
#   SSL handshake has read ~3000 bytes and written ~200 bytes
```

The 7-byte read is the diagnostic smoking gun: a TLS Alert record is
exactly 7 bytes (ContentType=21 alert + ProtocolVersion=0x0303 + length=2
+ AlertLevel=2 fatal + AlertDescription=40/71 handshake_failure /
insufficient_security), so when you see `read 7 bytes and written
ClientHello-size bytes`, the server told you "no overlap" without ever
sending a ServerHello.

---

## 3. TLS 1.3 — what changed and why it is faster

RFC 8446 §1.2 lists the major functional differences.[1] The headline
ones:

> "The list of supported symmetric encryption algorithms has been pruned
> of all algorithms that are considered legacy. Those that remain are
> all Authenticated Encryption with Associated Data (AEAD) algorithms."

> "Static RSA and Diffie-Hellman cipher suites have been removed; all
> public-key based key exchange mechanisms now provide forward
> secrecy."

> "All handshake messages after the ServerHello are now encrypted. The
> newly introduced EncryptedExtensions message allows various
> extensions previously sent in the clear in the ServerHello to also
> enjoy confidentiality protection."

> "A zero round-trip time (0-RTT) mode was added, saving a round trip
> at connection setup for some application data, at the cost of certain
> security properties."[1]

Putting those bullets together, the **new flow is one round-trip** for
a full handshake, and (with a resumption ticket) zero round-trips for
0-RTT:

```
Client                                           Server
                                                  (no encryption yet)
ClientHello
  + key_share          -------->
  + signature_algorithms
  + supported_versions                 ServerHello
  + psk_key_exchange_modes             + key_share
  + pre_shared_key        (optional)   {EncryptedExtensions}
                                       {CertificateRequest*}
                                       {Certificate*}
                                       {CertificateVerify*}
                                       {Finished}            <-- server half encrypted
                            <--------
[Application Data]  <------->  [Application Data]         <-- everything below this line is encrypted
{Certificate*}
{CertificateVerify*}
{Finished}            -------->
[Application Data]  <------->  [Application Data]
```

(Notation: `{}` = encrypted with handshake-traffic key, `[]` = encrypted
with application-traffic key, `*` = optional, `+` = noteworthy
extension. Figure 1 in RFC 8446 §2.[1])

### What the client sends upfront — the crucial change

The client's `key_share` extension in the **first** ClientHello carries
its ephemeral ECDHE public value. The server picks a group from the
client's offered shares and replies with its own `key_share`. Both sides
can now compute the shared secret immediately, without waiting for a
second round-trip. That is what collapses the 2-RTT TLS 1.2 handshake
into 1-RTT TLS 1.3.

If the server doesn't support any of the client's offered key shares
(e.g. only X25519, but the client offered only P-256), the server sends
a `HelloRetryRequest` and the client retries with a `key_share` in the
agreed group — adding one half-RTT.

### What is encrypted now

TLS 1.3 encrypts **everything** after the ServerHello:
- Certificate (so server identity is hidden from passive observers).
- CertificateVerify (signature over the handshake transcript).
- Finished (key confirmation MAC).
- New: `EncryptedExtensions` carries extension responses that used to
  be cleartext.

This is a strict upgrade over TLS 1.2, where anyone watching the wire
sees the server's certificate (and thus which CA the server uses, what
DNS name it claims, etc.).

### Cipher suite reshuffle

TLS 1.2 suites looked like
`TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` — one big blob that named the
key exchange, authentication, encryption, and MAC algorithms together.
TLS 1.3 splits that into independent choices:
- Key exchange: `(EC)DHE` only (forward secrecy mandatory)
- Authentication: `RSA` / `ECDSA` / `EdDSA` (named in
  `signature_algorithms` extension)
- Bulk encryption + hash: e.g. `TLS_AES_128_GCM_SHA256`
- All AEAD — no more CBC + HMAC combos

So a TLS 1.3 suite name encodes only the AEAD + hash, e.g.
`TLS_AES_128_GCM_SHA256`, `TLS_CHACHA20_POLY1305_SHA256`,
`TLS_AES_256_GCM_SHA384`. The server can pick any AEAD it supports;
the client must be able to negotiate independently of auth and KEX.

---

## 4. Resumption — PSK and 0-RTT

A full ECDHE handshake costs roughly one RTT in TLS 1.3 (two in 1.2),
plus the CPU cost of an ephemeral key generation and a signature
verification. For a browser opening many short connections to the same
origin, that's wasteful. TLS 1.3 supports two resumption modes, both
using **pre-shared keys (PSKs)** established during a previous
connection.[1]

### 4.1 PSK resumption (1-RTT)

After a successful handshake, the server can send a
`NewSessionTicket` containing a PSK identity and a ticket (an opaque
blob the server generated; the client can't decrypt it).

On the next connection, the client includes:
- `pre_shared_key` extension — list of PSK identities it has, including
  the ticket.
- `psk_key_exchange_modes` — `PSK with (EC)DHE` (recommended) or
  `PSK-only` (no forward secrecy).

The server decrypts the ticket, recovers the PSK, and uses it to
derive the handshake secret instead of (or in addition to) the ECDHE
key. The result is still 1-RTT, but the server skips its signature
operation — slightly cheaper.[1]

### 4.2 0-RTT — zero round-trips, weaker security

When the client has a PSK and wants to send data immediately, it can
**piggyback application data on the very first ClientHello**:

```
Client                                           Server
ClientHello
  + early_data
  + key_share*
  + psk_key_exchange_modes
  + pre_shared_key
(Application Data*)  -------->
                                              ServerHello + pre_shared_key + key_share*
                                              {EncryptedExtensions} + early_data*
                                              {Finished}
                              <--------
[Application Data]  <------->  [Application Data]
(EndOfEarlyData)
{Finished}            -------->
[Application Data]
```

(Source: RFC 8446 Figure 4, §2.3.[1])

The early data is encrypted with a key derived from the PSK alone —
which means **forward secrecy is lost for that first batch of bytes**:
if the PSK is later compromised, an attacker who recorded the 0-RTT
flight can decrypt it.

There is also a **replay** concern. Because the server doesn't yet know
if this is a fresh client, it can't tell whether the same ClientHello
was already received and processed. RFC 8446 §2.3 spells this out and
recommends either a single-use ticket (consume on first use) or a
server-side freshness check.[1]

Practical guidance: enable 0-RTT only for **idempotent** requests (GETs
that don't change server state), never for POSTs that mutate.

---

## 5. What `openssl s_client` shows you

Run:

```bash
openssl s_client -connect example.com:443 -servername example.com
```

The output, top to bottom:

| Line | What it tells you |
|------|-------------------|
| `CONNECTED(00000005)` | TCP socket opened. |
| `depth=2 O = ...` | Walking up the server's cert chain. |
| `verify return:1` / `verify return:0` | Chain validation result. |
| `Server certificate` | PEM dump of the leaf cert. |
| `subject=CN = example.com` | What the cert claims to identify. |
| `issuer=CN = ...` | Who signed it. |
| `SSL handshake has read N bytes and written M bytes` | Handshake complete; bytes exchanged. |
| `New, TLSv1.3, Cipher: TLS_AES_128_GCM_SHA256` | **Negotiated version and cipher.** |
| `Protocol : TLSv1.3` | Confirmed protocol. |
| `Verification: OK` | Cert chain valid against local trust store. |

Add `-tls1_2` or `-tls1_3` to force a version, `-cipher '...'` to force
a specific cipher suite, `-debug` to see the raw record contents.

If you see `verify error:num=20:unable to get local issuer certificate`,
the client machine doesn't trust the root CA that signed the server's
chain — fix by adding the missing CA to the OS trust store or pointing
`-CAfile` at a custom bundle.

---

## 6. Cheat-sheet — message direction at a glance

| Message | TLS 1.2 direction | TLS 1.3 direction | Encrypted? |
|---------|--------------------|--------------------|------------|
| ClientHello | C → S | C → S | clear |
| ServerHello | S → C | S → C | clear |
| Certificate | S → C | S → C | TLS 1.2 clear, TLS 1.3 encrypted |
| ServerKeyExchange | S → C | (folded into ServerHello extensions) | TLS 1.2 clear |
| ServerHelloDone | S → C | (removed) | TLS 1.2 clear |
| ClientKeyExchange | C → S | (folded into ClientHello `key_share`) | TLS 1.2 clear |
| CertificateRequest | S → C | S → C | TLS 1.3 encrypted |
| CertificateVerify | S → C / C → S | S → C / C → S | TLS 1.3 encrypted |
| Finished | S → C / C → S | S → C / C → S | TLS 1.2 encrypted, TLS 1.3 encrypted |
| ChangeCipherSpec | both | **removed** (middlebox compat only) | n/a |

---

## 7. Where to go next

- `tls-handshake-flow.html` — visual swim-lane of the TLS 1.3 1-RTT
  handshake with a side-by-side comparison to TLS 1.2.
- `cipher-suites-explained.md` (in the same `docs/` dir) — what each
  algorithm choice actually buys you.
- `pem-get-ssl.md` — reading the certificates you get out of the
  handshake.
- `why-san.md` — why the Subject Alternative Name in the certificate
  matters for the handshake to succeed.
- RFC 8446 (TLS 1.3) — canonical spec; §2 has the message diagrams.[1]
- RFC 5246 (TLS 1.2) — the older spec, still useful for cross-version
  diffs.
- MDN "Transport Layer Security (TLS)" — the clearest non-RFC
  explanation of the goals.[2]

---

## Sources

[1] RFC 8446 - The Transport Layer Security (TLS) Protocol Version 1.3 — https://www.rfc-editor.org/rfc/rfc8446
[2] MDN - Transport Layer Security (TLS) — https://developer.mozilla.org/en-US/docs/Web/Security/Transport_Layer_Security
[3] Wikipedia - Transport Layer Security — https://en.wikipedia.org/wiki/Transport_Layer_Security
[4] RFC 5246 - The Transport Layer Security (TLS) Protocol Version 1.2 — https://www.rfc-editor.org/rfc/rfc5246 (cited in §2.5 for the ServerHello rule "if it cannot find such a match, it will respond with a handshake failure alert" and the two alert descriptions `handshake_failure` 40 / `insufficient_security` 71)