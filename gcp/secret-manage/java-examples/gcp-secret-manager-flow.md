# GCP Secret Manager Complete Flow Guide

This document provides a comprehensive overview of how Java Spring Boot applications in GKE integrate with GCP Secret Manager using Workload Identity for both key-value and file-based secrets.

Key Features of the Flow Document:
📊 Multiple Mermaid Diagrams
Architecture Overview: Shows the relationship between all components
Sequence Diagrams: Detailed step-by-step processes for setup, deployment, and secret retrieval
Flowcharts: Decision trees for error handling and troubleshooting
Component Interaction Diagrams: How different parts communicate
🔄 Three Main Phases
Infrastructure Setup: GCP configuration, IAM, Workload Identity
Application Deployment: Container building and Kubernetes deployment
Secret Retrieval: Runtime secret access and usage
🔐 Two Secret Types Covered
Key-Value Secrets: Simple strings (passwords, API keys)
File-Based Secrets: Binary content (certificates, keystores)
🛠 Practical Elements
Complete setup checklist
Troubleshooting guide with common issues
Performance optimization tips
Security best practices
Monitoring and observability guidance
📈 Visual Learning
Color-coded components for easy identification
Step-by-step sequence flows
Error handling decision trees
Permission matrix and verification steps
The document serves as both a learning resource and a practical implementation guide, showing exactly how your Java Spring Boot application running in GKE can securely access secrets from GCP Secret Manager using Workload Identity - eliminating the need for service account key files while maintaining enterprise-grade security.

## Overview

The complete process involves several key components working together:

- **GCP Secret Manager**: Stores encrypted secrets
- **Workload Identity**: Provides secure authentication without service account keys
- **GKE**: Kubernetes cluster running the application
- **Spring Boot**: Application framework with GCP integration
- **Java Application**: Consumes secrets for authentication and configuration

## Architecture Overview

```mermaid
graph TB
    subgraph "GCP Project"
        SM[Secret Manager]
        GSA[Google Service Account]
        WI[Workload Identity Pool]
    end

    subgraph "GKE Cluster"
        KSA[Kubernetes Service Account]
        POD[Application Pod]
        APP[Spring Boot App]
    end

    subgraph "Secrets"
        KV[Key-Value Secrets<br/>passwords, API keys]
        FB[File-Based Secrets<br/>certificates, keystores]
    end

    SM --> KV
    SM --> FB
    GSA --> SM
    WI --> GSA
    KSA --> WI
    POD --> KSA
    APP --> POD
    APP --> SM

    style SM fill:#e1f5fe
    style GSA fill:#f3e5f5
    style KSA fill:#e8f5e8
    style APP fill:#fff3e0
```

## Complete Process Flow

### Phase 1: Infrastructure Setup

```mermaid
sequenceDiagram
    participant Admin as Platform Admin
    participant GCP as GCP Console/CLI
    participant SM as Secret Manager
    participant IAM as IAM Service
    participant GKE as GKE Cluster

    Note over Admin,GKE: Phase 1: Infrastructure Setup

    Admin->>GCP: 1. Enable APIs (Secret Manager, GKE)
    Admin->>SM: 2. Create secrets (key-value & file-based)
    Admin->>IAM: 3. Create Google Service Account (GSA)
    Admin->>IAM: 4. Grant secretAccessor role to GSA
    Admin->>GKE: 5. Enable Workload Identity on cluster
    Admin->>GKE: 6. Create Kubernetes Service Account (KSA)
    Admin->>IAM: 7. Bind KSA to GSA (Workload Identity)

    Note over Admin: Setup Complete - Ready for Application Deployment
```

### Phase 2: Application Deployment and Startup

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Registry as Container Registry
    participant K8s as Kubernetes API
    participant Pod as Application Pod
    participant App as Spring Boot App

    Note over Dev,App: Phase 2: Application Deployment

    Dev->>Registry: 1. Build & push Docker image
    Dev->>K8s: 2. Apply deployment manifests
    K8s->>Pod: 3. Schedule pod with KSA binding
    Pod->>App: 4. Start Spring Boot application
    App->>App: 5. Load application.yml with sm:// references

    Note over App: Application Ready - Secrets will be loaded on demand
```

### Phase 3: Secret Retrieval Process

```mermaid
sequenceDiagram
    participant App as Spring Boot App
    participant WI as Workload Identity
    participant STS as Security Token Service
    participant SM as Secret Manager
    participant FS as File System

    Note over App,FS: Phase 3: Secret Retrieval Process

    App->>App: 1. Application needs secret
    App->>WI: 2. Request GCP credentials
    WI->>STS: 3. Exchange KSA token for GCP token
    STS-->>WI: 4. Return OAuth 2.0 access token
    WI-->>App: 5. Provide GCP credentials

    alt Key-Value Secret
        App->>SM: 6a. Call accessSecretVersion API
        SM-->>App: 7a. Return secret value (string)
        App->>App: 8a. Use secret directly (password, API key)
    else File-Based Secret
        App->>SM: 6b. Call accessSecretVersion API
        SM-->>App: 7b. Return Base64 encoded content
        App->>App: 8b. Decode Base64 to bytes
        App->>FS: 9b. Write to file system (optional)
        App->>App: 10b. Use file content (keystore, certificate)
    end

    Note over App: Secret Retrieved and Ready for Use
```

## Detailed Component Interactions

### Workload Identity Authentication Flow

```mermaid
graph LR
    subgraph "Pod Environment"
        A[Application Process]
        B[GKE Metadata Server]
    end

    subgraph "GCP Services"
        C[Security Token Service]
        D[Secret Manager API]
    end

    A -->|1. Request credentials| B
    B -->|2. Get KSA token| B
    B -->|3. Exchange token| C
    C -->|4. Return OAuth token| B
    B -->|5. Provide credentials| A
    A -->|6. API call with token| D
    D -->|7. Return secret| A

    style A fill:#fff3e0
    style B fill:#e8f5e8
    style C fill:#f3e5f5
    style D fill:#e1f5fe
```

### Spring Boot Secret Integration

```mermaid
graph TD
    subgraph "Spring Boot Application"
        A[Application Startup]
        B[Configuration Loading]
        C[Property Resolution]
        D[Secret Manager Client]
        E[Application Components]
    end

    subgraph "Configuration Sources"
        F[application.yml<br/>sm:// references]
        G[Environment Variables]
        H[Command Line Args]
    end

    subgraph "Secret Types"
        I[Key-Value Secrets<br/>Direct injection]
        J[File-Based Secrets<br/>Programmatic access]
    end

    A --> B
    B --> F
    B --> G
    B --> H
    B --> C
    C --> D
    D --> I
    D --> J
    I --> E
    J --> E

    style A fill:#fff3e0
    style D fill:#e1f5fe
    style I fill:#e8f5e8
    style J fill:#f3e5f5
```

## Secret Types and Usage Patterns

### Key-Value Secrets

Key-value secrets are simple string values stored in Secret Manager, perfect for:

- Database passwords
- API keys
- JWT signing keys
- Configuration values

#### Storage Process

```mermaid
flowchart LR
    A[Plain Text Secret] --> B[gcloud CLI]
    B --> C[Secret Manager]
    C --> D[Encrypted Storage]

    style A fill:#fff3e0
    style C fill:#e1f5fe
    style D fill:#e8f5e8
```

#### Retrieval Process

```mermaid
flowchart LR
    A[Spring Boot App] --> B[sm:// Protocol]
    B --> C[Secret Manager Client]
    C --> D[API Call]
    D --> E[Decrypted Value]
    E --> F[Application Property]

    style A fill:#fff3e0
    style C fill:#e1f5fe
    style F fill:#e8f5e8
```

### File-Based Secrets

File-based secrets store binary content (Base64 encoded) for:

- SSL certificates
- Keystores (JKS, PKCS12)
- Private keys
- Configuration files

#### Storage Process

```mermaid
flowchart TD
    A[Binary File<br/>keystore.jks] --> B[Base64 Encoding]
    B --> C[gcloud CLI]
    C --> D[Secret Manager]
    D --> E[Encrypted Storage<br/>Base64 String]

    style A fill:#fff3e0
    style D fill:#e1f5fe
    style E fill:#e8f5e8
```

#### Retrieval Process

```mermaid
flowchart TD
    A[Spring Boot App] --> B[SecretManagerService]
    B --> C[API Call]
    C --> D[Base64 String]
    D --> E[Base64 Decoding]
    E --> F[Binary Content]
    F --> G{Usage Pattern}
    G -->|Option 1| H[Write to File System]
    G -->|Option 2| I[Use in Memory]

    style A fill:#fff3e0
    style B fill:#e1f5fe
    style F fill:#e8f5e8
    style H fill:#f3e5f5
    style I fill:#f3e5f5
```

## Authentication Flow Deep Dive

### Complete Authentication Sequence

```mermaid
sequenceDiagram
    participant App as Java Application
    participant Meta as GKE Metadata Server
    participant K8s as Kubernetes API
    participant STS as Google STS
    participant SM as Secret Manager

    Note over App,SM: Authentication and Secret Retrieval

    App->>Meta: 1. Request service account token
    Meta->>K8s: 2. Get KSA projected token
    K8s-->>Meta: 3. Return KSA JWT token
    Meta->>STS: 4. Exchange KSA token for GCP token
    Note over STS: Validates KSA token<br/>Checks Workload Identity binding
    STS-->>Meta: 5. Return OAuth 2.0 access token
    Meta-->>App: 6. Provide GCP credentials

    App->>SM: 7. Call Secret Manager API with token
    Note over SM: Validates token<br/>Checks IAM permissions
    SM-->>App: 8. Return encrypted secret
    App->>App: 9. Process secret (decode if file-based)

    Note over App: Secret ready for use
```

### Error Handling Flow

```mermaid
flowchart TD
    A[Secret Request] --> B{Workload Identity<br/>Configured?}
    B -->|No| C[Authentication Error<br/>403 Forbidden]
    B -->|Yes| D{GSA has<br/>secretAccessor role?}
    D -->|No| E[Permission Denied<br/>403 Forbidden]
    D -->|Yes| F{Secret Exists?}
    F -->|No| G[Not Found<br/>404 Error]
    F -->|Yes| H{Valid Version?}
    H -->|No| I[Version Not Found<br/>404 Error]
    H -->|Yes| J[Success<br/>Return Secret]

    style C fill:#ffebee
    style E fill:#ffebee
    style G fill:#ffebee
    style I fill:#ffebee
    style J fill:#e8f5e8
```

## Implementation Examples

### Key-Value Secret Implementation

```mermaid
graph TD
    subgraph "Configuration (application.yml)"
        A["app:<br/>  secrets:<br/>    database-password: ${sm://database-password}<br/>    api-key: ${sm://third-party-api-key}"]
    end

    subgraph "Java Code"
        B["@Value('${app.secrets.database-password}')<br/>private String dbPassword;"]
        C["@Autowired<br/>private SecretManagerService secretService;"]
        D["String secret = secretService.getKeyValueSecret('jwt-key');"]
    end

    subgraph "Usage"
        E[Database Connection]
        F[API Authentication]
        G[JWT Token Signing]
    end

    A --> B
    A --> C
    C --> D
    B --> E
    B --> F
    D --> G

    style A fill:#e3f2fd
    style B fill:#fff3e0
    style C fill:#fff3e0
    style D fill:#fff3e0
```

### File-Based Secret Implementation

```mermaid
graph TD
    subgraph "Secret Storage"
        A[keystore.jks file] --> B[Base64 encode]
        B --> C[Store in Secret Manager<br/>as 'keystore-jks-secret']
    end

    subgraph "Java Implementation"
        D[SecretManagerService] --> E[getFileSecret method]
        E --> F[Base64 decode]
        F --> G{Usage Pattern}
        G --> H[writeFileSecretToPath<br/>Write to /tmp/secrets/]
        G --> I[Direct byte array usage<br/>In-memory processing]
    end

    subgraph "Application Usage"
        H --> J[SSL Configuration]
        H --> K[Database SSL Connection]
        I --> L[Certificate Validation]
        I --> M[Cryptographic Operations]
    end

    C --> D

    style A fill:#fff3e0
    style C fill:#e1f5fe
    style D fill:#e8f5e8
    style J fill:#f3e5f5
    style K fill:#f3e5f5
    style L fill:#f3e5f5
    style M fill:#f3e5f5
```

## Security and Best Practices

### Security Model

```mermaid
graph TB
    subgraph "Security Layers"
        A[Workload Identity<br/>No static keys]
        B[IAM Permissions<br/>Least privilege]
        C[Secret Manager<br/>Encryption at rest]
        D[TLS in Transit<br/>API communication]
        E[Audit Logging<br/>Access tracking]
    end

    subgraph "Threat Mitigation"
        F[Key Rotation<br/>Automated updates]
        G[Access Control<br/>Fine-grained permissions]
        H[Monitoring<br/>Anomaly detection]
    end

    A --> F
    B --> G
    C --> F
    D --> H
    E --> H

    style A fill:#e8f5e8
    style B fill:#e8f5e8
    style C fill:#e8f5e8
    style D fill:#e8f5e8
    style E fill:#e8f5e8
```

### Permission Matrix

| Component                  | Required Permissions                 | Purpose            |
| -------------------------- | ------------------------------------ | ------------------ |
| Google Service Account     | `roles/secretmanager.secretAccessor` | Read secret values |
| Kubernetes Service Account | `roles/iam.workloadIdentityUser`     | Impersonate GSA    |
| GKE Node Pool              | `cloud-platform` OAuth scope         | Access GCP APIs    |
| Secret Manager             | Project-level or secret-level IAM    | Control access     |

## Troubleshooting Guide

### Common Issues and Solutions

```mermaid
flowchart TD
    A[Application Error] --> B{Error Type}

    B --> C[403 Forbidden]
    B --> D[404 Not Found]
    B --> E[Connection Timeout]
    B --> F[Decoding Error]

    C --> C1[Check Workload Identity binding]
    C --> C2[Verify GSA permissions]
    C --> C3[Confirm KSA annotation]

    D --> D1[Verify secret name]
    D --> D2[Check secret version]
    D --> D3[Confirm project ID]

    E --> E1[Check network connectivity]
    E --> E2[Verify GKE metadata server]
    E --> E3[Check OAuth scopes]

    F --> F1[Validate Base64 encoding]
    F --> F2[Check file format]
    F --> F3[Verify secret content]

    style C fill:#ffebee
    style D fill:#ffebee
    style E fill:#ffebee
    style F fill:#ffebee
```

## Complete Setup Checklist

### Infrastructure Setup

```mermaid
graph LR
    A[Enable APIs] --> B[Create Secrets]
    B --> C[Create GSA]
    C --> D[Grant Permissions]
    D --> E[Setup Workload Identity]
    E --> F[Create KSA]
    F --> G[Bind KSA to GSA]
    G --> H[Deploy Application]

    style A fill:#e3f2fd
    style B fill:#e3f2fd
    style C fill:#f3e5f5
    style D fill:#f3e5f5
    style E fill:#e8f5e8
    style F fill:#e8f5e8
    style G fill:#e8f5e8
    style H fill:#fff3e0
```

### Verification Steps

1. **API Enablement**

   ```bash
   gcloud services list --enabled | grep secretmanager
   ```

2. **Secret Creation**

   ```bash
   gcloud secrets list --project=YOUR_PROJECT_ID
   ```

3. **GSA Permissions**

   ```bash
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

4. **Workload Identity Binding**

   ```bash
   gcloud iam service-accounts get-iam-policy GSA_EMAIL
   ```

5. **KSA Configuration**
   ```bash
   kubectl describe sa KSA_NAME -n NAMESPACE
   ```

## Performance Considerations

### Caching Strategy

```mermaid
graph TD
    A[First Secret Request] --> B[API Call to Secret Manager]
    B --> C[Store in Local Cache]
    C --> D[Return Secret to Application]

    E[Subsequent Requests] --> F{Cache Hit?}
    F -->|Yes| G[Return Cached Value]
    F -->|No| H[API Call to Secret Manager]
    H --> I[Update Cache]
    I --> J[Return Secret]

    K[Cache Invalidation] --> L[TTL Expiry]
    K --> M[Manual Refresh]
    K --> N[Application Restart]

    style C fill:#e8f5e8
    style G fill:#e8f5e8
    style I fill:#e8f5e8
```

### Optimization Tips

1. **Cache Secrets**: Avoid repeated API calls
2. **Batch Operations**: Retrieve multiple secrets together
3. **Lazy Loading**: Load secrets only when needed
4. **Error Handling**: Implement retry logic with exponential backoff
5. **Monitoring**: Track API usage and performance metrics

## Monitoring and Observability

### Key Metrics to Monitor

```mermaid
graph TB
    subgraph "Application Metrics"
        A[Secret Retrieval Latency]
        B[Cache Hit Rate]
        C[Error Rate]
    end

    subgraph "GCP Metrics"
        D[Secret Manager API Calls]
        E[Authentication Success Rate]
        F[Permission Denied Errors]
    end

    subgraph "Infrastructure Metrics"
        G[Pod Restart Count]
        H[Workload Identity Token Refresh]
        I[Network Connectivity]
    end

    A --> J[Application Dashboard]
    B --> J
    C --> J
    D --> K[GCP Monitoring]
    E --> K
    F --> K
    G --> L[Kubernetes Dashboard]
    H --> L
    I --> L

    style J fill:#e3f2fd
    style K fill:#e8f5e8
    style L fill:#fff3e0
```

## Summary

This comprehensive flow demonstrates how GCP Secret Manager integrates with Java Spring Boot applications in GKE using Workload Identity. The key benefits include:

- **Security**: No static service account keys
- **Scalability**: Automatic credential management
- **Flexibility**: Support for both key-value and file-based secrets
- **Observability**: Full audit trail and monitoring capabilities
- **Maintainability**: Centralized secret management

The implementation provides a robust, secure, and scalable solution for managing sensitive data in cloud-native Java applications.
