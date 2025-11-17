# SIAB - Secure Infrastructure as a Box

A one-command secure Kubernetes platform installer for Rocky Linux with RKE2. Deploy a production-ready, security-hardened Kubernetes environment with integrated IAM, storage, service mesh, container scanning, and policy enforcement.

## Features

- **One-Command Install**: Deploy entire platform with a single command
- **RKE2 Hardened Kubernetes**: FIPS-compliant, CIS hardened Kubernetes distribution
- **Keycloak IAM**: Enterprise identity and access management with OIDC/SAML
- **Istio Service Mesh**: mTLS, traffic management, ingress/egress control
- **MinIO Object Storage**: S3-compatible distributed storage
- **Trivy Security Scanning**: Continuous vulnerability scanning for containers
- **OPA Gatekeeper**: Policy-as-code enforcement
- **Custom Resource Definitions**: Easy application deployment with `SIABApplication` CRD
- **Landing Dashboard**: Centralized portal for platform access

## Quick Start

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

## Requirements

- Rocky Linux 8.x or 9.x
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

## Support

- Documentation: [docs/](./docs/)
- Issues: [GitHub Issues](https://github.com/morbidsteve/SIAB/issues)

## License

Apache License 2.0
