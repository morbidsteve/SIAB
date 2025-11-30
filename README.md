# SIAB - Secure Infrastructure as a Box

**One-command secure Kubernetes platform for Rocky Linux**

Deploy a production-ready, security-hardened Kubernetes environment with integrated IAM, storage, service mesh, container scanning, and policy enforcement in minutes.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![RKE2](https://img.shields.io/badge/K8s-RKE2-326CE5)](https://docs.rke2.io/)
[![Istio](https://img.shields.io/badge/Service%20Mesh-Istio-466BB0)](https://istio.io/)

## 🚀 Quick Start

### One-Command Install

```bash
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | sudo bash
```

Or clone and install:

```bash
git clone https://github.com/morbidsteve/SIAB.git
cd SIAB
sudo ./install.sh
```

**Installation time:** 15-20 minutes
**Requirements:** Rocky Linux 8/9, 4 CPU cores, 16GB RAM, 30GB disk

👉 **[Full Getting Started Guide](./docs/GETTING-STARTED.md)**

## 📋 What You Get

After installation, you'll have a complete secure platform with:

| Component | Purpose | Access URL |
|-----------|---------|------------|
| **Keycloak** | Identity & Access Management | https://keycloak.siab.local |
| **MinIO** | S3-Compatible Object Storage | https://minio.siab.local |
| **Grafana** | Monitoring & Dashboards | https://grafana.siab.local |
| **Longhorn** | Distributed Block Storage | https://longhorn.siab.local |
| **K8s Dashboard** | Kubernetes Management | https://k8s-dashboard.siab.local |
| **App Catalog** | One-Click App Deployment | https://catalog.siab.local |

**🔒 All services enforce HTTPS** with automatic HTTP→HTTPS redirects

## ✨ Key Features

### Security First
- ✅ **HTTPS-Only Access** - Automatic HTTP to HTTPS redirects
- ✅ **Mutual TLS (mTLS)** - Service-to-service encryption via Istio
- ✅ **Firewalld Compatible** - Proper CNI-aware firewall rules
- ✅ **SELinux Enforcing** - Mandatory access control enabled
- ✅ **Vulnerability Scanning** - Continuous container scanning with Trivy
- ✅ **Policy Enforcement** - OPA Gatekeeper for compliance
- ✅ **RBAC + OIDC** - Keycloak enterprise IAM

### Platform Capabilities
- ✅ **RKE2 Kubernetes** - FIPS-compliant, CIS-hardened distribution
- ✅ **Istio Service Mesh** - Traffic management, observability
- ✅ **Distributed Storage** - Longhorn block + MinIO object storage
- ✅ **Monitoring Stack** - Prometheus, Grafana, Alertmanager
- ✅ **Application Catalog** - Pre-configured apps (PostgreSQL, Redis, NGINX, etc.)
- ✅ **Bare Metal Provisioning** - PXE/MAAS integration for automated deployment

## 📚 Documentation

### Getting Started
- **[Getting Started Guide](./docs/GETTING-STARTED.md)** - Installation, first steps, verification
- **[Application Deployment Guide](./docs/APPLICATION-DEPLOYMENT-GUIDE.md)** - Deploy your first app with examples
- **[Application Deployer](./docs/APPLICATION-DEPLOYER.md)** - Using the web-based app deployer
- **[Security Guide](./SECURITY.md)** - Security features, best practices, hardening

### Advanced Topics
- **[HTTPS Configuration](./docs/HTTPS-CONFIGURATION.md)** - TLS certificates and HTTPS setup
- **[Firewalld Configuration](./docs/FIREWALLD-CONFIGURATION.md)** - Firewall rules and CNI integration
- **[Bare Metal Provisioning](./docs/bare-metal-provisioning.md)** - PXE/MAAS automated deployment
- **[Improvements Roadmap](./docs/IMPROVEMENTS.md)** - Planned enhancements

### Quick References
- **[Architecture Overview](#architecture)** - System architecture and components
- **[Requirements](#requirements)** - Hardware, software, network requirements
- **[Security Features](./SECURITY.md)** - Security features overview

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    External Clients                         │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS (443) - HTTP redirected
                          ▼
┌─────────────────────────────────────────────────────────────┐
│               Istio Ingress Gateways (MetalLB)              │
│  ┌─────────────────────┐    ┌─────────────────────┐        │
│  │  Admin Gateway      │    │  User Gateway       │        │
│  │  (Admin Services)   │    │  (Applications)     │        │
│  └─────────────────────┘    └─────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ mTLS (Istio Service Mesh)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Workloads                       │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐          │
│  │ Keycloak   │  │   MinIO    │  │    Your    │          │
│  │    IAM     │  │  Storage   │  │    Apps    │          │
│  └────────────┘  └────────────┘  └────────────┘          │
│                                                             │
│  Policy Enforcement: OPA Gatekeeper                        │
│  Vulnerability Scanning: Trivy Operator                    │
│  Monitoring: Prometheus + Grafana                          │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Storage Layer                                  │
│  Longhorn (Block)  |  MinIO (Object)  |  NFS (Optional)    │
└─────────────────────────────────────────────────────────────┘
```

### Security Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Application   │ Container Scanning, Image Signing          │
├─────────────────────────────────────────────────────────────┤
│ Network       │ mTLS Everywhere, Network Policies          │
├─────────────────────────────────────────────────────────────┤
│ Platform      │ OPA Policies, Pod Security, RBAC           │
├─────────────────────────────────────────────────────────────┤
│ Infrastructure│ RKE2 CIS Hardened, SELinux, Firewalld      │
└─────────────────────────────────────────────────────────────┘
```

## 💻 Requirements

### Supported Operating Systems

**RHEL Family (Recommended):**
- Rocky Linux 8.x or 9.x ⭐
- Oracle Linux 8.x or 9.x
- AlmaLinux 8.x or 9.x
- RHEL 8.x or 9.x

**Debian Family:**
- Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
- Debian 11 (Bullseye), 12 (Bookworm)

### Hardware Requirements

**Minimum (Development/Testing):**
- 4 CPU cores
- 16GB RAM
- 30GB disk space

**Recommended (Production):**
- 8+ CPU cores
- 32GB+ RAM
- 100GB+ SSD storage
- Dedicated network interface

**Cluster (Multi-Node):**
- 3+ nodes for high availability
- Shared storage or distributed storage backend

### Network Requirements

- Static IP address (or DHCP reservation)
- Internet connectivity for installation
- Firewall ports (configured automatically):
  - 80/443 (HTTP/HTTPS)
  - 6443 (Kubernetes API)
  - 2379-2380 (etcd)
  - 8472, 4789 (CNI VXLAN)

## 🎯 Use Cases

### Development & Testing
- Local Kubernetes development environment
- Application testing with production-like setup
- CI/CD pipeline testing

### Production Workloads
- Microservices platform
- Internal applications and APIs
- Data processing pipelines
- ML/AI model serving

### Edge Computing
- On-premise Kubernetes at edge locations
- Low-latency application hosting
- Data sovereignty requirements

### Learning & Training
- Kubernetes training environment
- Security best practices demonstration
- Service mesh learning

## 🛠️ Management Tools

### Command Line Tools

```bash
# Check overall status
./siab-status.sh

# Run diagnostics
./siab-diagnose.sh

# Test HTTPS configuration
./scripts/test-https-access.sh

# Configure firewalld
sudo ./scripts/configure-firewalld.sh

# Interactive cluster management
k9s
```

### Web Interfaces

Access via browser (add to /etc/hosts or configure DNS):

```
10.10.30.240  keycloak.siab.local minio.siab.local grafana.siab.local longhorn.siab.local k8s-dashboard.siab.local
10.10.30.242  catalog.siab.local dashboard.siab.local
```

All URLs use HTTPS with automatic HTTP redirects.

## 🔧 Configuration

### Environment Variables

Control installation behavior:

```bash
# Set custom domain (default: siab.local)
export SIAB_DOMAIN="mycompany.local"

# Skip monitoring stack
export SIAB_SKIP_MONITORING=true

# Single-node mode (default: true)
export SIAB_SINGLE_NODE=true

# Custom MinIO storage size
export SIAB_MINIO_SIZE="50Gi"
```

### Post-Installation Configuration

See [Advanced Configuration Guide](./docs/ADVANCED-CONFIGURATION.md) for:
- Custom firewall rules
- Production TLS certificates (Let's Encrypt)
- External authentication (LDAP/SAML)
- Storage configuration
- Network tuning

## 🚨 Troubleshooting

### Quick Checks

```bash
# System status
./siab-status.sh

# Check pods
kubectl get pods -A

# Check ingress gateways
kubectl get gateway -n istio-system

# View logs
kubectl logs -n istio-system -l istio=ingress-admin --tail=50
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Cannot access services | Check firewalld: `sudo ./scripts/configure-firewalld.sh` |
| HTTP not redirecting | Apply gateway manifests: `kubectl apply -f manifests/istio/gateways.yaml` |
| Pod connectivity issues | Verify CNI: `kubectl get pods -n kube-system` |
| Certificate warnings | Expected with self-signed certs (see [Advanced Config](./docs/ADVANCED-CONFIGURATION.md#tls-certificates)) |

👉 **[Full Troubleshooting Guide](./docs/TROUBLESHOOTING.md)**

## 🗑️ Uninstalling SIAB

To completely remove SIAB and return your system to its pre-installation state:

```bash
sudo ./uninstall.sh
```

**What gets removed:**
- RKE2 Kubernetes cluster and all workloads
- Istio service mesh
- All deployed applications and data
- Keycloak, MinIO, Longhorn, and all storage
- Monitoring stack (Prometheus, Grafana)
- Security components (Trivy, Gatekeeper)
- Installed binaries (kubectl, helm, k9s, istioctl)
- Firewall rules and configuration files

**⚠️ Warning:** This action is destructive and cannot be undone. All data will be permanently deleted.

**Optional backup:** The script will offer to back up configurations before removal.

**Non-interactive mode:**
```bash
SIAB_UNINSTALL_CONFIRM=yes sudo ./uninstall.sh
```

After uninstallation, a system reboot is recommended to ensure all changes take effect.

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

MIT License - see [LICENSE](./LICENSE) file for details.

## 🆘 Support

- **Documentation**: See [docs/](./docs/) directory
- **Issues**: https://github.com/morbidsteve/SIAB/issues
- **Discussions**: https://github.com/morbidsteve/SIAB/discussions

## 🙏 Acknowledgments

SIAB builds on excellent open-source projects:
- [RKE2](https://docs.rke2.io/) - Kubernetes distribution
- [Istio](https://istio.io/) - Service mesh
- [Keycloak](https://www.keycloak.org/) - Identity and access management
- [MinIO](https://min.io/) - Object storage
- [Longhorn](https://longhorn.io/) - Distributed block storage
- [Trivy](https://trivy.dev/) - Security scanner
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/) - Policy enforcement

## ⭐ Star History

If you find SIAB useful, please consider starring the repository!

---

**Built with ❤️ for the Kubernetes community**
