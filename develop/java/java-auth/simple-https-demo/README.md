# Simple HTTPS Demo - Dual SSL Role

A minimal Spring Boot application demonstrating:
1. **TLS Server**: Listen on port 8443 with YOUR OWN certificate
2. **TLS Client**: Connect to third-party services using Java's built-in cacerts

## Architecture

```
                    External Client
                   (Browser/curl/etc)
                          |
                          | HTTPS (port 8443)
                          v
              +------------------------+
              |   Your Java App        |
              |   (TLS SERVER)         |
              |                        |
              |   server-keystore.p12  |  <-- YOUR certificate
              +------------------------+
                          |
                          | HTTPS (outbound)
                          v
              +------------------------+
              |   Third-Party Service  |
              |   (Google, AWS, etc)   |
              +------------------------+
                          ^
                          |
              Java's built-in cacerts   <-- Public CA certificates
              ($JAVA_HOME/lib/security/cacerts)
```

## Quick Start

```bash
# 1. Generate self-signed certificate
chmod +x generate-cert.sh
./generate-cert.sh

# 2. Build and run
mvn spring-boot:run

# 3. Test server (your certificate)
curl -k https://localhost:8443/hello

# 4. Test client (Java's cacerts for third-party)
curl -k "https://localhost:8443/fetch?url=https://httpbin.org/get"
```

## Key Configuration

### Server SSL (application.yml)
```yaml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: classpath:ssl/server-keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12
    key-alias: server
```

### Client SSL
By default, Java uses `$JAVA_HOME/lib/security/cacerts` for outbound HTTPS calls.
No extra configuration needed for public services!

## Common Pitfalls

| Mistake | Correct |
|---------|---------|
| Using TrustStore as KeyStore | KeyStore must have PrivateKeyEntry |
| Wrong alias name | Check with `keytool -list` |
| Mixing client/server certs | Server needs private key, client needs CA certs |

## Production Notes

For production, replace self-signed cert with real certificate:
```bash
# Import existing cert + key into PKCS12
openssl pkcs12 -export \
    -in your-cert.crt \
    -inkey your-key.key \
    -out server-keystore.p12 \
    -name server \
    -passout pass:changeit
```

### How to 

⛬  Done! I've created a complete, minimal Java Spring Boot application at /Users/lex/git/knowledge/java/java-auth/simple-https-demo/.
```bash
   Project Structure

     simple-https-demo/
     ├── pom.xml                          # Spring Boot 3.2 + Java 17
     ├── generate-cert.sh                 # Certificate generation script
     ├── README.md                        # Documentation
     └── src/main/
         ├── resources/
         │   ├── application.yml          # SSL configuration
         │   └── ssl/
         │       └── server-keystore.p12  # Your certificate (already generated)
         └── java/com/example/demo/
             ├── Application.java         # Main entry
             ├── controller/
             │   └── DemoController.java  # Test endpoints
             └── config/
                 └── RestClientConfig.java # RestTemplate config

   Key Points

   Role                       │ Certificate                      │ Purpose                        
   ---------------------------+----------------------------------+--------------------------------
   **TLS Server** (port 8443) │ `server-keystore.p12` (your own) │ Others access your service
   **TLS Client** (outbound)  │ Java's cacerts (built-in)        │ You access third-party services

   Run & Test

   bash
     cd simple-https-demo
     mvn spring-boot:run

     # Test server (your cert)
     curl -k https://localhost:8443/hello

     # Test client (Java's cacerts for external)
     curl -k "https://localhost:8443/fetch?url=https://httpbin.org/get"
```
 Auto (Medium) - allow reversible commands    


# Using openssl get certificate

```bash
openssl s_client -connect localhost:8443 -servername localhost -tls1_3
```

### Explanation:
- `-connect localhost:8443`: Connects to your HTTPS server on port 8443.
- `-servername localhost`: Enables SNI (Server Name Indication), required for most modern HTTPS servers.
- `-tls1_3`: Forces TLS 1.3 negotiation (replace with `-tls1_2`, `-tls1_1`, etc., to test specific versions, or omit to use the highest supported).

### To get the negotiated SSL/TLS version:
Run the command above (without version flag for auto-negotiation), then look for the **"Protocol"** line in the output:
```
---
Protocol  : TLSv1.3 (OUT), TLSv1.3 (IN)
---
```
Ignore certificate warnings (self-signed cert) by adding `-verify_quiet` or piping to `grep`:
```bash
openssl s_client -connect localhost:8443 -servername localhost -verify_quiet 2>/dev/null | grep "^Protocol"
```

This matches your `curl -k` (ignores cert errors) and directly shows the TLS version used, e.g., TLSv1.2, TLSv1.3. 

Test different versions by adding `-tls1_2`, etc., to see what's supported.