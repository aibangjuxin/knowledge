
# summary 
some commands to manage GKE service accounts and GCP service accounts.
```bash
#!/bin/bash

# Get all GKE service accounts where the name includes -rt and -rt$
gke_sa=$(kubectl get sa --all-namespaces -o json | jq -r '.items[] | select(.metadata.name | test("-rt|-rt$")) | .metadata.name')

# For each GKE service account, get the associated GCP service account and sort/uniq the results
gcp_sa_accounts=()
for sa in $gke_sa; do
  gcp_sa=$(kubectl describe sa $sa | grep 'kubernetes.io/service-account.name' | awk '{print $2}' | sort | uniq)
  gcp_sa_accounts+=($gcp_sa)
done

# For each GCP service account, check if it has the 'dns admin' role
for gcp_sa in "${gcp_sa_accounts[@]}"; do
#  gcloud iam service-accounts get-iam-policy $gcp_sa --format="value(bindings.role)" --project=$PROJECT_ID
  roles=$(gcloud iam service-accounts get-iam-policy $gcp_sa --format="value(bindings.role)")
  if [[ $roles == *"dns admin"* ]]; then
    echo "Service account $gcp_sa has 'dns admin' role"
  else
    echo "Service account $gcp_sa does not have 'dns admin' role"
  fi
done
```
# how to bind a GKE service account to a GCP service account and assign a Workload Identity role?

- To bind a GKE service account to a GCP service account and assign a Workload Identity role, you can follow these steps:
- Create a GCP service account or use an existing one.
- Create a Kubernetes service account in the same namespace as your workload.
- Add the IAM policy binding between the GCP service account and the Kubernetes service account.
- Annotate the Kubernetes service account with the GCP service account.
- Here is a shell script that performs these steps:
```bash
#!/bin/bash

# Variables
GCP_SA_NAME="your-gcp-sa"  # Replace with your GCP service account name
GCP_SA_EMAIL="your-gcp-sa@your-project-id.iam.gserviceaccount.com"  # Replace with your GCP service account email
GKE_SA_NAME="your-gke-sa"  # Replace with your GKE service account name
NAMESPACE="your-namespace"  # Replace with your namespace

# Create GCP service account
gcloud iam service-accounts create $GCP_SA_NAME

# Create GKE service account
kubectl create serviceaccount --namespace $NAMESPACE $GKE_SA_NAME

# Add IAM policy binding
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:your-project-id.svc.id.goog[$NAMESPACE/$GKE_SA_NAME]" \
  $GCP_SA_EMAIL

# Annotate GKE service account
kubectl annotate serviceaccount \
  --namespace $NAMESPACE \
  $GKE_SA_NAME \
  iam.gke.io/gcp-service-account=$GCP_SA_EMAIL
```

  You can verify if your GKE service account has the iam.workloadIdentityUser role by using the gcloud command to get the IAM policy of the GCP service account and then checking if the iam.workloadIdentityUser role is present.
```bash
#!/bin/bash

# Variables
GCP_SA_EMAIL="your-gcp-sa@your-project-id.iam.gserviceaccount.com"  # Replace with your GCP service account email
GKE_SA_NAME="your-gke-sa"  # Replace with your GKE service account name
NAMESPACE="your-namespace"  # Replace with your namespace

# Get IAM policy
iam_policy=$(gcloud iam service-accounts get-iam-policy $GCP_SA_EMAIL --format=json)

# Check if the iam.workloadIdentityUser role is present for the GKE service account
if echo "$iam_policy" | jq -e --arg GKE_SA "serviceAccount:your-project-id.svc.id.goog[$NAMESPACE/$GKE_SA_NAME]" '.bindings[] | select(.role == "roles/iam.workloadIdentityUser" and .members[] == $GKE_SA)' > /dev/null; then
  echo "GKE service account $GKE_SA_NAME has the 'iam.workloadIdentityUser' role"
else
  echo "GKE service account $GKE_SA_NAME does not have the 'iam.workloadIdentityUser' role"
fi


You can list the IAM roles assigned to a GCP service account using the gcloud command-line tool. Here is a shell command that performs this task:
GCP_SA_EMAIL="your-gcp-sa@your-project-id.iam.gserviceaccount.com"  # Replace with your GCP service account email

# List IAM roles
gcloud iam service-accounts get-iam-policy $GCP_SA_EMAIL --format="json" | jq -r '.bindings[].role'

How can I add a new IAM role to a GCP service account?

GCP_SA_EMAIL="your-gcp-sa@your-project-id.iam.gserviceaccount.com"  # Replace with your GCP service account email
ROLE="roles/storage.admin"  # Replace with the role you want to add

# Add IAM role
gcloud iam service-accounts add-iam-policy-binding $GCP_SA_EMAIL \
  --member="serviceAccount:$GCP_SA_EMAIL" \
  --role=$ROLE
```