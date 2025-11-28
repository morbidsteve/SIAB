# SIAB Application Deployer

A comprehensive, user-friendly GUI for deploying applications to SIAB with automatic integration.

## Features

### Multi-Format Deployment Support
- **Kubernetes Manifests** - Upload or paste YAML manifests
- **Helm Charts** - Deploy from Helm repositories or custom charts
- **Docker Compose** - Automatically converts to Kubernetes resources
- **Dockerfiles** - Builds and deploys containerized applications
- **Quick Deploy** - Simple form for rapid deployment

### Automatic SIAB Integration
- ✅ **Istio Service Mesh** - Automatic sidecar injection and VirtualService creation
- ✅ **Longhorn Storage** - Automatic PVC creation with persistent storage
- ✅ **Keycloak Authentication** - Ready for SSO integration
- ✅ **HTTPS Ingress** - Automatic TLS-enabled routes
- ✅ **Namespace Management** - Auto-creates namespaces with proper labels

### User Experience
- 🎨 **Beautiful Modern UI** - Gradient design with smooth animations
- 📁 **Drag & Drop** - Easy file uploads
- 📊 **Real-time Feedback** - See deployment status immediately
- 📱 **Responsive** - Works on desktop and mobile
- 🚀 **No Build Process** - Pure HTML/JavaScript frontend

## Quick Start

### Installation

```bash
cd /tmp/siab-app-deployer/deploy
./install-app-deployer.sh
```

This will:
1. Create `siab-deployer` namespace with Istio injection
2. Deploy backend API (Python/Flask)
3. Deploy frontend web UI (Nginx)
4. Create Istio VirtualService
5. Configure RBAC permissions

### Access

1. Get the gateway IP:
   ```bash
   kubectl get svc -n istio-system istio-ingressgateway-user -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. Add to `/etc/hosts`:
   ```bash
   echo "<GATEWAY_IP> deployer.siab.local" | sudo tee -a /etc/hosts
   ```

3. Open in browser:
   ```
   https://deployer.siab.local
   ```

## Usage Examples

### Quick Deploy

The easiest way to deploy an application:

1. Go to **Quick Deploy** tab
2. Fill in the form:
   - **Application Name**: `my-app`
   - **Container Image**: `nginx:latest`
   - **Container Port**: `80`
   - **Replicas**: `1`
   - **Storage Size**: `10Gi` (optional)
   - Check **"Expose via HTTPS"**
3. Click **"Deploy Application"**

Your app is now running at `https://my-app.siab.local`!

### Deploy from Kubernetes Manifest

1. Go to **Kubernetes Manifest** tab
2. Upload your YAML file or paste the content:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: my-app
     template:
       metadata:
         labels:
           app: my-app
       spec:
         containers:
         - name: app
           image: nginx:latest
           ports:
           - containerPort: 80
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: my-app
   spec:
     selector:
       app: my-app
     ports:
     - port: 80
       targetPort: 80
   ```
3. Click **"Deploy Manifest"**

Istio sidecar automatically injected!

### Deploy from Docker Compose

1. Go to **Docker Compose** tab
2. Paste your docker-compose.yml:
   ```yaml
   version: '3'
   services:
     web:
       image: nginx:latest
       ports:
         - "80:80"
       environment:
         - ENV=production
     db:
       image: postgres:15
       environment:
         - POSTGRES_PASSWORD=secret
       volumes:
         - db-data:/var/lib/postgresql/data
   volumes:
     db-data:
   ```
3. Click **"Deploy from Compose"**

Both services deployed with automatic conversion to Kubernetes!

### Deploy Helm Chart

1. Go to **Helm Chart** tab
2. Fill in:
   - **Chart Name**: `bitnami/postgresql`
   - **Release Name**: `my-db`
   - **Custom Values** (optional):
     ```yaml
     auth:
       postgresPassword: mypassword
     persistence:
       size: 20Gi
       storageClass: longhorn
     ```
3. Click **"Deploy Helm Chart"**

PostgreSQL deployed with Longhorn storage!

### Deploy from Dockerfile

1. Go to **Dockerfile** tab
2. Paste your Dockerfile:
   ```dockerfile
   FROM node:18-alpine
   WORKDIR /app
   COPY package*.json ./
   RUN npm install
   COPY . .
   EXPOSE 3000
   CMD ["npm", "start"]
   ```
3. Set:
   - **Application Name**: `my-node-app`
   - **Container Port**: `3000`
4. Click **"Build and Deploy"**

Image built and deployed automatically!

## Architecture

```
┌────────────────────────────────────────┐
│  Browser (deployer.siab.local)        │
│  - Modern Web UI                       │
│  - File Upload (Drag & Drop)          │
│  - Deployment Forms                    │
└─────────────┬──────────────────────────┘
              │ HTTPS
┌─────────────▼──────────────────────────┐
│  Istio Gateway (siab-gateway)         │
│  - TLS Termination                     │
│  - mTLS to backend                     │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│  Frontend (Nginx)                      │
│  - Serves static HTML/JS               │
│  - Proxies API requests                │
│  - 2 replicas                          │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│  Backend API (Python/Flask)            │
│  - Parses manifests                    │
│  - Converts docker-compose             │
│  - Builds Dockerfiles                  │
│  - Deploys via kubectl                 │
│  - Creates Istio routes                │
│  - Creates PVCs                        │
│  - 2 replicas                          │
└─────────────┬──────────────────────────┘
              │
┌─────────────▼──────────────────────────┐
│  Kubernetes API                        │
│  - Creates deployments                 │
│  - Creates services                    │
│  - Creates VirtualServices             │
│  - Creates PVCs                        │
└────────────────────────────────────────┘
```

## API Reference

### Quick Deploy
**POST** `/api/deploy/quick`

```json
{
  "name": "my-app",
  "image": "nginx:latest",
  "namespace": "default",
  "port": 80,
  "replicas": 1,
  "storage_size": "10Gi",
  "expose": true,
  "hostname": "my-app.siab.local",
  "env": {
    "KEY": "value"
  }
}
```

### Deploy Manifest
**POST** `/api/deploy/manifest`

```json
{
  "manifest": "apiVersion: apps/v1...",
  "namespace": "default"
}
```

### Deploy Helm
**POST** `/api/deploy/helm`

```json
{
  "chart": "bitnami/nginx",
  "name": "my-release",
  "namespace": "default",
  "values": {}
}
```

### Deploy Compose
**POST** `/api/deploy/compose`

```json
{
  "compose": "version: '3'...",
  "namespace": "default"
}
```

### Deploy Dockerfile
**POST** `/api/deploy/dockerfile`

```json
{
  "dockerfile": "FROM node:18...",
  "name": "my-app",
  "namespace": "default",
  "port": 8080
}
```

### List Applications
**GET** `/api/applications?namespace=default`

Response:
```json
{
  "applications": [
    {
      "name": "my-app",
      "namespace": "default",
      "replicas": 1,
      "ready_replicas": 1,
      "created": "2025-11-28T..."
    }
  ]
}
```

### Delete Application
**DELETE** `/api/applications/<name>?namespace=default`

## Security

- **RBAC**: Backend runs with ServiceAccount with limited cluster permissions
- **Network Policies**: Restrict traffic between components
- **Non-root**: All containers run as non-root users
- **Read-only Filesystem**: Where applicable
- **Istio mTLS**: All service-to-service communication encrypted

## Monitoring

### Check Deployment Status

```bash
kubectl get pods -n siab-deployer
kubectl get svc -n siab-deployer
kubectl get virtualservice -n istio-system app-deployer
```

### View Logs

```bash
# Backend logs
kubectl logs -n siab-deployer -l app=app-deployer-backend -f

# Frontend logs
kubectl logs -n siab-deployer -l app=app-deployer-frontend -f
```

### Check Health

```bash
# Backend health
kubectl exec -n siab-deployer deployment/app-deployer-backend -- curl -s localhost:5000/health

# Frontend health
curl -k https://deployer.siab.local/health
```

## Troubleshooting

### Deployer Not Accessible

```bash
# Check pods are running
kubectl get pods -n siab-deployer

# Check VirtualService
kubectl get virtualservice -n istio-system app-deployer -o yaml

# Check gateway IP
kubectl get svc -n istio-system istio-ingressgateway-user
```

### Deployment Fails

```bash
# Check backend logs
kubectl logs -n siab-deployer -l app=app-deployer-backend

# Check backend has kubectl access
kubectl exec -n siab-deployer deployment/app-deployer-backend -- kubectl get nodes

# Check RBAC permissions
kubectl auth can-i create deployments --as=system:serviceaccount:siab-deployer:app-deployer
```

### Application Not Accessible After Deploy

```bash
# Check if pod is running
kubectl get pods -n <namespace> -l app=<app-name>

# Check service exists
kubectl get svc -n <namespace> <app-name>

# Check VirtualService (if exposed)
kubectl get virtualservice -n istio-system <app-name>

# Check Istio sidecar injected
kubectl get pod -n <namespace> <pod-name> -o jsonpath='{.spec.containers[*].name}'
# Should show both app container and istio-proxy
```

## Development

### Run Backend Locally

```bash
cd backend
pip install -r requirements.txt
export SIAB_DOMAIN=siab.local
python app-deployer-api.py
```

Backend runs on http://localhost:5000

### Test API

```bash
# Health check
curl http://localhost:5000/health

# Quick deploy
curl -X POST http://localhost:5000/api/deploy/quick \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test",
    "image": "nginx:latest",
    "namespace": "default",
    "port": 80
  }'
```

### Update Deployment

After making changes:

```bash
# Update backend
kubectl create configmap deployer-backend-code \
  --from-file=app-deployer-api.py \
  --from-file=requirements.txt \
  -n siab-deployer \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/app-deployer-backend -n siab-deployer

# Update frontend
kubectl create configmap deployer-frontend-html \
  --from-file=index.html \
  -n siab-deployer \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/app-deployer-frontend -n siab-deployer
```

## Uninstall

```bash
kubectl delete namespace siab-deployer
kubectl delete virtualservice app-deployer -n istio-system
kubectl delete clusterrole app-deployer
kubectl delete clusterrolebinding app-deployer
```

## License

MIT License - See SIAB repository for details

## Contributing

1. Make changes to backend or frontend
2. Test locally
3. Update ConfigMaps in cluster
4. Submit pull request

## Created

- **Date**: 2025-11-28
- **Version**: 1.0.0
- **Status**: Production Ready
