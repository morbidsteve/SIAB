# SIAB - Secure Infrastructure as a Box

A one-command secure Kubernetes platform installer for Rocky Linux with RKE2. Deploy a production-ready, security-hardened Kubernetes environment with integrated IAM, storage, service mesh, container scanning, and policy enforcement.

## 🚀 New to SIAB? Start Here!

**Not sure which OS you need or where to begin?**

→ **[📖 Where Can I Start From? (Windows/Mac/Linux Guide)](./docs/where-to-start.md)** ←

This guide explains:
- ✅ What you can do from Windows, macOS, or Linux
- ✅ Which parts require which operating systems
- ✅ Common deployment scenarios with examples
- ✅ Quick start decision tree

**TL;DR:** You can **control** SIAB from **any OS** (Windows/Mac/Linux), but it **runs on** Rocky Linux.

**[⚡ Quick Start Guide](./QUICK-START.md)** - Get running in 10 minutes!

## Features

### Platform Capabilities
- **One-Command Install**: Deploy entire platform with a single command
- **Bare Metal Provisioning**: Automated OS installation and SIAB deployment on unprovisioned hardware
- **RKE2 Hardened Kubernetes**: FIPS-compliant, CIS hardened Kubernetes distribution
- **Keycloak IAM**: Enterprise identity and access management with OIDC/SAML
- **Istio Service Mesh**: mTLS, traffic management, ingress/egress control
- **MinIO Object Storage**: S3-compatible distributed storage
- **Trivy Security Scanning**: Continuous vulnerability scanning for containers
- **OPA Gatekeeper**: Policy-as-code enforcement
- **Custom Resource Definitions**: Easy application deployment with `SIABApplication` CRD
- **Landing Dashboard**: Centralized portal for platform access

### Bare Metal Provisioning
- **GUI Provisioner**: Cross-platform graphical interface (double-click to run!)
- **MAAS Integration**: Enterprise-grade Metal as a Service support
- **PXE Boot**: Lightweight network installation server
- **Hardware Discovery**: Automatic detection of IPMI/BMC interfaces
- **Kickstart Automation**: Unattended Rocky Linux installation
- **Cloud-Init Support**: Post-installation configuration automation
- **Cluster Deployment**: Multi-node cluster provisioning from bare metal

### Application Catalog
- **Web-Based Catalog**: Browse and deploy apps via beautiful web UI
- **One-Click Deployment**: Deploy databases, monitoring, CI/CD tools with one click
- **Pre-Configured Apps**: PostgreSQL, Redis, Prometheus, Grafana, NGINX, RabbitMQ, Vault, and more
- **Security Integrated**: All apps include vulnerability scanning and security policies
- **Organized Categories**: Databases, Monitoring, CI/CD, Messaging, Web Servers, Development, Security
- **Deployment Tracking**: See what's deployed and manage from the UI

## Quick Start

### Option 1: Install on Existing Rocky Linux

```bash
# One-command install
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

Or clone and install:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./install.sh
```

### Option 2: Deploy on Bare Metal (Unprovisioned Hardware)

SIAB can automatically provision bare metal servers from scratch:

**Using GUI (Easiest):**
```bash
cd SIAB/gui
./SIAB-Provisioner.sh  # Linux/macOS
# or
SIAB-Provisioner.bat   # Windows
```

**Using MAAS (Enterprise):**
```bash
# On Ubuntu server, set up MAAS provisioning
sudo ./provisioning/maas/setup-maas.sh

# Deploy 3-node cluster
./provisioning/scripts/provision-cluster.sh --method maas --nodes 3
```

**Using PXE (Lightweight):**
```bash
# On Rocky Linux server, set up PXE server
sudo ./provisioning/pxe/setup-pxe-server.sh

# Boot target machines via PXE (they auto-install Rocky + SIAB)
```

**📋 [See detailed OS requirements and scenarios](./docs/where-to-start.md)**

See [Bare Metal Provisioning Guide](./docs/bare-metal-provisioning.md) and [GUI Guide](./docs/gui-provisioner.md) for details.

### Option 3: Deploy Pre-Configured Applications

After SIAB is installed, deploy popular applications with one click:

```bash
# Deploy application catalog
kubectl apply -f catalog/catalog-deployment.yaml

# Access web interface
open https://catalog.siab.local
```

Browse and deploy apps like PostgreSQL, Redis, Grafana, NGINX, and more with a single click!

## Requirements

**Supported Operating Systems:**

RHEL-based:
- Rocky Linux 8.x or 9.x
- Oracle Linux 8.x or 9.x
- AlmaLinux 8.x or 9.x
- RHEL 8.x or 9.x
- CentOS 8.x or 9.x (Stream)

Debian-based:
- Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Xubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Debian 11 (Bullseye) or 12 (Bookworm)

**Hardware Requirements:**
- Minimum 4 CPU cores
- Minimum 16GB RAM
- Minimum 100GB disk space
- Root or sudo access
- Internet connectivity

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SIAB Platform                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐      │
│  │ Landing │  │Keycloak │  │  MinIO  │  │   Your   │      │
│  │  Page   │  │   IAM   │  │ Storage │  │   Apps   │      │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬─────┘      │
│       │            │            │             │            │
├───────┴────────────┴────────────┴─────────────┴────────────┤
│                    Istio Service Mesh                       │
│              (mTLS, Traffic Management, Policies)           │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐      │
│  │  Trivy  │  │   OPA   │  │  Cert   │  │ External │      │
│  │ Scanner │  │Gatekeeper│  │ Manager │  │ Secrets  │      │
│  └─────────┘  └─────────┘  └─────────┘  └──────────┘      │
├─────────────────────────────────────────────────────────────┤
│                    RKE2 Kubernetes                          │
│              (CIS Hardened, FIPS Compliant)                 │
├─────────────────────────────────────────────────────────────┤
│                    Rocky Linux                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Core Infrastructure
- **RKE2**: Rancher's hardened Kubernetes distribution
- **Istio**: Service mesh with mTLS and traffic management
- **Cert-Manager**: Automated TLS certificate management

### Security
- **Keycloak**: Identity and access management
- **Trivy Operator**: Continuous vulnerability scanning
- **OPA Gatekeeper**: Policy enforcement
- **Falco**: Runtime security monitoring
- **Network Policies**: Zero-trust network segmentation

### Storage & Data
- **MinIO**: S3-compatible object storage
- **Longhorn**: Distributed block storage
- **External Secrets Operator**: Secure secrets management

### Observability
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Jaeger**: Distributed tracing

## Custom Resource Definitions

Deploy applications easily using the `SIABApplication` CRD:

```yaml
apiVersion: siab.io/v1alpha1
kind: SIABApplication
metadata:
  name: my-app
  namespace: default
spec:
  image: myregistry/myapp:latest
  replicas: 3
  port: 8080

  # Automatic security scanning
  security:
    scanOnDeploy: true
    blockCriticalVulns: true

  # Automatic IAM integration
  auth:
    enabled: true
    requiredRoles:
      - user

  # Storage integration
  storage:
    enabled: true
    size: 10Gi

  # Ingress configuration
  ingress:
    enabled: true
    hostname: myapp.example.com
    tls: true
```

## Post-Installation

After installation completes:

1. **Access Landing Page**: https://siab.local
2. **Keycloak Admin**: https://keycloak.siab.local
3. **MinIO Console**: https://minio.siab.local
4. **Grafana Dashboard**: https://grafana.siab.local

Default admin credentials are generated during installation and stored in:
```
/etc/siab/credentials.env
```

## Security Features

- **Pod Security Standards**: Enforced restricted profile
- **Network Policies**: Default deny-all with explicit allow rules
- **mTLS Everywhere**: All service-to-service communication encrypted
- **RBAC**: Role-based access control integrated with Keycloak
- **Audit Logging**: Comprehensive audit trail
- **Image Signing**: Cosign integration for supply chain security
- **Runtime Protection**: Falco for threat detection

## Configuration

Customize installation via environment variables:

```bash
# Custom domain
export SIAB_DOMAIN="mycompany.com"

# Skip certain components
export SIAB_SKIP_MONITORING="false"

# Custom storage size
export SIAB_MINIO_SIZE="500Gi"

sudo ./install.sh
```

See `docs/configuration.md` for all options.

## Deploying Applications

### Using the CRD (Recommended)

```bash
kubectl apply -f my-siab-app.yaml
```

### Using Helm

```bash
helm install myapp siab/application \
  --set image=myapp:latest \
  --set replicas=3
```

## Uninstallation

```bash
sudo ./uninstall.sh
```

## Documentation

- [Getting Started](./docs/getting-started.md) - Installation and first deployment
- [Bare Metal Provisioning](./docs/bare-metal-provisioning.md) - Deploy on unprovisioned hardware
- [GUI Provisioner](./docs/gui-provisioner.md) - Using the graphical interface
- [Application Catalog](./catalog/README.md) - One-click app deployment
- [Configuration Guide](./docs/configuration.md) - Customize your installation
- [Application Deployment](./docs/deployment.md) - Deploy apps with CRDs
- [Security Guide](./docs/security.md) - Security architecture and best practices

## Use Cases

### Datacenter Deployment
Deploy SIAB across your datacenter using MAAS:
1. Set up MAAS server
2. Add bare metal servers via IPMI
3. Deploy multi-node Kubernetes cluster
4. Automatic OS installation and SIAB setup

### Edge Computing
Deploy secure Kubernetes at edge locations:
1. Ship preconfigured hardware
2. PXE boot from central server
3. Zero-touch provisioning
4. Automatic security hardening

### Development Clusters
Quickly provision dev/test environments:
1. Point at available hardware
2. Automated Rocky Linux installation
3. SIAB platform ready in 30 minutes
4. Tear down and rebuild easily

## Support

- Documentation: [docs/](./docs/)
- Issues: [GitHub Issues](https://github.com/morbidsteve/SIAB/issues)

## License

Apache License 2.0
