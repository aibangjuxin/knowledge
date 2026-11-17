# Firestore vs GCP Secret Manager Cost Comparison

## Overview

This document compares the costs between Google Cloud Firestore and Google Cloud Secret Manager for storing and retrieving authentication credentials in the Cloud Scheduler Service context. The comparison focuses on the cost implications of the approach outlined in `css-enhance.md`, where secrets are accessed frequently during scheduler operations.

## Pricing Models

### Google Cloud Firestore Pricing

#### Operations
- **Document Reads**: $0.06 per 100,000 reads
- **Document Writes**: $0.18 per 100,000 writes
- **Document Deletes**: $0.02 per 100,000 deletes
- **Free Tier**: 50,000 reads, 20,000 writes, 20,000 deletes per day

#### Storage
- **Data Storage**: $0.18 per GB per month
- Includes document data, metadata, and indexes
- **Free Tier**: 1 GB of storage per month

#### Network Egress
- **Outbound Data Transfer**: $0.12 per GB
- **Free Tier**: 10 GB of network egress per month

### Google Cloud Secret Manager Pricing

#### Active Secret Versions
- **$0.06 per version per location** for active secret versions
- Destroyed secret versions are free
- **Free Tier**: Six secret versions are free for all customers

#### Operations
- **Access operations**: $0.03 per 10,000 operations
- **Management operations**: Free

#### Notifications
- **Rotation notifications**: $0.05 per rotation
- Billed for every `SECRET_ROTATE` message sent to a Pub/Sub topic

## Cost Comparison for Cloud Scheduler Use Case

### Scenario Analysis

#### Low Usage (100 teams, 1000 scheduler executions/day)
- **Firestore**: 
  - Daily reads: 1,000 (one per execution)
  - Monthly reads: 30,000
  - Cost: $0 (within free tier)
  - Storage: ~$0.01 (minimal credential data)

- **Secret Manager**:
  - Active secrets: 100
  - Monthly cost: 100 × $0.06 = $6.00
  - Monthly operations: 30,000
  - Operations cost: (30,000 ÷ 10,000) × $0.03 = $0.09
  - Total: $6.09 per month

#### Medium Usage (500 teams, 10,000 scheduler executions/day)
- **Firestore**:
  - Daily reads: 10,000
  - Monthly reads: 300,000
  - Cost: (300,000 ÷ 100,000) × $0.06 = $0.18
  - Storage: ~$0.05

- **Secret Manager**:
  - Active secrets: 500
  - Monthly cost: 500 × $0.06 = $30.00
  - Monthly operations: 300,000
  - Operations cost: (300,000 ÷ 10,000) × $0.03 = $0.90
  - Total: $30.90 per month

#### High Usage (1000 teams, 50,000 scheduler executions/day)
- **Firestore**:
  - Daily reads: 50,000
  - Monthly reads: 1,500,000
  - Cost: (1,500,000 ÷ 100,000) × $0.06 = $0.90
  - Storage: ~$0.10

- **Secret Manager**:
  - Active secrets: 1,000
  - Monthly cost: 1,000 × $0.06 = $60.00
  - Monthly operations: 1,500,000
  - Operations cost: (1,500,000 ÷ 10,000) × $0.03 = $4.50
  - Total: $64.50 per month

## Cost Analysis Summary

### When Firestore is More Cost-Effective
- **Low usage scenarios** where you're within the free tier
- Applications with **infrequent access patterns**
- Cases where you're already using Firestore for other purposes

### When Secret Manager is More Cost-Effective
- **High access frequency** scenarios (many scheduler executions)
- Applications requiring **advanced security features** (versioning, audit trails, automatic rotation)
- When the **security compliance** benefits outweigh the cost difference

### Break-Even Analysis
- For 1000 teams with 50,000 daily executions, Secret Manager costs ~$64.50 vs Firestore ~$0.90
- However, Secret Manager provides significantly better security features
- The cost difference is approximately **$63.60/month** for the high-usage scenario

## Recommendations

### For Cloud Scheduler Service
1. **If cost is the primary concern**: Use Firestore for credential storage, especially if usage is low and you're within free tier limits.

2. **If security is the primary concern**: Use Secret Manager despite higher costs, as it provides:
   - Better security controls
   - Audit trails
   - Automatic rotation capabilities
   - Dedicated secret management features

3. **Hybrid approach**: 
   - Use Secret Manager for high-security credentials
   - Use Firestore for less sensitive data
   - Implement caching to reduce API calls in both cases

4. **Optimization strategies**:
   - Implement aggressive caching to reduce API calls
   - Use the event-driven approach from `css-secret-notifications.md` to minimize unnecessary fetches
   - Monitor usage patterns to optimize the choice of service

## Conclusion

For the Cloud Scheduler Service use case where credentials are accessed on every scheduler execution, Secret Manager has higher operational costs than Firestore. However, the security benefits of Secret Manager (versioning, audit logs, rotation) may justify the additional cost, especially for sensitive authentication credentials. The choice depends on the trade-off between cost efficiency and security requirements.

## References

1. Google Cloud Firestore Pricing: https://firebase.google.com/docs/firestore/billing-example
2. Google Cloud Secret Manager Pricing: https://cloud.google.com/security/products/secret-manager
3. Google Cloud Pricing Calculator: https://cloud.google.com/products/calculator
4. Google Cloud Secret Manager Documentation: https://docs.cloud.google.com/secret-manager/docs/