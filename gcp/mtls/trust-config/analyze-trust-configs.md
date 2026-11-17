
```bash
#!/bin/bash

# --- Configuration ---
TRUST_CONFIG_NAME="your-trust-config-name"
LOCATION="global"
OUTPUT_DIR="./certs"

# Create output directory if not exists
mkdir -p "$OUTPUT_DIR"

# --- Get Trust Config in JSON format ---
echo "Getting trust config in JSON format..."
gcloud certificate-manager trust-configs describe "$TRUST_CONFIG_NAME" \
    --location="$LOCATION" \
    --format="json" > "$OUTPUT_DIR/trust-config.json"

# --- Extract certificates from trust config ---
echo "Extracting certificates from trust config..."

# Extract trust anchors (root CA certificates)
echo "Extracting trust anchors..."
jq -r '.trustAnchors[].pemCertificate' "$OUTPUT_DIR/trust-config.json" | \
while IFS= read -r cert; do
    if [ ! -z "$cert" ]; then
        echo "$cert" > "$OUTPUT_DIR/trust-anchor-$(date +%s).pem"
    fi
done

# Extract intermediate CA certificates if they exist
echo "Extracting intermediate CA certificates..."
jq -r '.intermediateCas[].pemCertificate' "$OUTPUT_DIR/trust-config.json" | \
while IFS= read -r cert; do
    if [ ! -z "$cert" ]; then
        echo "$cert" > "$OUTPUT_DIR/intermediate-ca-$(date +%s).pem"
    fi
done

# --- Analyze certificates ---
echo "\nAnalyzing certificates..."
for cert in "$OUTPUT_DIR"/*.pem; do
    if [ -f "$cert" ]; then
        echo "\nAnalyzing certificate: $(basename "$cert"):"
        echo "----------------------------------------"
        openssl x509 -in "$cert" -noout -issuer -subject
        echo "----------------------------------------"
    fi
done

echo "\nCertificate analysis complete. Files are stored in $OUTPUT_DIR/"
```