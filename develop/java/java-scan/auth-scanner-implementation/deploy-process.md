# Auth Scanner Deployment & Integration Guide

## Overview
This document describes how to integrate the `auth-scanner` into your CI/CD pipeline to ensure all Java APIs have proper authentication checks before deployment.

## 1. Build the Scanner
First, build the scanner JAR. This can be done once and the resulting JAR stored in a shared artifact repository, or built as part of the pipeline.

```bash
cd auth-scanner-implementation
mvn clean package
# The output will be at: target/auth-scanner-1.0-SNAPSHOT.jar
```

## 2. Integration into CI Pipeline
The scanner should run **after** the application build but **before** the Docker image build/deployment.

### Example: GitLab CI

```yaml
stages:
  - build
  - scan
  - deploy

build_app:
  stage: build
  script:
    - mvn clean package
  artifacts:
    paths:
      - target/my-app.jar

auth_scan:
  stage: scan
  script:
    # Download scanner (or use from previous stage if built there)
    - wget http://internal-repo/auth-scanner.jar
    # Run scan
    - java -jar auth-scanner.jar target/my-app.jar --output auth-report.json
  artifacts:
    paths:
      - auth-report.json
    when: always
  allow_failure: false # Fail the pipeline if issues are found
```

### Example: Jenkins Pipeline

```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean package'
            }
        }
        stage('Security Scan') {
            steps {
                script {
                    // Assume auth-scanner.jar is available in workspace or /opt/tools
                    def exitCode = sh(script: 'java -jar /opt/tools/auth-scanner.jar target/my-app.jar --output auth-report.json', returnStatus: true)
                    if (exitCode != 0) {
                        error("Auth Scanner found security issues! Check auth-report.json")
                    }
                }
            }
        }
        stage('Deploy') {
            steps {
                // Deploy steps...
            }
        }
    }
}
```

## 3. Scanner Rules
The scanner currently enforces:
- **Controller Detection**: Scans classes with `@RestController` or `@Controller`.
- **Endpoint Detection**: Scans methods with `@RequestMapping`, `@GetMapping`, etc.
- **Security Check**:
    - Checks if the **Class** has `@PreAuthorize`, `@Secured`, or `@RolesAllowed`.
    - Checks if the **Method** has `@PreAuthorize`, `@Secured`, or `@RolesAllowed`.
    - **Violation**: If neither the class nor the method has one of these annotations, it is flagged as a **HIGH** severity issue.

## 4. Handling False Positives
If you have a public endpoint (e.g., `/login`, `/public/**`) that *should* be insecure, the current scanner is strict.
**Future Improvement**: Add support for a `@PublicApi` annotation to explicitly bypass the check.

## 5. Troubleshooting
- **"Unsupported class file major version"**: Ensure the scanner is running with a Java version compatible with the target application's compiled bytecode.
