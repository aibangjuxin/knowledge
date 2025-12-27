#!/bin/bash
# =============================================================================
# Generate Self-Signed Certificate for HTTPS Server (Port 8443)
# =============================================================================

SSL_DIR="src/main/resources/ssl"
mkdir -p "$SSL_DIR"

KEYSTORE="$SSL_DIR/server-keystore.p12"
PASSWORD="changeit"
ALIAS="server"
VALIDITY=365

# Remove old keystore if exists
rm -f "$KEYSTORE"

echo "=== Generating self-signed certificate for HTTPS server ==="

# Generate PKCS12 keystore with private key + certificate
keytool -genkeypair \
    -alias "$ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -storetype PKCS12 \
    -keystore "$KEYSTORE" \
    -storepass "$PASSWORD" \
    -validity "$VALIDITY" \
    -dname "CN=localhost, OU=Demo, O=Example, L=City, ST=State, C=US" \
    -ext "SAN=dns:localhost,ip:127.0.0.1"

echo ""
echo "=== Certificate generated successfully! ==="
echo "Location: $KEYSTORE"
echo "Password: $PASSWORD"
echo "Alias:    $ALIAS"
echo ""

# Show certificate info
echo "=== Certificate Details ==="
keytool -list -v -keystore "$KEYSTORE" -storepass "$PASSWORD" | grep -A 20 "Alias name"

echo ""
echo "=== How to run ==="
echo "1. mvn spring-boot:run"
echo "2. Access: https://localhost:8443/hello"
echo "3. Test outbound: https://localhost:8443/fetch?url=https://httpbin.org/get"
echo ""
echo "Note: Browser will warn about self-signed cert - this is expected for dev."
