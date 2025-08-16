#!/bin/bash

# Timeout API Runner Script

echo "=== Timeout API Application ==="
echo

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo "Error: Maven is not installed. Please install Maven first."
    exit 1
fi

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo "Error: Java is not installed. Please install Java 11 or higher."
    exit 1
fi

# Function to build the application
build_app() {
    echo "Building the application..."
    mvn clean package -q
    if [ $? -eq 0 ]; then
        echo "✅ Build successful!"
    else
        echo "❌ Build failed!"
        exit 1
    fi
}

# Function to run the application
run_app() {
    echo "Starting the Timeout API application..."
    echo "The application will be available at: http://localhost:8080"
    echo
    echo "Available endpoints:"
    echo "  - GET /api/timeout?timeout=<seconds>  (Main timeout endpoint)"
    echo "  - GET /api/health                     (Health check)"
    echo
    echo "Example usage:"
    echo "  curl http://localhost:8080/api/timeout?timeout=5"
    echo
    echo "Press Ctrl+C to stop the application"
    echo "----------------------------------------"
    
    java -jar target/timeout-api-1.0.0.jar
}

# Main execution
case "$1" in
    "build")
        build_app
        ;;
    "run")
        if [ ! -f "target/timeout-api-1.0.0.jar" ]; then
            echo "JAR file not found. Building first..."
            build_app
        fi
        run_app
        ;;
    "clean")
        echo "Cleaning build artifacts..."
        mvn clean -q
        echo "✅ Clean completed!"
        ;;
    *)
        echo "Usage: $0 {build|run|clean}"
        echo
        echo "Commands:"
        echo "  build  - Build the application"
        echo "  run    - Run the application (builds if needed)"
        echo "  clean  - Clean build artifacts"
        echo
        echo "Quick start: $0 run"
        exit 1
        ;;
esac