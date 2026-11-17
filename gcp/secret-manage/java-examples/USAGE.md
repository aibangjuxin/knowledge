# Usage Guide - GCP Secret Manager Java Demo

This guide walks you through setting up and running the GCP Secret Manager demo application.

## Prerequisites

1. **GCP Project**: A Google Cloud Project with billing enabled
2. **GKE Cluster**: A GKE cluster with Workload Identity enabled
3. **Tools**: `gcloud`, `kubectl`, `maven`, `docker` (or use Cloud Build)

## Step-by-Step Setup

### 1. Environment Setup

```bash
# Set your project ID
export GOOGLE_CLOUD_PROJECT="your-project-id"
export REGION="us-central1"

# Authenticate with GCP
gcloud auth login
gcloud config set project $GOOGLE_CLOUD_PROJECT
```

### 2. Run the Complete Setup Script

```bash
# Make the setup script executable
chmod +x setup-gcp.sh

# Run the complete setup
./setup-gcp.sh
```

This script will:
- Enable required APIs
- Create the Google Service Account (GSA)
- Grant Secret Manager permissions
- Create all demo secrets
- Set up Workload Identity binding

### 3. Build and Deploy the Application

```bash
# Update Kubernetes manifests with your project ID
sed -i "s/PROJECT_ID/$GOOGLE_CLOUD_PROJECT/g" k8s/*.yaml

# Build and push the Docker image using Jib
mvn compile jib:build -Dimage=gcr.io/$GOOGLE_CLOUD_PROJECT/secret-manager-demo:latest

# Deploy to Kubernetes
kubectl apply -f k8s/
```

### 4. Test the Application

```bash
# Wait for deployment to be ready
kubectl wait --for=condition=available --timeout=300s deployment/secret-manager-demo -n secret-manager-demo

# Port forward to access the application
kubectl port-forward svc/secret-manager-demo-service 8080:80 -n secret-manager-demo &

# Test the health endpoint
curl http://localhost:8080/api/health

# Test authentication with the demo user
curl -X POST http://localhost:8080/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"MySecureDbPassword123!"}'

# Test API key validation
curl -X POST http://localhost:8080/api/validate-api-key \
  -H "X-API-Key: api-key-abc123xyz789"

# Get application statistics
curl http://localhost:8080/api/stats

# Test secret retrieval (returns masked value for security)
curl http://localhost:8080/api/secret/jwt-signing-key
```

## Understanding the Demo

### Key-Value Secrets

The application demonstrates three ways to use key-value secrets:

1. **Declarative injection** via `application.yml`:
   ```yaml
   app:
     secrets:
       database-password: ${sm://database-password}
       api-key: ${sm://third-party-api-key}
   ```

2. **Programmatic retrieval**:
   ```java
   String secret = secretManagerService.getKeyValueSecret("jwt-signing-key");
   ```

3. **Spring property injection**:
   ```java
   @Value("${app.secrets.api-key}")
   private String apiKey;
   ```

### File-Based Secrets

File secrets are Base64 encoded and can be used in two ways:

1. **Write to file system**:
   ```java
   secretManagerService.writeFileSecretToPath("keystore-jks-secret", "/tmp/secrets/keystore.jks");
   ```

2. **Get as byte array**:
   ```java
   byte[] keystoreContent = secretManagerService.getFileSecret("keystore-jks-secret");
   ```

## API Endpoints

| Endpoint | Method | Description | Example |
|----------|--------|-------------|---------|
| `/api/health` | GET | Health check | `curl http://localhost:8080/api/health` |
| `/api/login` | POST | User authentication demo | See authentication example above |
| `/api/validate-api-key` | POST | API key validation | See API key example above |
| `/api/stats` | GET | Application statistics | `curl http://localhost:8080/api/stats` |
| `/api/secret/{name}` | GET | Retrieve specific secret | `curl http://localhost:8080/api/secret/database-password` |

## Monitoring and Troubleshooting

### Check Pod Logs
```bash
kubectl logs -f deployment/secret-manager-demo -n secret-manager-demo
```

### Verify Workload Identity Setup
```bash
# Check if the KSA is properly annotated
kubectl describe sa secret-manager-demo-ksa -n secret-manager-demo

# Verify the GSA exists and has proper permissions
gcloud iam service-accounts describe secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com

# Check Workload Identity binding
gcloud iam service-accounts get-iam-policy secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
```

### Test Secret Access from Pod
```bash
# Execute into the pod to test secret access
kubectl exec -it deployment/secret-manager-demo -n secret-manager-demo -- /bin/bash

# Inside the pod, test if you can access secrets
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
```

### Common Issues and Solutions

#### 1. Permission Denied (403) Errors
```bash
# Check if GSA has secretAccessor role
gcloud projects get-iam-policy $GOOGLE_CLOUD_PROJECT \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com"

# Grant missing permissions
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
  --member="serviceAccount:secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

#### 2. Workload Identity Not Working
```bash
# Check if Workload Identity is enabled on the cluster
gcloud container clusters describe YOUR_CLUSTER_NAME \
  --region=$REGION \
  --format="value(workloadIdentityConfig.workloadPool)"

# Check if node pool has correct metadata settings
gcloud container node-pools describe YOUR_NODE_POOL \
  --cluster=YOUR_CLUSTER_NAME \
  --region=$REGION \
  --format="value(config.workloadMetadataConfig.mode)"
```

#### 3. Secrets Not Found
```bash
# List all secrets in the project
gcloud secrets list --project=$GOOGLE_CLOUD_PROJECT

# Check specific secret
gcloud secrets describe database-password --project=$GOOGLE_CLOUD_PROJECT

# Test secret access manually
gcloud secrets versions access latest --secret=database-password --project=$GOOGLE_CLOUD_PROJECT
```

## Environment-Specific Configuration

### Development Environment
```bash
# Use development secrets
export SPRING_PROFILES_ACTIVE=dev

# The application will use:
# - dev-database-password
# - dev-api-key
```

### Production Environment
```bash
# Use production secrets
export SPRING_PROFILES_ACTIVE=prod

# The application will use:
# - prod-database-password  
# - prod-api-key
```

## Security Best Practices

### 1. Secret Rotation
```bash
# Create new version of a secret
echo -n "new-password-value" | gcloud secrets versions add database-password --data-file=-

# The application will automatically use the latest version
```

### 2. Monitoring Secret Access
```bash
# View audit logs for secret access
gcloud logging read 'resource.type="gce_instance" AND protoPayload.serviceName="secretmanager.googleapis.com"' \
  --limit=50 \
  --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"
```

### 3. Least Privilege Access
```bash
# Grant access to specific secrets only (instead of project-wide)
gcloud secrets add-iam-policy-binding database-password \
  --member="serviceAccount:secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

## Cleanup

### Remove the Application
```bash
kubectl delete -f k8s/
```

### Remove GCP Resources
```bash
# Delete secrets
gcloud secrets delete database-password --quiet
gcloud secrets delete third-party-api-key --quiet
gcloud secrets delete jwt-signing-key --quiet
gcloud secrets delete keystore-jks-secret --quiet
gcloud secrets delete ssl-cert-secret --quiet

# Delete service account
gcloud iam service-accounts delete secret-manager-demo-gsa@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --quiet
```

## Next Steps

1. **Customize for Your Use Case**: Modify the secret names and types based on your application needs
2. **Implement Secret Rotation**: Set up automated secret rotation policies
3. **Add Monitoring**: Integrate with your monitoring and alerting systems
4. **Scale the Pattern**: Apply this pattern to other applications in your organization
5. **Security Review**: Conduct a security review of your secret management practices

## Additional Resources

- [GCP Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Spring Cloud GCP Documentation](https://spring.io/projects/spring-cloud-gcp)
- [GKE Security Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)


# summary 
## 🧪 Testing Section
Complete curl commands for all API endpoints
Authentication testing with demo credentials
API key validation examples
Statistics and health check endpoints
## 📚 Understanding the Demo
Detailed explanation of key-value vs file-based secrets
Three different ways to access secrets in Spring Boot
Code examples for each approach
## 📊 API Documentation
Complete endpoint table with methods and examples
Practical curl commands for each endpoint
## 🔍 Monitoring & Troubleshooting
Pod log checking commands
Workload Identity verification steps
Secret access testing from within pods
Common issues with specific solutions
## 🛠 Advanced Troubleshooting
Permission denied error resolution
Workload Identity debugging
Secret not found issues
Step-by-step diagnostic commands
## 🌍 Environment Configuration
Development vs production environment setup
Profile-specific secret usage
Environment variable configuration
## 🔐 Security Best Practices
Secret rotation procedures
Audit log monitoring
Least privilege access implementation
Security monitoring commands
## 🧹 Cleanup Instructions
Application removal steps
GCP resource cleanup
Complete teardown procedures
## 🚀 Next Steps & Resources
Customization guidance
Scaling recommendations
Additional learning resources
Security review suggestions