# GCP Secret Manager Java Examples

This directory contains comprehensive Java examples for working with GCP Secret Manager in both key-value and file formats, specifically designed for GKE deployments.

## Project Structure

```
java-examples/
├── README.md                           # This file
├── pom.xml                            # Maven dependencies
├── src/main/java/
│   ├── SecretManagerDemo.java         # Main demo application
│   ├── config/
│   │   ├── SecretManagerConfig.java   # Spring configuration
│   │   └── AppProperties.java         # Application properties
│   ├── service/
│   │   ├── SecretManagerService.java  # Core secret management service
│   │   └── AuthenticationService.java # Authentication using secrets
│   └── model/
│       └── SecretType.java           # Secret type enumeration
├── src/main/resources/
│   ├── application.yml               # Spring Boot configuration
│   └── sample-files/
│       └── sample-keystore.jks       # Sample file for testing
└── k8s/
    ├── deployment.yaml               # Kubernetes deployment
    ├── service-account.yaml          # Kubernetes service account
    └── secret-setup.sh              # Script to create GCP secrets
```

## Features

1. **Key-Value Secret Management**: Store and retrieve simple string values
2. **File-Based Secret Management**: Store and retrieve binary files (Base64 encoded)
3. **Spring Boot Integration**: Seamless integration with Spring Boot applications
4. **GKE Workload Identity**: Configured for secure authentication in GKE
5. **Authentication Example**: Complete example using secrets for user authentication

## Quick Start

1. Set up GCP environment and create secrets
2. Deploy to GKE with Workload Identity
3. Run the application to see both secret types in action

See individual files for detailed implementation and usage examples.