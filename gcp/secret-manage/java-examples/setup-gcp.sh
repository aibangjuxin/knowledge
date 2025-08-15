#!/bin/bash

# Complete GCP setup script for Secret Manager Demo
# This script sets up all necessary GCP resources for the demo

set -e

# Configuration
PROJECT_ID=${GOOGLE_CLOUD_PROJECT:-"your-project-id"}
REGION=${REGION:-"us-central1"}
CLUSTER_NAME=${CLUSTER_NAME:-"secret-manager-demo-cluster"}
GSA_NAME="secret-manager-demo-gsa"
KSA_NAME="secret-manager-demo-ksa"
NAMESPACE="secret-manager-demo"

echo "=== Setting up GCP Secret Manager Demo ==="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Step 1: Enable required APIs
echo "Step 1: Enabling required APIs..."
gcloud services enable secretmanager.googleapis.com \
    container.googleapis.com \
    cloudbuild.googleapis.com \
    --project="$PROJECT_ID"

# Step 2: Create Google Service Account (GSA)
echo "Step 2: Creating Google Service Account..."
if gcloud iam service-accounts describe "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "GSA already exists: ${GSA_NAME}"
else
    gcloud iam service-accounts create "$GSA_NAME" \
        --display-name="Secret Manager Demo Service Account" \
        --description="Service account for Secret Manager demo application" \
        --project="$PROJECT_ID"
fi

# Step 3: Grant Secret Manager permissions to GSA
echo "Step 3: Granting Secret Manager permissions..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# Step 4: Create secrets using the setup script
echo "Step 4: Creating secrets..."
bash k8s/secret-setup.sh

# Step 5: Set up Workload Identity binding
echo "Step 5: Setting up Workload Identity binding..."
gcloud iam service-accounts add-iam-policy-binding \
    "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --project="$PROJECT_ID"

echo ""
echo "=== Setup completed successfully! ==="
echo ""
echo "Next steps:"
echo "1. Build and push the Docker image:"
echo "   mvn compile jib:build -Dimage=gcr.io/$PROJECT_ID/secret-manager-demo:latest"
echo ""
echo "2. Update the Kubernetes manifests with your project ID:"
echo "   sed -i 's/PROJECT_ID/$PROJECT_ID/g' k8s/*.yaml"
echo ""
echo "3. Deploy to GKE:"
echo "   kubectl apply -f k8s/"
echo ""
echo "4. Test the application:"
echo "   kubectl port-forward svc/secret-manager-demo-service 8080:80 -n $NAMESPACE"
echo "   curl http://localhost:8080/api/health"