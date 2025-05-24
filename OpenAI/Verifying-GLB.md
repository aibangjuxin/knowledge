# Verifying GCP Global Load Balancer mTLS Configuration Prior to DNS Cutover

## 1. Introduction: Ensuring Your GCP GLB mTLS Configuration is Ready

Mutual Transport Layer Security (mTLS) provides a robust mechanism for two-way authentication, ensuring that both the client and the server cryptographically verify each other's identities before establishing a secure connection.1 This contrasts with traditional TLS, where typically only the server authenticates itself to the client. Implementing mTLS is a significant step towards a zero-trust security model, demanding mutual verification and establishing a high degree of trust for communications.2

Before redirecting production traffic to a Google Cloud Platform (GCP) Global Load Balancer (GLB) newly configured with mTLS, comprehensive verification is paramount. A premature DNS cutover without thorough pre-flight checks can lead to service disruptions, client authentication failures, or unintended security misconfigurations. This report outlines methods to rigorously test the mTLS setup by directly targeting the GLB's IP address, interpreting client-side tool outputs, and analyzing relevant GCP logs.

A primary challenge when verifying mTLS by directly targeting an IP address, such as `120.120.88.88`, revolves around Server Name Indication (SNI). SNI is a TLS extension allowing the client to indicate the hostname it is attempting to reach during the handshake. This is crucial because the GLB's mTLS policy is often associated with a specific server certificate, which in turn is tied to a domain name, not directly to the IP address. Simply connecting to the IP address via HTTPS might test basic TLS connectivity but may not accurately reflect the mTLS behavior intended for the specific domain. Furthermore, understanding how to access and interpret GCP's logging mechanisms is essential for gaining a server-side perspective on the mTLS handshake, identifying successful validations, and diagnosing failures. This document aims to provide comprehensive guidance on these aspects.

Undertaking verification before a DNS switch serves as a critical risk mitigation strategy. Once DNS records are updated, the GLB's IP address becomes the authoritative endpoint for the domain. If the mTLS configuration is flawed—due to issues such as incorrect Certificate Authority (CA) trust settings, improper client validation modes, or unaddressed SNI complications—clients attempting to connect via the domain name will likely encounter mTLS handshake failures. Such failures can manifest as widespread service outages for legitimate users or, conversely, create security vulnerabilities if mTLS is inadvertently bypassed. Testing the configuration with the GLB's direct IP address, while correctly simulating domain-based access through SNI manipulation, allows for the isolation and remediation of GLB-specific mTLS issues without affecting live production traffic.

## 2. Pre-DNS Switch Verification: Testing mTLS Against the GLB IP Address

When a client attempts an HTTPS connection directly to an IP address, the SNI field in the TLS ClientHello message may not be sent, or it may contain the IP address itself rather than the intended hostname.3 This behavior poses a significant challenge for verifying mTLS configurations on services like GCP GLBs.

GCP GLBs, particularly when hosting multiple domains or services, rely on the SNI provided by the client to select the appropriate SSL certificate.4 Each SSL certificate can have an associated mTLS policy (configured via a `ServerTlsPolicy` or Client Authentication resource). If the SNI is missing or does not match a configured hostname for which a certificate and mTLS policy are defined, the GLB might present a default certificate (if available), an incorrect certificate, or fail to apply the intended mTLS policy altogether. This means that a test against the IP address without proper SNI handling might result in a successful basic TLS handshake, perhaps with a default certificate that doesn't enforce mTLS, leading to a false positive conclusion that the mTLS setup for the specific domain is functional.

The methods detailed in subsequent sections, specifically using the `--resolve` option with `curl` or the `-servername` option with `openssl s_client`, are therefore not merely conveniences but essential mechanisms for accurate pre-DNS switch mTLS validation. These options allow the testing tool to connect to the GLB's raw IP address while still presenting the _intended hostname_ in the SNI field of the TLS ClientHello message. This forces the GLB to behave as if the request originated through the domain name, thereby selecting the correct server certificate and applying the associated mTLS policy. This ensures that the test conditions accurately mirror how the GLB will process requests after the DNS records are updated to point to its IP address.

## 3. Method 1: Using `curl` for mTLS Verification

The `curl` command-line tool is a versatile utility for transferring data with URLs and can be effectively used to test mTLS configurations.

### Constructing the `curl` Command

To perform an mTLS test with `curl`, several options are necessary:

- `--cert <client_cert_file>[:<password>]`: Specifies the path to the client's PEM-formatted certificate file. If the private key is also in this file, this might be sufficient. If the private key is password-protected and part of this file, the password can be appended after a colon.5
- `--key <client_key_file>`: Specifies the path to the client's PEM-formatted private key file.5
- `--cacert <ca_bundle_file>`: Specifies a file containing PEM-formatted CA certificates to be used for verifying the server's certificate.6 This bundle should include the CA certificate(s) that signed the GLB's server certificate.
- `-v` or `--verbose`: Enables verbose output, which displays detailed information about the connection and TLS handshake.7
- The URL should be constructed using `https://<GLB_IP_ADDRESS>`.

### Forcing Hostname Resolution for SNI with `curl --resolve`

To ensure the GLB receives the correct SNI and applies the domain-specific mTLS policy, the `--resolve`option is critical when testing against an IP address. This option pre-populates `curl`'s DNS cache with a specific IP address for a given hostname and port combination.3

The syntax is: `curl --resolve <hostname>:<port>:<IP_address> https://<hostname> [other_options]`.3

For example, to test mTLS for `your.domain.com` which will eventually point to GLB IP `120.120.88.88`:

Bash

```
curl --resolve your.domain.com:443:120.120.88.88 \
     -v \
     --cert client_certificate.pem \
     --key client_private_key.pem \
     --cacert server_ca_bundle.pem \
     https://your.domain.com
```

This command instructs `curl` to connect to `120.120.88.88` for any requests to `your.domain.com` on port 443, while ensuring that `your.domain.com` is used in the SNI field of the TLS handshake.

### Interpreting `curl -v` Verbose Output

The verbose output from `curl` provides a step-by-step account of the connection and TLS handshake. Key lines to examine for mTLS verification include 7:

- `* Trying <IP_address>...`
- `* Connected to <hostname> (<IP_address>) port <port> (#0)`: Confirms connection to the resolved IP.
- `* ALPN, offering h2, http/1.1`: Client offers Application-Layer Protocol Negotiation.
- `* TLSv1.x (OUT), TLS handshake, Client hello (1)`: Client initiates the TLS handshake.
- `* TLSv1.x (IN), TLS handshake, Server hello (2)`: Server responds with its hello message.
- `* TLSv1.x (IN), TLS handshake, Certificate (11)`: Server sends its certificate chain.8
- `* TLSv1.x (IN), TLS handshake, Request CERT (13)`: **This is a crucial indicator for mTLS.** It signifies that the server is requesting a certificate from the client.6 If this line is absent, the GLB is likely not configured to request a client certificate for this connection, which could be due to SNI issues, an incorrect mTLS policy application, or a permissive `clientValidationMode` where the client chose not to send one.
- `* TLSv1.x (OUT), TLS handshake, Certificate (11)`: Client sends its certificate. This should appear after the server's "Request CERT" message if the client is configured with a certificate.
- `* TLSv1.x (OUT), TLS handshake, Client key exchange (16)`: Client sends key exchange information.
- `* TLSv1.x (OUT), TLS handshake, Certificate verify (15)`: **Another critical mTLS indicator.** The client sends a digital signature to prove possession of the private key corresponding to the public key in the certificate it presented.
- `* SSL connection using TLSv1.x / <CipherSuite>`: Indicates a successful TLS handshake, including the negotiated cipher.
- `* Server certificate:... subject: CN=<server_hostname>... issuer:...`: Details of the server's certificate.
- `* SSL certificate verify ok.` : Confirms that the server's certificate was successfully verified against the CA bundle provided via `--cacert`. If this fails (e.g., "SSL certificate problem: unable to get local issuer certificate"), it indicates an issue with trusting the server's certificate, which must be resolved before mTLS-specific steps can be properly tested. This failure occurs before the server would typically request a client certificate.
- An HTTP response code (e.g., `HTTP/1.1 200 OK`). If mTLS fails after the handshake appears to complete, or if the client certificate is rejected, specific HTTP error codes like `400 Bad Request` (with a body like "No required SSL certificate was sent") or `403 Forbidden` might be returned.10 Other TLS handshake errors might terminate the connection even before an HTTP status is returned.

The order and presence of these messages, particularly the "Request CERT (13)" from the server and the subsequent "Certificate (11)" and "Certificate verify (15)" from the client, directly evidence the mTLS flow.

**Table 1: `curl` mTLS Command Options**

|   |   |   |
|---|---|---|
|**Option**|**Description**|**Example Usage**|
|`--cert <file>[:<password>]`|Specifies the client certificate file (PEM format) and optional password if the key is embedded and encrypted. 5|`--cert client.pem:password123`|
|`--key <file>`|Specifies the client private key file (PEM format). 5|`--key client.key`|
|`--cacert <file>`|Specifies a CA bundle file (PEM format) to verify the server's certificate. 6|`--cacert ca-bundle.pem`|
|`--resolve <host>:<port>:<ip_address>`|Provides a custom IP address for a hostname and port, ensuring correct SNI. 3|`--resolve example.com:443:1.2.3.4`|
|`-v`, `--verbose`|Enables verbose output, showing detailed connection and handshake information. 7|`-v`|
|`-H "Header: Value"`|Adds a custom HTTP header. Can be used to test backend behavior with mTLS headers if `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` mode is used.|`-H "X-Custom-Auth: true"`|

**Table 2: Interpreting Key `curl -v` mTLS Handshake Stages**

|   |   |   |
|---|---|---|
|**Verbose Output Snippet Pattern**|**Meaning in mTLS Context**|**What to Look For (Success/Failure)**|
|`* TLSv1.x (IN), TLS handshake, Request CERT (13)`|Server is requesting a client certificate. **Essential for mTLS.** 9|**Success:** Presence of this message. **Failure/Concern:** Absence may indicate mTLS is not being enforced for this connection.|
|`* TLSv1.x (OUT), TLS handshake, Certificate (11)`|Client is sending its certificate in response to the server's request.|**Success:** Presence after "Request CERT". **Failure/Concern:** Absence if "Request CERT" was seen and client should send a cert.|
|`* TLSv1.x (OUT), TLS handshake, Certificate verify (15)`|Client is proving possession of the private key for the sent certificate.|**Success:** Presence after client sends its certificate. **Failure/Concern:** Absence can indicate key mismatch or other issues.|
|`* SSL certificate verify ok.`|Server's certificate is trusted by the client (based on `--cacert`).|**Success:** This message. **Failure:** Error messages like "unable to get local issuer certificate".|
|`> GET / HTTP/1.1... < HTTP/1.1 200 OK`|Successful HTTP transaction after TLS handshake.|**Success:** Expected HTTP response (e.g., 200). **Failure:** HTTP errors (400, 403) or TLS connection termination.|
|`< HTTP/1.1 400 Bad Request`(body may indicate "No required SSL certificate was sent")|Server rejected the request, often due to missing or invalid client certificate. 10|**Failure:** Indicates mTLS enforcement rejected the client.|

## 4. Method 2: Using `openssl s_client` for Granular mTLS Analysis

The `openssl s_client` command is another powerful tool for diagnosing SSL/TLS connections, including mTLS. It often provides more granular details of the TLS handshake messages.

### Command Syntax for mTLS

Key options for `openssl s_client` in an mTLS context include 11:

- `-connect <GLB_IP_ADDRESS>:<port>`: Specifies the server IP address and port to connect to.
- `-servername <hostname>`: This is crucial for SNI. It sets the Server Name Indication extension in the ClientHello message to the specified hostname (e.g., `your.domain.com`).
- `-cert <client_cert_file.pem>`: Specifies the client's PEM-formatted certificate file.
- `-key <client_key_file.pem>`: Specifies the client's PEM-formatted private key file.
- `-CAfile <ca_bundle_file.pem>`: Provides a file of PEM-formatted CA certificates to be used when verifying the server's certificate.
- `-verify <depth>` (e.g., `-verify 2`): Turns on server certificate verification up to the specified chain depth. Using `-CAfile` typically implies verification.

Example command:

Bash

```
openssl s_client -connect 120.120.88.88:443 \
                 -servername your.domain.com \
                 -cert client_certificate.pem \
                 -key client_private_key.pem \
                 -CAfile server_ca_bundle.pem
```

### Interpreting `openssl s_client` Output

The output of `openssl s_client` is verbose by default. Key sections to analyze are:

- `CONNECTED(00000003)`: Indicates a successful TCP connection.
- `---CertificatePRequest---`: This section, if present, details the server's request for a client certificate. It may list:
    - `Acceptable client certificate CA names`: A list of Distinguished Names (DNs) of CAs the server trusts for client certificates. **Note:** GCP GLBs may not always send the `certificate_authorities`extension, which populates this list.13 If this list is absent, the client must infer which certificate to send or be pre-configured.
    - `Client Certificate Types`: The types of client certificates the server is willing to accept (e.g., RSA sign, ECDSA sign).
- Server Certificate Details: Information about the certificate presented by the server (subject, issuer, validity period).
- `---SSL handshake has read xxxx bytes and written xxxx bytes---`: Summary of handshake data.
- `Verification: OK` or `Verify return code: 0 (ok)`: Indicates that the server's certificate was successfully verified against the CAs provided in `-CAfile`. Failures here will show different codes and error messages.
- Session Parameters: Details about the negotiated TLS version, cipher suite, session ID, etc.
- If the handshake is successful, the tool will then wait for input, allowing HTTP commands (e.g., `GET / HTTP/1.1\nHost: your.domain.com\n\n`) to be typed and sent to the server.
- Common errors include "no certificate returned" if the client doesn't send one when requested, or various handshake failure messages if certificates are invalid, keys don't match, or trust cannot be established.

`openssl s_client` can provide more detailed insight into the `CertificateRequest` message from the server compared to `curl`. If the server does send a list of acceptable CAs, `openssl s_client` is more likely to display this information, which can be invaluable for debugging scenarios where a client certificate is provided but rejected by the server. The potential absence of the `certificate_authorities` extension from GCP GLBs, as suggested by some community discussions 13, means that clients might need to be explicitly configured to present the correct certificate for `your.domain.com`, as the server may not provide a list of its trusted CAs to guide the client's selection process during the handshake. This elevates the importance of thorough client-side configuration and testing.

**Table 3: `openssl s_client` mTLS Command Options**

|   |   |   |
|---|---|---|
|**Option**|**Description**|**Example Usage**|
|`-connect <host>:<port>`|Specifies the server IP address (or hostname) and port to connect to. 11|`-connect 120.120.88.88:443`|
|`-servername <name>`|Sets the TLS SNI extension in the ClientHello to the given hostname. Crucial for IP-based testing. 11|`-servername your.domain.com`|
|`-cert <file>`|Specifies the client certificate file (PEM format). 11|`-cert client.pem`|
|`-key <file>`|Specifies the client private key file (PEM format). 11|`-key client.key`|
|`-CAfile <file>`|Specifies a CA bundle file (PEM format) to verify the server's certificate. 12|`-CAfile ca-bundle.pem`|
|`-verify <depth>`|Turns on server certificate verification up to a specified chain depth.|`-verify 2`|
|`-state`|Prints SSL session states.|`-state`|
|`-debug`|Prints extensive debugging information.|`-debug`|

## 5. Accessing and Interpreting GCP GLB Logs for mTLS Insights

While client-side tools like `curl` and `openssl s_client` provide the client's perspective of the mTLS handshake, GCP Cloud Logging offers the server-side (GLB) view. This is essential for correlating observations and understanding how the GLB processed the mTLS attempt.

### Ensuring Logging is Enabled for your GLB's Backend Service

For Global External Application Load Balancers, logging occurs if logging is enabled on the associated backend service(s).14 Logging is configured on a per-backend-service basis. During verification and troubleshooting, it is highly recommended to set the logging sample rate to `1.0` (which means 100% of requests are logged) to ensure all relevant events are captured.14

### Navigating to Cloud Logging and Basic Query Structure

Logs for GCP GLBs can be accessed via the Logs Explorer in the Google Cloud Console. The resource type for External HTTP(S) Load Balancers is `http_load_balancer`.16 A basic query to view these logs would be:

```
resource.type="http_load_balancer"
```

The specific log name is often `projects/<PROJECT_ID>/logs/requests` or can be found associated with the forwarding rule or URL map configured for the load balancer.14

### Filtering Logs for the Specific GLB IP Address

To isolate logs relevant to tests conducted against a specific GLB IP address (e.g., `120.120.88.88`), the most reliable method is to filter by the forwarding rule name that is configured with this IP address. Logs are indexed by forwarding rule.14 The `resource.labels.forwarding_rule_name` field should be used.

Example query:

```
resource.type="http_load_balancer"
resource.labels.forwarding_rule_name="<YOUR_FORWARDING_RULE_NAME_ASSOCIATED_WITH_120.120.88.88>"
```

Replace `<YOUR_FORWARDING_RULE_NAME_ASSOCIATED_WITH_120.120.88.88>` with the actual name of your forwarding rule.

### Key Log Fields for mTLS

Several fields within the `jsonPayload` of `http_load_balancer` log entries are pertinent to mTLS validation 1:

- `jsonPayload.statusDetails`: This field is critical. It provides a string explaining why the load balancer returned a particular HTTP status or details about connection termination, including mTLS-related events.14 For mTLS, look for messages like `client_cert_validation_failed`, `client_cert_not_provided`, or specific success indicators if available.
- `jsonPayload.tls.client_cert_present`: An optional mTLS field (for certain LB types and configurations) indicating if a client certificate was presented (boolean).1
- `jsonPayload.tls.client_cert_chain_verified`: An optional mTLS field indicating if the presented client certificate chain was successfully verified (boolean).1
- `jsonPayload.tls.client_cert_error`: An optional mTLS field providing a specific error code if client certificate validation failed (e.g., `client_cert_chain_exceeded_limit`, `client_cert_invalid_rsa_key_size`).1
- Other optional `jsonPayload.tls.*` fields: If validation is successful and these fields are enabled for logging, details like `client_cert_sha256_fingerprint`, `client_cert_serial_number`, `client_cert_subject_dn`, etc., may be available.1
- `jsonPayload.proxyStatus`: For regional external Application Load Balancers and internal Application Load Balancers, this field may contain TLS error details if an initial handshake failure occurs due to a proof-of-possession failure by the client.20
- `httpRequest.responseStatusCode`: The HTTP status code returned to the client by the load balancer (e.g., 200, 400, 403, 503).

### Interpreting mTLS-related Custom Headers (if logged by backend)

When the GLB's clientValidationMode is set to ALLOW_INVALID_OR_MISSING_CLIENT_CERT, the load balancer passes the mTLS validation status to the backend service via specific HTTP headers. These headers include X-Client-Cert-Present, X-Client-Cert-Chain-Verified, X-Client-Cert-Error, X-Client-Cert-Sha256-Fingerprint, and others detailing the certificate if valid.1 These headers are not logged by the GLB itself in Cloud Logging by default; they are consumed by the backend application.1 If observation of these headers is required, the backend application must be configured to log them.

However, for cross-region internal Application Load Balancers, regional external Application Load Balancers, and regional internal Application Load Balancers, when ALLOW_INVALID_OR_MISSING_CLIENT_CERT is used and validation fails, "optional mTLS fields" can be configured in the load balancer's logging settings to capture the reason for the failure directly in Cloud Logging, in addition to the headers being passed to the backend.1

### Identifying Successful mTLS Handshakes vs. Failures in Logs

- **Successful mTLS:** Look for `jsonPayload.statusDetails` indicating a successful proxy operation (e.g., `response_sent_by_backend`) and an appropriate `httpRequest.responseStatusCode` (e.g., 200). If optional mTLS fields are enabled and logged, `jsonPayload.tls.client_cert_present: true` and `jsonPayload.tls.client_cert_chain_verified: true` would be strong indicators of a successful mTLS handshake from the GLB's perspective. This should be correlated with successful client-side tests.
- **mTLS Failures:**
    - If `clientValidationMode` is `REJECT_INVALID`, `jsonPayload.statusDetails` might show errors like `client_cert_validation_failed`, `client_cert_not_provided`, or other specific error messages listed in 1(e.g., `client_cert_chain_exceeded_limit`, `client_cert_invalid_eku`). The `httpRequest.responseStatusCode` might be a client error (e.g., 400) or the connection might be terminated without a full HTTP response.
    - If `clientValidationMode` is `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` and optional mTLS fields are logged, look for `jsonPayload.tls.client_cert_chain_verified: false` and a corresponding `jsonPayload.tls.client_cert_error` message. The `httpRequest.responseStatusCode` might still be 200 if the backend processes the request despite the mTLS validation failure.
    - For proof-of-possession failures with Global External ALBs, there might be no specific mTLS error in the GLB logs; the connection simply terminates.1 Regional/internal ALBs may log this in `jsonPayload.proxyStatus`.

The choice of `clientValidationMode` has a fundamental impact on how and where mTLS validation results are observed. If `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` is used, relying solely on GLB logs might be insufficient to confirm mTLS enforcement unless the backend application logs the custom headers or the optional mTLS log fields are explicitly enabled and reviewed for the specific load balancer type. Without these, the GLB logs might show a successful proxy operation (e.g., a 200 OK response from the backend) even if the client presented an invalid certificate or no certificate at all, potentially creating a significant blind spot if the intention is to strictly enforce mTLS and audit it from the load balancer logs.

A critical early check in the mTLS validation process is the "proof of possession" of the private key by the client. If a client presents a certificate but cannot cryptographically prove it owns the corresponding private key, the GLB will terminate the TLS handshake immediately, irrespective of the `clientValidationMode`setting.1 The logging of this specific failure varies: Global External Application Load Balancers do _not_ log this specific failure, leading to a silent failure from the GLB's logging perspective for this error type.1Regional and internal load balancers, however, will log a TLS error in the `proxyStatus` field.20 This discrepancy means that for Global External ALBs, client-side tools are the primary means of detecting proof-of-possession failures.

**Table 4: Key GCP GLB Log Fields for mTLS Analysis**

|   |   |   |   |
|---|---|---|---|
|**Log Field Path**|**Description**|**Relevance to mTLS**|**Example Values/Interpretation**|
|`jsonPayload.statusDetails`|String explaining LB action or error. 18|Can indicate mTLS success/failure reasons, connection termination.|`response_sent_by_backend`, `client_cert_validation_failed`, `client_cert_not_provided`|
|`jsonPayload.tls.client_cert_present`|(Optional field) Boolean: client certificate was presented. 1|Direct indicator of client cert presentation.|`true`, `false`|
|`jsonPayload.tls.client_cert_chain_verified`|(Optional field) Boolean: client certificate chain verified. 1|Direct indicator of successful client cert validation by GLB.|`true`, `false`|
|`jsonPayload.tls.client_cert_error`|(Optional field) String: error code if client cert validation failed. 1|Specific reason for mTLS validation failure.|`client_cert_invalid_rsa_key_size`, `client_cert_validation_failed`|
|`jsonPayload.tls.client_cert_sha256_fingerprint`|(Optional field) SHA256 fingerprint of presented client leaf certificate. 1|Helps identify the specific client certificate.|Hexadecimal string|
|`jsonPayload.proxyStatus`|(Regional/Internal LBs) TLS error details for certain handshake failures. 20|Can indicate proof-of-possession failure.|e.g., `TLS_ERROR`|
|`httpRequest.responseStatusCode`|HTTP status code returned to client.|Overall outcome of the request.|`200`, `400`, `403`, `503`|
|`resource.labels.forwarding_rule_name`|Name of the forwarding rule that handled the request.|Used to filter logs for a specific GLB frontend IP.|`your-glb-forwarding-rule`|

**Table 5: Common mTLS-related `statusDetails` and `client_cert_error` Messages in GCP Logs**

|   |   |   |
|---|---|---|
|**Message String (from statusDetails or jsonPayload.tls.client_cert_error)**|**Potential Meaning in mTLS Context**|**Possible Causes**|
|`client_cert_not_provided`|Client did not present a certificate when one might have been expected or required.|Client not configured with a cert; `clientValidationMode` is `REJECT_INVALID`.|
|`client_cert_validation_failed`|General failure in validating the client certificate chain against the trust config.|Untrusted CA, expired cert, malformed cert, chain issues.|
|`client_cert_chain_exceeded_limit`|The client certificate chain depth exceeds the allowed limit.|Client certificate chain is too long.|
|`client_cert_invalid_eku`|Client certificate has an invalid or missing Extended Key Usage (EKU). Must include `clientAuth`. 1|Certificate not intended for client authentication.|
|`client_cert_invalid_rsa_key_size`|Client certificate uses an RSA key size that is not supported (e.g., too small). 1|Weak or non-compliant client certificate key.|
|`client_cert_trust_config_not_found`|The trust configuration specified in the mTLS policy was not found. 1|Misconfiguration in `ServerTlsPolicy` or trust config resource deleted/inaccessible.|
|(No specific mTLS error in `statusDetails` for Global Ext. ALB on proof-of-possession failure)|Connection terminates during TLS handshake.|Client failed to prove possession of private key. Detected by client-side tools. 1|

## 6. Understanding GCP GLB mTLS Client Validation Modes and Logging Impact

GCP's Application Load Balancers offer distinct client validation modes for mTLS, which significantly influence how connections are handled and how validation results are logged.1

### `ALLOW_INVALID_OR_MISSING_CLIENT_CERT`

- **Behavior**: When this mode is selected, the load balancer allows the connection from the client even if the client certificate validation fails or if no client certificate is presented at all.1 However, a crucial exception exists: if a client _does_ present a certificate, the load balancer will always perform a "proof of possession" check to verify that the client owns the private key corresponding to the presented public key certificate. If this proof of possession check fails, the TLS handshake is terminated immediately, regardless of this permissive validation mode.1
- **Logging**: If the connection proceeds (i.e., proof of possession passed or no cert presented/validation failed for other reasons), the load balancer forwards the request to the backend. Information about the mTLS validation status is passed to the backend via custom HTTP headers, such as `X-Client-Cert-Present`, `X-Client-Cert-Chain-Verified`, and `X-Client-Cert-Error`.1 These headers are intended for the backend application to inspect and act upon. For certain load balancer types (cross-region internal, regional external, and regional internal Application Load Balancers), additional "optional mTLS fields" can be configured in the load balancer's logging settings to capture the reason for validation failure directly in Cloud Logging.1

### `REJECT_INVALID`

- **Behavior**: This mode enforces stricter mTLS. The load balancer will reject the connection if a client does not provide a certificate or if the presented certificate fails any part of the validation process (including chain of trust against the configured trust anchor).1
- **Logging**: When a connection is rejected due to mTLS validation failure in this mode, errors are logged directly to Cloud Logging by the load balancer.1 Example error messages that might appear in `jsonPayload.statusDetails` or `jsonPayload.tls.client_cert_error` include `client_cert_chain_exceeded_limit`, `client_cert_invalid_eku`, `client_cert_not_provided`, and `client_cert_validation_failed`.1

### Proof-of-Possession Failures

As highlighted, the proof-of-possession check is a fundamental first step if a client certificate is presented.1 The client must prove it owns the private key for the certificate it sends by generating a signature during the handshake; failure to do so means the client is not the legitimate owner of the certificate.1

The logging of this specific failure type differs based on the load balancer:

- **Global External Application Load Balancers**: If proof of possession fails, the TLS handshake is terminated, but _no specific information is logged_ to Cloud Logging for this event.1 This creates a "silent failure" from the perspective of GLB logs.
- **Regional External Application Load Balancers & Internal Application Load Balancers**: If proof of possession fails, a TLS error is logged in the `jsonPayload.proxyStatus` field.20

This distinction in logging proof-of-possession failures is critical. For Global External Application Load Balancers operating in `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` mode, if a client presents a certificate but fails the private key possession check, client-side tools like `curl` or `openssl s_client` will report a TLS handshake error. However, the administrator reviewing only the GLB logs might not find any specific mTLS error entry corresponding to this failure, potentially leading to confusion during troubleshooting.

Furthermore, when choosing the `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` mode, the onus of enforcing authorization based on mTLS validation status effectively shifts to the backend application. The GLB, in this mode, permits the request to reach the backend even if the client certificate is invalid or missing (assuming proof-of-possession passed if a cert was sent). The backend application must then inspect the custom mTLS headers (e.g., `X-Client-Cert-Chain-Verified`) and decide whether to grant or deny access. If the backend does not perform this check and act accordingly, the mTLS validation at the load balancer level becomes merely informational rather than a strict enforcement mechanism at the application layer.

## 7. Troubleshooting Common mTLS Verification Issues

Verifying mTLS configurations can encounter several common issues. A systematic approach, combining client-side tool output with server-side (GLB) logs, is essential for diagnosis.

- **Certificate Chain Issues:**
    
    - **Client Certificate Not Trusted by GLB:** The client certificate presented is not signed by a CA that is present in the GLB's `TrustConfig` resource, or a valid chain to such a CA cannot be built. Ensure the `TrustConfig` (linked via the `ServerTlsPolicy`/ClientAuthentication resource) contains the correct root and any necessary intermediate CAs.1
    - **Server Certificate Not Trusted by Client:** When testing, if the client tool (e.g., `curl`, `openssl s_client`) cannot verify the GLB's server certificate (e.g., missing `--cacert` or incorrect CA in the client's trust store), the handshake will fail before mTLS-specific steps.
    - **Missing Intermediate CAs:** Either the client is not sending its intermediate CAs (if needed and not known by the GLB), or the GLB's server certificate chain is incomplete.
    - **Certificate Requirements Not Met:** Client or intermediate certificates might violate requirements such as `Basic Constraints` extension (`CA=true` for CAs), `Key Usage` extension (`keyCertSign` for CAs), or `Extended Key Usage` (`clientAuth` for client leaf certificates).1
- **SNI Mismatches:**
    
    - The client testing tool is not sending the correct hostname in the SNI field when connecting to the GLB's IP address. This is remediated by using `curl --resolve <host>:<port>:<ip>` 3 or `openssl s_client -servername <host>`.11
    - The GLB may not have an SSL certificate configured for the hostname provided in the SNI, leading it to present a default certificate (if any) or fail the handshake.
- **Private Key Mismatch / Proof of Possession Failure:**
    
    - The client is configured with a certificate (`--cert`) but the provided private key (`--key`) does not correspond to that certificate's public key.
    - As detailed previously, this results in immediate TLS handshake termination by the GLB.1 Logging of this failure depends on the GLB type.
- **"No required SSL certificate was sent" (e.g., HTTP 400 Error):**
    
    - This typically means the server (GLB) expected/required a client certificate, but the client did not provide one.10 This can occur if `curl` is used without `--cert`/`--key`, or if the client application is not configured to send its certificate.
- **GLB Trust Configuration Errors:**
    
    - The `TrustConfig` resource specified in the `ServerTlsPolicy` (ClientAuthentication resource) might be misconfigured, point to the wrong set of CAs, or the resource itself might be missing or inaccessible.1
- **Certificate Expiration:**
    
    - Either the client's certificate or the GLB's server certificate (or any certificate in their respective chains) has expired.1
- **Unsupported Cryptography:**
    
    - Certificates involved might be using weak or deprecated signature algorithms (e.g., MD5, SHA-1) or key types/sizes not supported by the GLB's mTLS policy.1
- **GCP GLB Not Sending `certificate_authorities` Extension:**
    
    - As noted in community discussions 13, GCP GLBs might not send the `certificate_authorities` list in the `CertificateRequest` message. This can make it harder for clients with multiple certificates to select the correct one, potentially leading to the client sending a certificate not trusted by the GLB.

When troubleshooting, a common pitfall is to focus solely on the client's leaf certificate and overlook the integrity and completeness of the entire certificate chain up to one of the CAs explicitly trusted in the GLB's `TrustConfig`. The GLB must be able to construct a valid path of trust from the presented client certificate back to one of its configured trusted CAs.

A "divide and conquer" strategy is often effective. First, ensure basic TLS connectivity to the GLB IP address (using the correct SNI via `--resolve` or `-servername` and verifying the server's certificate with `--cacert`) _without_sending a client certificate. If this step succeeds, then introduce the client certificate and key into the command. If failures occur at this stage, the issue is more likely related to client certificate presentation, the GLB's trust of the client's CA, or a proof-of-possession failure. Finally, correlate client-side observations with the detailed messages in GCP Cloud Logging (`statusDetails`, `client_cert_error`, `proxyStatus`) to understand the GLB's perspective on the handshake.

## 8. Final Pre-Switch Checklist and Recommendations

Before making the DNS switch to point your domain to the mTLS-enabled GLB IP address, a final series of checks and considerations can build confidence and help prevent unforeseen issues.

### Consolidated Verification Steps:

1. **Configuration Audit:**
    - Confirm that mTLS is correctly enabled on the target HTTPS proxy of your GLB. This involves verifying that a `ServerTlsPolicy` (also known as a ClientAuthentication resource in some contexts) is created and attached to the proxy, and that this policy specifies the appropriate `clientValidationMode` and `clientValidationTrustConfig`.1
    - Ensure the `TrustConfig` resource referenced by the `ServerTlsPolicy` contains the correct and complete set of CA certificates (root and any necessary intermediates) that are expected to sign valid client certificates.1
2. **Positive Path Testing (Valid Client Certificate):**
    - Using `curl --resolve your.domain.com:443:<GLB_IP>` (or `openssl s_client -connect <GLB_IP>:443 -servername your.domain.com`), attempt a connection with a known valid client certificate and private key.
    - In the `curl -v` output, look for the server's "Request CERT (13)" message, followed by the client sending its certificate and "Certificate verify (15)", culminating in a successful TLS handshake and expected HTTP response.
    - In `openssl s_client` output, look for the `CertificatePRequest` details and a successful handshake.
3. **Negative Path Testing (Invalid/Missing Client Certificate):**
    - Repeat tests with `curl` or `openssl s_client` but:
        - Without providing any client certificate/key.
        - Providing an expired client certificate.
        - Providing a client certificate signed by a CA not in the GLB's `TrustConfig`.
        - Providing a client certificate with a mismatched private key (to test proof-of-possession failure).
    - Observe the behavior:
        - If `clientValidationMode` is `REJECT_INVALID`, these attempts should result in connection termination or an appropriate error (e.g., HTTP 400/403).
        - If `clientValidationMode` is `ALLOW_INVALID_OR_MISSING_CLIENT_CERT`, these attempts should still reach the backend (unless proof-of-possession fails). Verify that the mTLS custom headers passed to the backend accurately reflect the validation failure.
4. **GCP Log Review:**
    - Query GCP Cloud Logging for `resource.type="http_load_balancer"` filtered by the relevant `resource.labels.forwarding_rule_name`.
    - Examine `jsonPayload.statusDetails`, `jsonPayload.tls.*` optional fields (if enabled), and `jsonPayload.proxyStatus` (for regional/internal LBs) for both successful and failed test attempts. Correlate these server-side logs with client-side observations.

### Confidence-Building Measures:

- **Diverse Client Testing:** If feasible, perform tests from different client environments or using different TLS libraries to ensure broad compatibility.
- **Backend Application Behavior (for `ALLOW_INVALID_OR_MISSING_CLIENT_CERT`):** If this mode is used, rigorously test and confirm that your backend applications correctly parse the mTLS custom headers (e.g., `X-Client-Cert-Chain-Verified`, `X-Client-Cert-Error`), log them appropriately, and enforce authorization decisions based on this information. Without this backend enforcement, the mTLS check at the GLB becomes informational rather than a security control.
- **Document Expected Outcomes:** Clearly document the expected behavior (connection success/failure, specific errors, log entries) for connections with valid client certificates and various types of invalid or missing client certificates. This provides a baseline for future monitoring and troubleshooting.

### Prerequisite: Server-Side Certificate and Domain Validation

While this report focuses on client certificate validation (mTLS), it's crucial to remember that the GLB's own server-side TLS configuration must be sound. If using Google-managed SSL certificates for the GLB, ensure that domain ownership has been validated (e.g., via DNS Authorization by creating specific DNS records like CNAMEs).24 The server certificate must be active and correctly associated with the target proxy before mTLS can be effectively layered on top.

### Strategic Considerations for DNS Cutover:

- **Test Negative Paths Thoroughly:** It is vital to confirm not only that legitimate clients _can_ connect but also that unauthorized or improperly configured clients _cannot_ (or are handled as expected per the `clientValidationMode`). This validates the actual enforcement posture of the mTLS setup.
- **Shorten DNS TTL:** Before the planned DNS switch, consider significantly reducing the Time-To-Live (TTL) value for the relevant DNS A/AAAA records (e.g., to 60-300 seconds). A shorter TTL means that if any widespread issues are discovered immediately after the cutover, reverting the DNS change to the previous IP address will propagate much more quickly across the internet, minimizing the impact duration. Once the new configuration is stable, the TTL can be increased again.

By systematically executing these verification steps and considering these recommendations, the likelihood of a smooth and secure transition when enabling mTLS on your GCP Global Load Balancer can be significantly increased.