# React Docker Application

A production-ready React application containerized with Docker and configured for Kubernetes deployment with health checks, horizontal pod autoscaling, and service configuration.

## 🚀 Features

- **React 18** - Modern React application with hooks
- **Docker Multi-stage Build** - Optimized production build with nginx
- **Health Check Endpoint** - `/.well-known/health` for monitoring
- **Kubernetes Ready** - Complete K8s manifests included
- **Horizontal Pod Autoscaler** - Auto-scaling based on CPU/memory usage
- **Service Configuration** - Both ClusterIP and NodePort services
- **Production Optimized** - Gzip compression, caching, security headers

## 📁 Project Structure

```
React/
├── public/
│   └── index.html              # HTML template
├── src/
│   ├── App.js                  # Main React component
│   ├── App.css                 # Application styles
│   ├── index.js                # React entry point
│   └── index.css               # Global styles
├── k8s/
│   ├── deployment.yaml         # Kubernetes deployment
│   ├── service.yaml            # Kubernetes services
│   └── hpa.yaml                # Horizontal Pod Autoscaler
├── scripts/
│   ├── build.sh                # Docker build script
│   └── deploy.sh               # Kubernetes deploy script
├── Dockerfile                  # Multi-stage Docker build
├── nginx.conf                  # Nginx configuration
├── package.json                # Node.js dependencies
└── README.md                   # This file
```

## 🛠️ Prerequisites

- **Node.js** 18+ and npm
- **Docker** for containerization
- **kubectl** configured for your Kubernetes cluster
- **Kubernetes cluster** with metrics-server enabled (for HPA)

## 🏗️ Local Development

### 1. Install Dependencies
```bash
npm install
```

### 2. Start Development Server
```bash
npm start
```

The application will be available at `http://localhost:3000`

### 3. Build for Production
```bash
npm run build
```

## 🐳 Docker Usage

### Build Docker Image
```bash
# Using the build script
./scripts/build.sh

# Or manually
docker build -t react-docker-app:latest .
```

### Run Docker Container
```bash
docker run -p 8080:80 react-docker-app:latest
```

Access the application at `http://localhost:8080`

### Test Health Check
```bash
curl http://localhost:8080/.well-known/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2025-02-28T10:30:00.000Z",
  "service": "react-app"
}
```

## ☸️ Kubernetes Deployment

### 1. Build and Push Image
```bash
# Build the image
./scripts/build.sh

# Tag for your registry (replace with your registry)
docker tag react-docker-app:latest your-registry/react-docker-app:latest

# Push to registry
docker push your-registry/react-docker-app:latest
```

### 2. Update Image in Deployment
Edit `k8s/deployment.yaml` and update the image reference:
```yaml
image: your-registry/react-docker-app:latest
```

### 3. Deploy to Kubernetes
```bash
# Using the deploy script
./scripts/deploy.sh

# Or manually
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

### 4. Verify Deployment
```bash
# Check pods
kubectl get pods -l app=react-app

# Check services
kubectl get services -l app=react-app

# Check HPA
kubectl get hpa react-app-hpa

# Check deployment status
kubectl rollout status deployment/react-app
```

## 🌐 Accessing the Application

### NodePort Service
The application is accessible via NodePort on port 30080:
```bash
# Get node IP
kubectl get nodes -o wide

# Access application
curl http://<NODE_IP>:30080
```

### Port Forward (for testing)
```bash
kubectl port-forward service/react-app-service 8080:80
```
Then access at `http://localhost:8080`

## 📊 Monitoring and Health Checks

### Health Check Endpoint
- **URL**: `/.well-known/health`
- **Method**: GET
- **Response**: JSON with status, timestamp, and service name

### Kubernetes Probes
- **Liveness Probe**: Checks if container is running
- **Readiness Probe**: Checks if container is ready to serve traffic
- **Both use**: `/.well-known/health` endpoint

### Horizontal Pod Autoscaler
- **Min Replicas**: 2
- **Max Replicas**: 10
- **CPU Target**: 70% utilization
- **Memory Target**: 80% utilization

## 🔧 Configuration

### Environment Variables
Set in `k8s/deployment.yaml`:
```yaml
env:
- name: NODE_ENV
  value: "production"
```

### Resource Limits
Configured in deployment:
- **Requests**: 50m CPU, 64Mi memory
- **Limits**: 100m CPU, 128Mi memory

### Nginx Configuration
- Gzip compression enabled
- Static asset caching (1 year)
- Security headers included
- React Router support

## 🚨 Troubleshooting

### Common Issues

1. **Image Pull Errors**
   ```bash
   # Check if image exists
   docker images | grep react-docker-app
   
   # Verify image in registry
   docker pull your-registry/react-docker-app:latest
   ```

2. **Health Check Failures**
   ```bash
   # Test health endpoint locally
   curl -f http://localhost:8080/.well-known/health
   
   # Check pod logs
   kubectl logs -l app=react-app
   ```

3. **HPA Not Scaling**
   ```bash
   # Check metrics-server
   kubectl top nodes
   kubectl top pods
   
   # Check HPA status
   kubectl describe hpa react-app-hpa
   ```

4. **Service Not Accessible**
   ```bash
   # Check service endpoints
   kubectl get endpoints react-app-service
   
   # Check pod labels
   kubectl get pods --show-labels
   ```

### Debugging Commands
```bash
# Get detailed pod information
kubectl describe pod <pod-name>

# View application logs
kubectl logs -f deployment/react-app

# Execute into container
kubectl exec -it <pod-name> -- /bin/sh

# Check nginx configuration
kubectl exec -it <pod-name> -- cat /etc/nginx/conf.d/default.conf
```

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: Build and Deploy
on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Build Docker image
      run: |
        docker build -t ${{ secrets.REGISTRY }}/react-docker-app:${{ github.sha }} .
        docker push ${{ secrets.REGISTRY }}/react-docker-app:${{ github.sha }}
    
    - name: Deploy to Kubernetes
      run: |
        sed -i 's|react-docker-app:latest|${{ secrets.REGISTRY }}/react-docker-app:${{ github.sha }}|' k8s/deployment.yaml
        kubectl apply -f k8s/
```

## 📈 Performance Optimization

### Docker Image Optimization
- Multi-stage build reduces image size
- Alpine Linux base image
- Only production dependencies included

### Nginx Optimization
- Gzip compression for text files
- Static asset caching
- Efficient serving of React build

### Kubernetes Optimization
- Resource requests and limits set
- Horizontal pod autoscaling configured
- Readiness and liveness probes implemented

## 🔒 Security Considerations

### Nginx Security Headers
- X-Frame-Options: SAMEORIGIN
- X-XSS-Protection: 1; mode=block
- X-Content-Type-Options: nosniff
- Referrer-Policy: no-referrer-when-downgrade

### Kubernetes Security
- Non-root user in container
- Resource limits prevent resource exhaustion
- Health checks ensure only healthy pods serve traffic

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📞 Support

For issues and questions:
- Create an issue in the repository
- Check the troubleshooting section
- Review Kubernetes and Docker documentation