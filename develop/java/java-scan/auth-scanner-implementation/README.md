# Auth Scanner Implementation

This directory contains the source code for the Java Auth Scanner.

## Prerequisites
- Java 11+
- Maven 3+

## Building
```bash
mvn clean package
```
The executable JAR will be created at `target/auth-scanner-1.0-SNAPSHOT.jar`.

## Usage
```bash
java -jar target/auth-scanner-1.0-SNAPSHOT.jar <path-to-target-app.jar> [--output <report-file.json>]
```

## Example
```bash
# Build the scanner
mvn clean package

# Run against a test target (assuming you have one)
java -jar target/auth-scanner-1.0-SNAPSHOT.jar ../test-target/test-app.jar
```

## Output
The tool outputs a JSON report. If issues are found, it exits with code 1.
