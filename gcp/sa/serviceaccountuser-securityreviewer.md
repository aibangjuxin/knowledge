# GCP Roles: roles/iam.serviceAccountUser and roles/iam.securityReviewer

This document provides a comprehensive overview of the `roles/iam.serviceAccountUser` and `roles/iam.securityReviewer` roles in Google Cloud Platform, including their permissions, use cases, and practical examples for querying these roles.

## roles/iam.serviceAccountUser

### Overview
The `roles/iam.serviceAccountUser` role is a predefined IAM role that allows a principal (user, group, or service account) to act as or impersonate a service account. This is one of the most commonly used roles when granting access to service accounts.

### Key Permissions
- `iam.serviceAccounts.actAs` - Allows attaching a service account to a resource and acting as that service account
- `iam.serviceAccounts.get` - Allows getting information about a service account
- `iam.serviceAccounts.list` - Allows listing service accounts

### Capabilities
- Allows a principal to attach a service account to a resource (such as Compute Engine VMs, App Engine apps, Cloud Run services, etc.)
- Enables code running on those resources to get credentials for the attached service account
- Permits long-running jobs to authenticate as the service account
- Allows the principal to use the service account's identity to access other GCP resources

### Use Cases
- Granting a user or another service account the ability to impersonate a service account
- Allowing GKE nodes to use a specific service account for workload identity
- Enabling applications running on Compute Engine to use service account credentials
- Providing access to developers who need to test applications using service account permissions

### Important Notes
- This role does NOT allow creating short-lived credentials for service accounts
- This role does NOT allow using the `--impersonate-service-account` flag for Google Cloud CLI
- For token creation tasks, the `roles/iam.serviceAccountTokenCreator` role is needed

## roles/iam.securityReviewer

### Overview
The `roles/iam.securityReviewer` role is a predefined IAM role that grants permissions to review security configurations and policies across Google Cloud resources. This role is designed for security auditors and reviewers who need to examine security settings without necessarily having the ability to make changes.

### Key Permissions
- Access to list all resources and read their policies
- Ability to view IAM policies across resources
- Read-only access to security configurations
- View access to audit logs and security-related configurations
- Permission to examine custom roles (but not administer them)

### Capabilities
- Review security configurations across the GCP environment
- Examine IAM policies and access controls
- View security-related settings and configurations
- Audit security compliance across resources
- View but not modify security policies

### Use Cases
- Security audits and compliance reviews
- Periodic access reviews to ensure appropriate permissions
- Monitoring security posture across GCP resources
- Compliance reporting and security assessments
- Third-party security tools integration that requires read-only access

## Practical Examples: Querying Service Account Roles

### 1. Check Project-Level IAM Policy for a Specific Service Account
```bash
# Check which roles are assigned to a specific service account at the project level
gcloud projects get-iam-policy PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:SERVICE_ACCOUNT_EMAIL" \
    --format="table(bindings.role)"
```

### 2. Check Service Account Level IAM Policy
```bash
# Check which principals have access to use/impersonate a specific service account
gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL \
    --project=PROJECT_ID \
    --format="table(bindings.role, bindings.members)"
```

### 3. Get Detailed Information About a Role
```bash
# Get detailed permissions for the serviceAccountUser role
gcloud iam roles describe roles/iam.serviceAccountUser --project=PROJECT_ID

# Get detailed permissions for the securityReviewer role
gcloud iam roles describe roles/iam.securityReviewer --project=PROJECT_ID
```

### 4. Check if a User Has Specific Roles
```bash
# Check if a user has the serviceAccountUser role on a specific service account
gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL \
    --project=PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:USER_EMAIL" \
    --format="table(bindings.role)"
```

### 5. Find All Service Accounts with Specific Roles
```bash
# List all service accounts in a project
gcloud iam service-accounts list --project=PROJECT_ID

# Then check each service account's IAM policy for specific roles
for sa in $(gcloud iam service-accounts list --project=PROJECT_ID --format="value(email)"); do
    echo "Checking $sa..."
    gcloud iam service-accounts get-iam-policy $sa --project=PROJECT_ID --format="table(bindings.role, bindings.members)"
done
```

## Best Practices

### For roles/iam.serviceAccountUser
- Follow the principle of least privilege - only grant this role when necessary
- Regularly audit who has this role assigned
- Monitor usage of service accounts that have this role assigned
- Consider using workload identity instead of directly assigning this role when possible

### For roles/iam.securityReviewer
- Limit assignment to personnel responsible for security auditing
- Regularly rotate access for security reviewers
- Monitor access patterns of security reviewer accounts
- Combine with other monitoring tools for comprehensive security oversight

## Security Considerations

### roles/iam.serviceAccountUser
- This role effectively grants the ability to act as the service account
- Be cautious when granting this role to users or other service accounts
- A compromised account with this role can access all resources the service account has access to

### roles/iam.securityReviewer
- While read-only, this role can reveal sensitive security configurations
- Limit to trusted security personnel
- Monitor access to prevent unauthorized disclosure of security information

## Relationship Between the Roles

In the context of your verification script (`verify-gce-sa.sh`), these roles serve complementary purposes:
- `roles/iam.serviceAccountUser` allows the secret manager admin service account to impersonate and act as needed for creating instances
- `roles/iam.securityReviewer` provides the onboarding service account with the ability to review security configurations at the project level
- Together, they enable both operational functionality and security oversight in your deployment workflow