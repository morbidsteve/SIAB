# Getting Started with SIAB

This guide will help you install SIAB and deploy your first application.

## Prerequisites

- Rocky Linux 8.x or 9.x
- 4+ CPU cores
- 16GB+ RAM
- 100GB+ disk space
- Root access
- Internet connectivity

## Installation

### Quick Install

Run the one-command installer:

```bash
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

### Manual Install

Clone the repository and run:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./install.sh
```

### Custom Configuration

Set environment variables before installation:

```bash
export SIAB_DOMAIN="mycompany.com"
export SIAB_MINIO_SIZE="500Gi"
sudo ./install.sh
```

## Installation Process

The installer will:

1. **Check System Requirements** - Verify CPU, RAM, and disk space
2. **Install RKE2** - Deploy hardened Kubernetes
3. **Configure Security** - SELinux, firewall, encryption
4. **Deploy Istio** - Service mesh with mTLS
5. **Install Keycloak** - Identity management
6. **Deploy MinIO** - Object storage
7. **Setup Security Tools** - Trivy scanning, OPA Gatekeeper
8. **Install SIAB Operator** - CRD controller

Installation takes approximately 15-30 minutes.

## Post-Installation

### Access Your Platform

After installation, access services at:

- **Dashboard**: https://dashboard.siab.local:PORT
- **Keycloak**: https://keycloak.siab.local:PORT
- **MinIO**: https://minio.siab.local:PORT

Find the NodePort with:

```bash
kubectl get svc -n istio-system istio-ingress
```

### Retrieve Credentials

```bash
sudo cat /etc/siab/credentials.env
```

### Verify Installation

```bash
kubectl get nodes
kubectl get pods -A
kubectl get siabapplications
```

## Deploy Your First Application

Create a file `my-app.yaml`:

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: hello-world
  namespace: default
spec:
  image: nginx:1.25-alpine
  replicas: 2
  port: 80

  security:
    scanOnDeploy: true

  ingress:
    enabled: true
    hostname: hello.siab.local
    tls: true
```

Deploy it:

```bash
kubectl apply -f my-app.yaml
```

Check status:

```bash
kubectl get siabapplications
kubectl describe siabapplication hello-world
```

## Next Steps

- [Configuration Guide](./configuration.md)
- [Security Best Practices](./security.md)
- [Application Deployment](./deployment.md)
- [Monitoring & Observability](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)

## Getting Help

- Check logs: `/var/log/siab/install.log`
- Platform status: `kubectl get pods -A`
- Report issues: https://github.com/morbidsteve/SIAB/issues
