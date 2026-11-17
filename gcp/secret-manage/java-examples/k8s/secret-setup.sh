#!/bin/bash

# GCP Secret Manager Setup Script
# This script creates the necessary secrets in GCP Secret Manager for the demo application

set -e

# Configuration
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"your-project-id"}
REGION=${REGION:-"us-central1"}

echo "Setting up GCP Secret Manager secrets for project: $PROJECT_ID"

# Function to create a secret if it doesn't exist
create_secret_if_not_exists() {
    local secret_name=$1
    local secret_value=$2
    
    if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" >/dev/null 2>&1; then
        echo "Secret '$secret_name' already exists, adding new version..."
        echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
            --data-file=- --project="$PROJECT_ID"
    else
        echo "Creating secret '$secret_name'..."
        gcloud secrets create "$secret_name" \
            --replication-policy="automatic" \
            --project="$PROJECT_ID"
        echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
            --data-file=- --project="$PROJECT_ID"
    fi
}

# Create key-value secrets
echo "Creating key-value secrets..."
create_secret_if_not_exists "database-password" "MySecureDbPassword123!"
create_secret_if_not_exists "third-party-api-key" "api-key-abc123xyz789"
create_secret_if_not_exists "jwt-signing-key" "jwt-secret-key-for-token-signing-2024"

# Create development environment secrets
create_secret_if_not_exists "dev-database-password" "DevDbPassword123!"
create_secret_if_not_exists "dev-api-key" "dev-api-key-abc123"

# Create production environment secrets  
create_secret_if_not_exists "prod-database-password" "ProdDbPassword456!"
create_secret_if_not_exists "prod-api-key" "prod-api-key-xyz789"

echo "Key-value secrets created successfully!"#
 Create file-based secrets (Base64 encoded)
echo "Creating file-based secrets..."

# Create a sample keystore file (for demo purposes)
SAMPLE_KEYSTORE_CONTENT="MIIKXgIBAzCCCiQGCSqGSIb3DQEHAaCCChUEggoRMIIKDTCCBXEGCSqGSIb3DQEHAaCCBWIEggVeMIIFWjCCBVYGCyqGSIb3DQEMCgECoIIE+jCCBPYwHAYKKoZIhvcNAQwBAzAOBAhQVYmVbPY7hgICB9AEggTUn8n"

# Create keystore secret
if gcloud secrets describe "keystore-jks-secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Secret 'keystore-jks-secret' already exists, adding new version..."
    echo -n "$SAMPLE_KEYSTORE_CONTENT" | gcloud secrets versions add "keystore-jks-secret" \
        --data-file=- --project="$PROJECT_ID"
else
    echo "Creating keystore secret..."
    gcloud secrets create "keystore-jks-secret" \
        --replication-policy="automatic" \
        --project="$PROJECT_ID"
    echo -n "$SAMPLE_KEYSTORE_CONTENT" | gcloud secrets versions add "keystore-jks-secret" \
        --data-file=- --project="$PROJECT_ID"
fi

# Create SSL certificate secret (sample PEM content)
SSL_CERT_CONTENT="LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURYVENDQWtXZ0F3SUJBZ0lKQUxGM1E="

if gcloud secrets describe "ssl-cert-secret" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Secret 'ssl-cert-secret' already exists, adding new version..."
    echo -n "$SSL_CERT_CONTENT" | gcloud secrets versions add "ssl-cert-secret" \
        --data-file=- --project="$PROJECT_ID"
else
    echo "Creating SSL certificate secret..."
    gcloud secrets create "ssl-cert-secret" \
        --replication-policy="automatic" \
        --project="$PROJECT_ID"
    echo -n "$SSL_CERT_CONTENT" | gcloud secrets versions add "ssl-cert-secret" \
        --data-file=- --project="$PROJECT_ID"
fi

echo "File-based secrets created successfully!"

# List all created secrets
echo "All secrets created:"
gcloud secrets list --project="$PROJECT_ID" --format="table(name,createTime)"

echo "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Create and configure the Google Service Account (GSA)"
echo "2. Set up Workload Identity binding"
echo "3. Deploy the application to GKE"