# SIAB - Complete Documentation

> **Secure Infrastructure as a Box** - Production-ready Kubernetes platform in minutes

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Installation](#installation)
4. [Security Guide](#security-guide)
5. [Application Deployment](#application-deployment)
6. [Advanced Configuration](#advanced-configuration)
7. [Bare Metal Provisioning](#bare-metal-provisioning)
8. [Troubleshooting](#troubleshooting)
9. [API Reference](#api-reference)
10. [FAQ](#faq)

---

# Overview

## What is SIAB?

**SIAB (Secure Infrastructure as a Box)** is a one-command installer that deploys a complete, production-ready Kubernetes platform with enterprise-grade security, service mesh, identity management, and monitoring.

###Features at a Glance

| Category | Features |
|----------|----------|
| **Security** | HTTPS-only, mTLS, RBAC, OIDC, SELinux, Vulnerability Scanning |
| **Platform** | RKE2 Kubernetes, Istio Service Mesh, MetalLB Load Balancer |
| **Storage** | Longhorn (Block), MinIO (Object), NFS Support |
| **Identity** | Keycloak IAM with OIDC/SAML |
| **Monitoring** | Prometheus, Grafana, Alertmanager |
| **Policy** | OPA Gatekeeper, Network Policies, Pod Security |

### Architecture

```
┌──────────────────────────────────────────────────────┐
│              External Users/Clients                   │
└──────────────────────────────────────────────────────┘
                       │
                       │ HTTPS Only (HTTP → HTTPS redirect)
                       ▼
┌──────────────────────────────────────────────────────┐
│          Istio Ingress Gateways (MetalLB)            │
│  ┌──────────────┐          ┌──────────────┐         │
│  │ Admin Gateway│          │ User Gateway │         │
│  │ 10.10.30.240 │          │ 10.10.30.242 │         │
│  └──────────────┘          └──────────────┘         │
└──────────────────────────────────────────────────────┘
                       │
                       │ mTLS (Istio Service Mesh)
                       ▼
┌──────────────────────────────────────────────────────┐
│                Kubernetes Workloads                   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │Keycloak  │ │  MinIO   │ │   Your   │            │
│  │   IAM    │ │ Storage  │ │   Apps   │            │
│  └──────────┘ └──────────┘ └──────────┘            │
│                                                       │
│  Security: Trivy Scanner + OPA Gatekeeper            │
│  Monitoring: Prometheus + Grafana                    │
└──────────────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│              Persistent Storage                       │
│  Longhorn (Block) │ MinIO (Object) │ NFS (Optional) │
└──────────────────────────────────────────────────────┘
```

### Components

| Component | Version | Purpose |
|-----------|---------|---------|
| RKE2 | v1.28+ | CIS-hardened Kubernetes |
| Istio | 1.20+ | Service mesh, mTLS, traffic management |
| Keycloak | 23+ | Identity and access management |
| MinIO | Latest | S3-compatible object storage |
| Longhorn | 1.5+ | Distributed block storage |
| Trivy | Latest | Container vulnerability scanning |
| OPA Gatekeeper | 3.14+ | Policy enforcement |
| Prometheus Stack | 56+ | Monitoring and alerting |
| MetalLB | Latest | Load balancer for bare metal |
| cert-manager | 1.13+ | Automatic certificate management |

---

# Quick Start

## One-Command Installation

```bash
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

Or clone and install:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./install.sh
```

**Installation Time:** 15-20 minutes
**Requirements:** Rocky Linux 8/9, 4 cores, 16GB RAM, 30GB disk

## System Requirements

### Supported Operating Systems

**RHEL Family (Recommended):**
- ✅ Rocky Linux 8.x, 9.x
- ✅ Oracle Linux 8.x, 9.x
- ✅ AlmaLinux 8.x, 9.x
- ✅ RHEL 8.x, 9.x

**Debian Family:**
- ✅ Ubuntu 20.04, 22.04, 24.04 LTS
- ✅ Debian 11, 12

### Hardware Requirements

| Environment | Cores | RAM | Disk |
|-------------|-------|-----|------|
| **Development** | 4 | 16GB | 30GB |
| **Production** | 8+ | 32GB+ | 100GB+ SSD |
| **Cluster** | 12+ | 64GB+ | 200GB+ SSD |

### Network Requirements

- Static IP or DHCP reservation
- Internet connectivity for installation
- Firewall ports (configured automatically):
  - 80, 443 (HTTP/HTTPS)
  - 6443 (Kubernetes API)
  - 2379-2380 (etcd)
  - 8472, 4789 (CNI VXLAN)
  - 15010-15017 (Istio control plane)

## Post-Installation Access

After installation, access services at:

| Service | URL | Purpose |
|---------|-----|---------|
| **Keycloak** | https://keycloak.siab.local | Identity Management |
| **MinIO** | https://minio.siab.local | Object Storage Console |
| **Grafana** | https://grafana.siab.local | Monitoring Dashboards |
| **Longhorn** | https://longhorn.siab.local | Storage Management |
| **K8s Dashboard** | https://k8s-dashboard.siab.local | Kubernetes UI |
| **App Catalog** | https://catalog.siab.local | Application Deployment |

### Configure DNS/Hosts

Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
10.10.30.240  keycloak.siab.local minio.siab.local grafana.siab.local longhorn.siab.local k8s-dashboard.siab.local
10.10.30.242  catalog.siab.local dashboard.siab.local
```

---

# Installation

## Pre-Installation Checklist

- [ ] Supported OS installed (Rocky Linux 8/9 recommended)
- [ ] Minimum hardware requirements met
- [ ] Static IP configured or DHCP reservation set
- [ ] Internet connectivity available
- [ ] Root or sudo access
- [ ] No conflicting Kubernetes installations

## Installation Steps

### Step 1: Download SIAB

```bash
# Clone repository
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
```

### Step 2: Configure Installation (Optional)

Set environment variables before installation:

```bash
# Custom domain (default: siab.local)
export SIAB_DOMAIN="mycompany.local"

# Admin email
export SIAB_ADMIN_EMAIL="admin@mycompany.local"

# Skip monitoring (saves resources)
export SIAB_SKIP_MONITORING=false

# Single-node mode
export SIAB_SINGLE_NODE=true

# MinIO storage size
export SIAB_MINIO_SIZE="20Gi"
```

### Step 3: Run Installer

```bash
sudo ./install.sh
```

The installer will:
1. Check system requirements
2. Install system dependencies
3. Configure firewall (firewalld/ufw)
4. Install RKE2 Kubernetes
5. Deploy Istio service mesh
6. Install storage providers (Longhorn, MinIO)
7. Deploy Keycloak IAM
8. Configure monitoring (Prometheus/Grafana)
9. Set up security policies
10. Create ingress gateways

### Step 4: Verify Installation

```bash
# Check overall status
./siab-status.sh

# Verify all pods are running
kubectl get pods -A

# Check ingress gateways
kubectl get svc -n istio-system | grep ingress

# Test HTTPS access
./scripts/test-https-access.sh
```

## What Gets Installed

### Infrastructure Layer
- **RKE2** - CIS-hardened Kubernetes
- **Firewalld/UFW** - Configured with CNI-aware rules
- **SELinux** - Enforcing mode

### Networking Layer
- **Istio** - Service mesh with automatic mTLS
- **MetalLB** - Load balancer IP pool
- **Canal (Calico + Flannel)** - CNI networking

### Storage Layer
- **Longhorn** - Distributed block storage
- **MinIO** - S3-compatible object storage
- **cert-manager** - Automatic TLS certificates

### Security Layer
- **Keycloak** - Identity and access management
- **Trivy Operator** - Continuous vulnerability scanning
- **OPA Gatekeeper** - Policy enforcement
- **NetworkPolicies** - Pod-to-pod traffic control

### Monitoring Layer
- **Prometheus** - Metrics collection
- **Grafana** - Visualization and dashboards
- **Alertmanager** - Alert routing

### Management Layer
- **Kubernetes Dashboard** - Web-based cluster management
- **k9s** - Terminal-based cluster UI

---

# Security Guide

## Security Architecture

SIAB implements defense-in-depth security across four layers:

```
┌────────────────────────────────────────────────┐
│ APPLICATION LAYER                              │
│ • Container Scanning (Trivy)                   │
│ • Image Signature Verification                 │
│ • Application-level Authentication (Keycloak)  │
├────────────────────────────────────────────────┤
│ NETWORK LAYER                                  │
│ • mTLS Everywhere (Istio)                      │
│ • Network Policies (Calico)                    │
│ • HTTPS-Only External Access                   │
├────────────────────────────────────────────────┤
│ PLATFORM LAYER                                 │
│ • Policy Enforcement (OPA Gatekeeper)          │
│ • Pod Security Standards                       │
│ • RBAC + OIDC Integration                      │
│ • Audit Logging                                │
├────────────────────────────────────────────────┤
│ INFRASTRUCTURE LAYER                           │
│ • CIS Hardened Kubernetes (RKE2)               │
│ • SELinux Enforcing                            │
│ • Firewalld CNI-Aware Rules                    │
│ • Encrypted Secrets at Rest                    │
└────────────────────────────────────────────────┘
```

## HTTPS-Only Access

### Automatic HTTP to HTTPS Redirects

All external services automatically redirect HTTP to HTTPS:

```yaml
# Gateway configuration (automatically applied)
servers:
- port:
    number: 443
    name: https
    protocol: HTTPS
  tls:
    mode: SIMPLE
    credentialName: siab-gateway-cert
  hosts:
  - "*.siab.local"
- port:
    number: 80
    name: http
    protocol: HTTP
  tls:
    httpsRedirect: true  # Automatic redirect
  hosts:
  - "*.siab.local"
```

### Test HTTPS Configuration

```bash
# Verify HTTP redirects
curl -I http://keycloak.siab.local
# Expected: HTTP/1.1 301 Moved Permanently
# location: https://keycloak.siab.local/

# Test HTTPS access
curl -k -I https://keycloak.siab.local
# Expected: HTTP/1.1 200 OK

# Run complete test suite
./scripts/test-https-access.sh
```

## Firewall Configuration

### Why Firewalld Configuration is Critical

⚠️ **IMPORTANT**: By default, firewalld blocks pod-to-pod traffic, causing "No route to host" errors. SIAB configures firewalld properly during installation.

### Automated Configuration

The installer automatically configures firewalld with:

1. **CNI interfaces in trusted zone**:
   - cni0 (Container Network Interface)
   - flannel.1 (Flannel VXLAN)
   - tunl0 (Calico IPIP tunnel)

2. **Pod/Service CIDRs as trusted**:
   - 10.42.0.0/16 (Pod CIDR)
   - 10.43.0.0/16 (Service CIDR)

3. **Required ports opened**:
   - Kubernetes: 6443, 9345, 10250, 2379-2380
   - NodePort range: 30000-32767
   - Canal: 8472, 4789, 51820-51821, 179, 5473
   - Istio: 80, 443, 15010-15017, 15021, 15090

4. **Masquerading enabled** for container networking

### Manual Configuration

If needed, run the firewalld configuration script:

```bash
sudo ./scripts/configure-firewalld.sh
```

## Mutual TLS (mTLS)

### Service-to-Service Encryption

All communication within the Istio service mesh uses mutual TLS:

```yaml
# Strict mTLS for internal services
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT

# Permissive mTLS for ingress gateways (accepts external HTTP/HTTPS)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: ingress-admin-mtls
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-admin
  mtls:
    mode: PERMISSIVE
```

### Verify mTLS

```bash
# Check PeerAuthentication policies
kubectl get peerauthentication -A

# Verify pod has Istio sidecar
kubectl get pods -n my-namespace my-pod -o jsonpath='{.spec.containers[*].name}'
# Should show: my-app istio-proxy
```

## Identity and Access Management

### Keycloak Configuration

Access Keycloak admin console: https://keycloak.siab.local

**Default credentials** are generated during installation and stored in:
```bash
cat ~/.siab-credentials.env
```

### Create Application Client

1. Login to Keycloak admin console
2. Navigate to: Clients → Create
3. Configure:
   - Client ID: `my-app`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `https://my-app.apps.siab.local/*`
4. Save and copy Client Secret

### Integrate with Application

Configure your app to use OIDC:

```yaml
env:
- name: OAUTH2_CLIENT_ID
  value: "my-app"
- name: OAUTH2_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: oidc-secret
      key: client-secret
- name: OAUTH2_ISSUER_URL
  value: "https://keycloak.siab.local/realms/siab"
```

## Vulnerability Scanning

### Trivy Operator

Automatically scans all container images for CVEs:

```bash
# View vulnerability reports
kubectl get vulnerabilityreports -A

# Check specific image
kubectl get vulnerabilityreport -n my-namespace

# View detailed report
kubectl describe vulnerabilityreport my-app-xxxxx -n my-namespace
```

### Policy Enforcement

OPA Gatekeeper enforces security policies:

```bash
# View constraints
kubectl get constraints

# Check denied requests
kubectl get events --field-selector reason=FailedCreate
```

## Production Security Checklist

Before deploying to production:

- [ ] Replace self-signed certificates with trusted CA (Let's Encrypt)
- [ ] Configure external authentication (LDAP/SAML) in Keycloak
- [ ] Enable MFA for all administrative accounts
- [ ] Review and customize network policies
- [ ] Set up vulnerability scanning alerts
- [ ] Configure backup and disaster recovery
- [ ] Enable audit logging
- [ ] Review and tune OPA policies
- [ ] Perform security audit
- [ ] Document security procedures
- [ ] Set up monitoring and alerting for security events

---

# Application Deployment

## Deployment Methods

### Method 1: kubectl (Basic)

```bash
kubectl apply -f my-app.yaml
```

### Method 2: Helm Charts (Recommended)

```bash
helm install my-app ./chart -n my-namespace
```

### Method 3: SIAB Catalog (Easiest)

Access: https://catalog.siab.local

Click to deploy: PostgreSQL, Redis, NGINX, RabbitMQ, Vault, etc.

## Example: Deploy a Web Application

### Step 1: Create Namespace with Istio Injection

```bash
kubectl create namespace web-app
kubectl label namespace web-app istio-injection=enabled
```

### Step 2: Create Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-app
  namespace: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-app
  template:
    metadata:
      labels:
        app: nginx-app
        version: v1
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        fsGroup: 101
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ALL]
            add: [NET_BIND_SERVICE]
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

Apply:
```bash
kubectl apply -f deployment.yaml
```

### Step 3: Create Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-app
  namespace: web-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    name: http
  selector:
    app: nginx-app
```

Apply:
```bash
kubectl apply -f service.yaml
```

### Step 4: Create VirtualService for External Access

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: nginx-app
  namespace: istio-system
spec:
  hosts:
  - "nginx.apps.siab.local"
  gateways:
  - user-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: nginx-app.web-app.svc.cluster.local
        port:
          number: 80
```

Apply:
```bash
kubectl apply -f virtualservice.yaml
```

### Step 5: Configure DNS/Hosts

```bash
# Add to /etc/hosts
echo "10.10.30.242  nginx.apps.siab.local" | sudo tee -a /etc/hosts
```

### Step 6: Access Your Application

```bash
# Test HTTP redirect
curl -I http://nginx.apps.siab.local
# Expected: HTTP/1.1 301 Moved Permanently

# Access via HTTPS
curl -k https://nginx.apps.siab.local
```

## Example: Deploy a Database

### Step 1: Create Namespace

```bash
kubectl create namespace database
kubectl label namespace database istio-injection=enabled
```

### Step 2: Create PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: database
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

### Step 3: Create Secret

```bash
kubectl create secret generic postgres-secret \
  --from-literal=postgres-password=SecurePassword123! \
  -n database
```

### Step 4: Deploy PostgreSQL

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: database
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: postgres-pvc
```

### Step 5: Disable mTLS for Database

Databases don't typically have Istio sidecars:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgres-mtls-disable
  namespace: istio-system
spec:
  host: postgres.database.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
```

---

# Advanced Configuration

## Firewalld Advanced Topics

See full guide: [docs/FIREWALLD-CONFIGURATION.md](docs/FIREWALLD-CONFIGURATION.md)

### Custom Rules

```bash
# Add custom port
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Add custom service
sudo firewall-cmd --permanent --add-service=mysql
sudo firewall-cmd --reload
```

## HTTPS and TLS Configuration

See full guide: [docs/HTTPS-CONFIGURATION.md](docs/HTTPS-CONFIGURATION.md)

### Production Certificates (Let's Encrypt)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
```

---

# Bare Metal Provisioning

See full guide: [docs/bare-metal-provisioning.md](docs/bare-metal-provisioning.md)

## PXE Boot Method

```bash
# Set up PXE server
sudo ./provisioning/pxe/setup-pxe-server.sh

# Boot target machines via network boot
# They will auto-install Rocky Linux + SIAB
```

## MAAS Method

```bash
# Set up MAAS (Ubuntu required)
sudo ./provisioning/maas/setup-maas.sh

# Deploy cluster
./provisioning/scripts/provision-cluster.sh --method maas --nodes 3
```

---

# Troubleshooting

## Common Issues

### Issue: Cannot Access Services

**Symptoms:** Unable to access https://keycloak.siab.local or other services

**Diagnosis:**
```bash
# Check firewalld status
sudo firewall-cmd --state

# Check pod connectivity
kubectl exec -n istio-system deployment/istio-ingress-admin -- \
  nc -zv keycloak.keycloak.svc.cluster.local 80
```

**Solution:**
```bash
# Reconfigure firewalld
sudo ./scripts/configure-firewalld.sh

# Restart ingress gateways
kubectl rollout restart deployment/istio-ingress-admin -n istio-system
kubectl rollout restart deployment/istio-ingress-user -n istio-system
```

### Issue: HTTP Not Redirecting to HTTPS

**Diagnosis:**
```bash
curl -I http://keycloak.siab.local
# Should return 301, not 503 or 404
```

**Solution:**
```bash
# Reapply gateway manifests
kubectl apply -f manifests/istio/gateways.yaml

# Verify configuration
kubectl get gateway admin-gateway -n istio-system -o yaml | grep httpsRedirect
```

### Issue: Pod-to-Pod Connectivity Failure

**Error:** `delayed connect error: 113 (No route to host)`

**Cause:** Firewalld blocking CNI traffic

**Solution:**
```bash
# Option 1: Reconfigure firewalld properly
sudo ./scripts/configure-firewalld.sh

# Option 2: Temporarily disable to test
sudo systemctl stop firewalld
# Test connectivity
# Then re-enable and configure properly
sudo systemctl start firewalld
sudo ./scripts/configure-firewalld.sh
```

### Issue: Certificate Warnings in Browser

**Expected Behavior:** Self-signed certificates show security warnings

**Solution for Development:**
- Click "Advanced" → "Proceed to site"

**Solution for Production:**
- Configure Let's Encrypt or use commercial CA
- See [Advanced Configuration](#https-and-tls-configuration)

## Diagnostic Tools

```bash
# Overall status
./siab-status.sh

# Detailed diagnostics
./siab-diagnose.sh

# Upstream connection errors
./diagnose-upstream-errors.sh

# HTTPS testing
./scripts/test-https-access.sh

# Check specific service
kubectl logs -n namespace pod-name --tail=100
```

---

# API Reference

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SIAB_DOMAIN` | `siab.local` | Base domain for services |
| `SIAB_ADMIN_EMAIL` | `admin@siab.local` | Administrator email |
| `SIAB_SKIP_MONITORING` | `false` | Skip Prometheus/Grafana |
| `SIAB_SKIP_STORAGE` | `false` | Skip MinIO |
| `SIAB_SKIP_LONGHORN` | `false` | Skip Longhorn |
| `SIAB_MINIO_SIZE` | `20Gi` | MinIO storage size |
| `SIAB_SINGLE_NODE` | `true` | Single-node mode |

## Management Scripts

| Script | Purpose |
|--------|---------|
| `install.sh` | Main installer |
| `uninstall.sh` | Remove SIAB |
| `siab-status.sh` | Check status |
| `siab-diagnose.sh` | Run diagnostics |
| `siab-info.sh` | Show system info |
| `scripts/configure-firewalld.sh` | Configure firewall |
| `scripts/test-https-access.sh` | Test HTTPS |

---

# FAQ

## General Questions

**Q: What is SIAB?**
A: A one-command installer for a production-ready, security-hardened Kubernetes platform with integrated service mesh, IAM, storage, and monitoring.

**Q: What operating systems are supported?**
A: Rocky Linux 8/9 (recommended), RHEL 8/9, AlmaLinux 8/9, Ubuntu 20.04/22.04/24.04 LTS, Debian 11/12.

**Q: How long does installation take?**
A: 15-20 minutes on recommended hardware with good internet connection.

**Q: Can I use SIAB in production?**
A: Yes! Follow the production security checklist and configure proper TLS certificates.

## Security Questions

**Q: Why am I getting certificate warnings?**
A: SIAB uses self-signed certificates by default. For production, configure Let's Encrypt or use commercial certificates.

**Q: Is firewalld required?**
A: No, but recommended for production. If enabled, it must be configured properly to allow CNI traffic.

**Q: What is mTLS and why is it important?**
A: Mutual TLS encrypts all service-to-service communication within the mesh, providing zero-trust networking.

## Technical Questions

**Q: Can I change the domain from siab.local?**
A: Yes, set `SIAB_DOMAIN` environment variable before installation.

**Q: How do I add more nodes to the cluster?**
A: Install RKE2 on additional nodes and join them to the cluster. See RKE2 documentation for details.

**Q: Can I disable monitoring to save resources?**
A: Yes, set `SIAB_SKIP_MONITORING=true` before installation.

**Q: How do I upgrade SIAB components?**
A: Currently manual. Use `helm upgrade` for Helm-installed components. Automated upgrades coming soon.

---

**Documentation Version:** 1.0.0
**Last Updated:** 2025-11-28
**GitHub:** https://github.com/morbidsteve/SIAB

---

*Built with ❤️ for the Kubernetes community*
