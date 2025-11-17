# SIAB Application Catalog

A web-based catalog for browsing and deploying pre-configured, security-hardened applications to your SIAB cluster.

## Features

- **One-Click Deployment**: Deploy popular applications with a single click
- **Security Integrated**: All apps include vulnerability scanning and security policies
- **Pre-Configured**: Applications come with sensible defaults and best practices
- **Categories**: Organized by type (databases, monitoring, CI/CD, etc.)
- **Search & Filter**: Easily find the right application
- **Deployment Tracking**: See what's deployed and manage it

## Quick Start

### Deploy the Catalog

```bash
# Copy catalog files to SIAB directory
mkdir -p /opt/siab/catalog
cp -r catalog/* /opt/siab/catalog/

# Deploy to cluster
kubectl apply -f catalog/catalog-deployment.yaml
```

### Access the Catalog

```bash
# Get the catalog URL
echo "https://catalog.siab.local"

# Add to /etc/hosts if using local domain
echo "$(kubectl get svc -n istio-system istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}') catalog.siab.local" | sudo tee -a /etc/hosts
```

### Using the Web Interface

1. Open https://catalog.siab.local in your browser
2. Browse applications by category or search
3. Click on an app to see details
4. Click "Deploy" to install to your cluster
5. Monitor deployment status

## Available Applications

### Databases
- **PostgreSQL** - Advanced relational database
- **Redis** - In-memory data store and cache

### Monitoring
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization and dashboards

### CI/CD
- **GitLab Runner** - CI/CD pipeline execution

### Messaging
- **RabbitMQ** - Message broker

### Web Servers
- **NGINX** - High-performance web server

### Development
- **VS Code Server** - Browser-based IDE

### Security
- **HashiCorp Vault** - Secrets management

## Adding Your Own Applications

### 1. Create App Directory

```bash
mkdir -p catalog/apps/your-category/your-app
```

### 2. Create Metadata

Create `metadata.yaml`:

```yaml
id: your-app
name: Your Application
version: 1.0.0
category: your-category
icon: 🚀
description: Brief description of your app
tags:
  - tag1
  - tag2
maintainer: Your Name
documentation: https://your-app.com/docs
```

### 3. Create Manifest

Create `manifest.yaml` using SIABApplication CRD:

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: your-app
spec:
  image: your-app:latest
  replicas: 1
  port: 8080
  # ... rest of configuration
```

### 4. Reload Catalog

The catalog will automatically pick up new applications on restart.

## API Reference

### Get All Categories

```bash
GET /api/categories
```

### Get All Applications

```bash
GET /api/apps?category=databases
```

### Get Application Details

```bash
GET /api/apps/{app_id}
```

### Deploy Application

```bash
POST /api/apps/{app_id}/deploy
Content-Type: application/json

{
  "namespace": "default",
  "values": {}
}
```

### Remove Application

```bash
POST /api/apps/{app_id}/undeploy
Content-Type: application/json

{
  "namespace": "default"
}
```

### Get Deployed Applications

```bash
GET /api/deployed
```

## Architecture

```
┌─────────────────────────────────────┐
│   Browser (catalog.siab.local)     │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│     NGINX Frontend (Static)         │
│  - React UI                         │
│  - Proxy to API                     │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│     Flask Backend API               │
│  - Serves app metadata              │
│  - Deploys via kubectl              │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│     Kubernetes API                  │
│  - Creates SIABApplications         │
│  - SIAB Operator reconciles         │
└─────────────────────────────────────┘
```

## Security

The catalog includes:

- **Authentication**: Integrates with Keycloak for user auth
- **RBAC**: Role-based access control for deployments
- **Network Policies**: Isolated catalog namespace
- **Read-Only Filesystem**: Containers run with minimal permissions
- **Vulnerability Scanning**: All catalog apps are scanned before deployment

## Troubleshooting

### Catalog Not Accessible

```bash
# Check pods
kubectl get pods -n siab-catalog

# Check logs
kubectl logs -n siab-catalog -l app=catalog-backend
kubectl logs -n siab-catalog -l app=catalog-frontend
```

### Deployment Fails

```bash
# Check SIAB operator logs
kubectl logs -n siab-system -l app=siab-operator

# Check application events
kubectl describe siabapplication <app-name>
```

### Apps Not Showing

```bash
# Verify apps directory is mounted
kubectl exec -n siab-catalog deployment/catalog-backend -- ls -la /app/apps

# Check backend logs for errors
kubectl logs -n siab-catalog -l app=catalog-backend
```

## Development

### Run Backend Locally

```bash
cd catalog/backend
pip install -r requirements.txt
python catalog-api.py
```

### Run Frontend Locally

```bash
cd catalog/frontend/public
python -m http.server 8000
```

Then visit http://localhost:8000

## Contributing

To add applications to the catalog:

1. Follow the app structure in `catalog/apps/`
2. Ensure security best practices
3. Test deployment
4. Submit pull request

## License

Apache License 2.0
